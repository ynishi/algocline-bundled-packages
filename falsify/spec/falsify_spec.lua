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
    for _, name in ipairs({ "falsify" }) do
        package.loaded[name] = nil
    end
end

describe("falsify", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("falsify")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("falsify")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates initial hypotheses", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose hypothesis") then
                return "Hypothesis text " .. n
            end
            if prompt:match("DISPROVE") then
                return "Cannot find counterexample"
            end
            if prompt:match("Judge the falsification") then
                return "SURVIVED"
            end
            if prompt:match("Synthesize") then
                return "Final synthesis"
            end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Why is the sky blue?",
            initial_hypotheses = 2,
            max_rounds = 1,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.stats.initial_count).to.equal(2)
        expect(ctx.result.stats.total_survived).to.equal(2)
        expect(#ctx.result.survivors).to.equal(2)
        expect(ctx.result.answer).to.equal("Final synthesis")
    end)

    it("refutes hypotheses and derives successors", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose hypothesis") then
                return "Hypothesis " .. n
            end
            if prompt:match("DISPROVE") then
                return "Found clear counterexample: X contradicts the hypothesis"
            end
            if prompt:match("Judge the falsification") then
                return "REFUTED"
            end
            if prompt:match("IMPROVED hypothesis") then
                return "Derived successor hypothesis"
            end
            if prompt:match("Synthesize") or prompt:match("All hypotheses were refuted") then
                return "Synthesis from survivors"
            end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Analyze X",
            initial_hypotheses = 2,
            max_rounds = 1,
            derive_on_refute = true,
        })
        expect(ctx.result.stats.total_refuted > 0).to.equal(true)
        expect(ctx.result.stats.total_derived > 0).to.equal(true)
        -- Total generated = initial + derived
        expect(ctx.result.stats.total_generated > 2).to.equal(true)
    end)

    it("respects derive_on_refute=false", function()
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then return "Counterexample found" end
            if prompt:match("Judge") then return "REFUTED" end
            if prompt:match("refuted") then return "Answer from nothing" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 2,
            max_rounds = 1,
            derive_on_refute = false,
        })
        expect(ctx.result.stats.total_derived).to.equal(0)
        expect(ctx.result.stats.total_generated).to.equal(2)
    end)

    it("weakened verdict lowers confidence but keeps active", function()
        local round = 0
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then
                round = round + 1
                return "Partial flaw found"
            end
            if prompt:match("Judge") then return "WEAKENED" end
            if prompt:match("Synthesize") then return "Answer" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 1,
            max_rounds = 2,
        })
        -- Weakened twice: 0.5 - 0.2 - 0.2 = 0.1
        local h = ctx.result.all_hypotheses[1]
        expect(h.status).to.equal("survived")
        expect(h.confidence < 0.5).to.equal(true)
    end)

    it("max_hypotheses limits derived count", function()
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then return "counter" end
            if prompt:match("Judge") then return "REFUTED" end
            if prompt:match("IMPROVED") then return "derived" end
            if prompt:match("Synthesize") or prompt:match("refuted") then return "A" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")

        -- max_hypotheses=3: 5 initial hypotheses, all refuted in round 1.
        -- After each refute, active_count = remaining_active + new_hypotheses.
        -- 1st refute: 4 active + 0 new = 4 ≥ 3 → NO derive
        -- 2nd refute: 3 active + 0 new = 3 ≥ 3 → NO derive
        -- 3rd refute: 2 active + 0 new = 2 < 3 → derive → 1 new
        -- 4th refute: 1 active + 1 new = 2 < 3 → derive → 2 new
        -- 5th refute: 0 active + 2 new = 2 < 3 → derive → 3 new
        -- Total derived in round 1 = 3 (not 5)
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 5,
            max_rounds = 1,
            max_hypotheses = 3,
        })
        -- Should derive fewer than refuted due to cap
        expect(ctx.result.stats.total_refuted).to.equal(5)
        expect(ctx.result.stats.total_derived).to.equal(3)
    end)
end)
