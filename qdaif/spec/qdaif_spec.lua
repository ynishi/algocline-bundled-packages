--- Tests extracted from tests/test_exploration.lua (Phase C decomposition).

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for _, item in ipairs(list) do
                results[#results + 1] = fn(item)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("%d+")) or 5
        end,
        json_decode = function(s)
            if type(s) ~= "string" then return nil end
            local t = {}
            for k, v in s:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
                local num = tonumber(v)
                if num then
                    t[k] = num
                else
                    t[k] = v:match('^"(.*)"$') or v
                end
            end
            return t
        end,
        json_encode = function(t)
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                if type(v) == "string" then
                    parts[#parts + 1] = string.format('"%s":"%s"', k, v)
                else
                    parts[#parts + 1] = string.format('"%s":%s', k, tostring(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
    }
    _G.alc = a
    return call_log
end

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "qdaif" }) do
        package.loaded[name] = nil
    end
end

describe("qdaif", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("qdaif")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("qdaif")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, {
            features = { { name = "style", bins = { "a", "b" } } },
        })
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.features", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, { task = "solve" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.features is required")).to_not.equal(nil)
    end)

    it("errors with single-bin feature", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, {
            task = "solve",
            features = { { name = "x", bins = { "only_one" } } },
        })
        expect(ok).to.equal(false)
        expect(err:match("bins")).to_not.equal(nil)
    end)

    it("seeds archive and runs mutation loop", function()
        local call_n = 0
        local log = mock_alc(function(prompt, opts, n)
            call_n = call_n + 1
            -- Seed generation
            if prompt:match("Generate a high%-quality solution") then
                return "solution candidate " .. call_n
            end
            -- Evaluation: return score + bins
            if prompt:match("SCORE:") or prompt:match("Evaluate this candidate") then
                return "SCORE: 7\nBINS: 1"
            end
            -- Mutation
            if prompt:match("Create a VARIANT") then
                return "mutated variant " .. call_n
            end
            return "mock " .. call_n
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "Write a greeting",
            features = { { name = "tone", bins = { "formal", "casual" } } },
            seed_count = 2,
            iterations = 3,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.best).to_not.equal(nil)
        expect(ctx.result.best_score > 0).to.equal(true)
        expect(ctx.result.stats.total_cells).to.equal(2)
        expect(ctx.result.stats.seed_count).to.equal(2)
        expect(ctx.result.stats.iterations).to.equal(3)
        expect(ctx.result.coverage > 0).to.equal(true)
        -- seed_count * 2 (generate + eval) + iterations * 2 (mutate + eval)
        expect(#log).to.equal(2 * 2 + 3 * 2)
    end)

    it("multi-axis features create correct grid", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "SCORE: 6\nBINS: 1, 2" end
            return "candidate"
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "test",
            features = {
                { name = "style", bins = { "formal", "casual", "technical" } },
                { name = "length", bins = { "short", "long" } },
            },
            seed_count = 1,
            iterations = 1,
        })
        expect(ctx.result.stats.total_cells).to.equal(6) -- 3 * 2
    end)

    it("archive replaces only when score improves", function()
        local eval_scores = { 8, 8, 3 } -- seed=8, seed_eval=8, mutation_eval=3
        local eval_idx = 0
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then
                eval_idx = eval_idx + 1
                local s = eval_scores[eval_idx] or 5
                return string.format("SCORE: %d\nBINS: 1", s)
            end
            return "candidate"
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "test",
            features = { { name = "x", bins = { "a", "b" } } },
            seed_count = 1,
            iterations = 1,
        })
        -- Best should be from seed (score 8), not mutation (score 3)
        expect(ctx.result.best_score).to.equal(8)
    end)
end)
