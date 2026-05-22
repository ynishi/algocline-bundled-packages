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
    for _, name in ipairs({ "coevolve" }) do
        package.loaded[name] = nil
    end
end

describe("coevolve", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("coevolve")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("coevolve")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates seed problems when none provided", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Problem: what is 2+2?" end
            if prompt:match("Solve this problem") then return "The answer is 4" end
            if prompt:match("Judge the answer") then return "CORRECT\nWell done" end
            if prompt:match("CHALLENGER") then return "Problem: what is 3*7?" end
            if prompt:match("everything you learned") then return "Final comprehensive answer" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Arithmetic reasoning",
            rounds = 2,
            problems_per_round = 2,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.answer).to.equal("Final comprehensive answer")
        expect(#ctx.result.round_stats).to.equal(2)
        expect(ctx.result.total_problems > 0).to.equal(true)
    end)

    it("accepts seed_problems", function()
        mock_alc(function(prompt)
            if prompt:match("Solve") then return "answer" end
            if prompt:match("Judge") then return "CORRECT\nGood" end
            if prompt:match("CHALLENGER") then return "New problem" end
            if prompt:match("battle%-tested") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Math",
            seed_problems = { "What is 1+1?", "What is 2*3?" },
            rounds = 1,
        })
        expect(ctx.result.total_problems).to.equal(2)
    end)

    it("tracks correct/partial/wrong counts", function()
        local judge_n = 0
        mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Problem" end
            if prompt:match("Solve this problem") then return "answer" end
            if prompt:match("Judge the answer") then
                judge_n = judge_n + 1
                if judge_n == 1 then return "CORRECT\nRight" end
                if judge_n == 2 then return "WRONG\nIncorrect" end
                return "PARTIAL\nAlmost"
            end
            if prompt:match("everything you learned") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Test",
            rounds = 1,
            problems_per_round = 3,
        })
        expect(ctx.result.total_correct).to.equal(1)
        expect(ctx.result.total_wrong).to.equal(1)
        expect(ctx.result.total_partial).to.equal(1)
    end)

    it("difficulty adjusts based on success rate", function()
        mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Easy problem" end
            if prompt:match("Solve") then return "correct answer" end
            if prompt:match("Judge") then return "CORRECT\nPerfect" end
            if prompt:match("CHALLENGER") then return "Should be harder" end
            if prompt:match("battle%-tested") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Test",
            rounds = 2,
            problems_per_round = 2,
            difficulty_target = 0.5,
        })
        -- All correct → success_rate=1.0 > target+0.2 → "harder"
        expect(ctx.result.round_stats[1].success_rate).to.equal(1.0)
        expect(ctx.result.round_stats[1].difficulty_hint:match("harder")).to_not.equal(nil)
    end)
end)
