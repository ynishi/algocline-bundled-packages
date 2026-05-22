--- Tests for step_verify.
--- Extracted from tests/test_tier1_2.lua (Phase C decomposition).

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
            local score = s:match('"score"%s*:%s*(%d+)')
            local passed = s:match('"passed"%s*:%s*(true)')
            local fb = s:match('"feedback"%s*:%s*"([^"]*)"')
            if score then
                return {
                    score = tonumber(score),
                    passed = passed ~= nil,
                    feedback = fb or "",
                }
            end
            return nil
        end,
        stats = { record = function() end },
    }
    _G.alc = a
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["step_verify"] = nil
end

describe("step_verify", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("step_verify")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("step_verify")
        expect(m.meta.category).to.equal("validation")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("all steps correct = no re-derive, 1 round", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then
                return "Step 1: Identify 2+2\nStep 2: Calculate 2+2=4\nStep 3: Answer is 4"
            end
            -- Verification calls
            if prompt:match("verify") or prompt:match("Verify") or prompt:match("VERDICT") then
                return "This step is logically sound. VERDICT: CORRECT"
            end
            -- Synthesis
            return "The answer is 4."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "What is 2+2?" })
        expect(ctx.result.total_rounds).to.equal(1)
        expect(ctx.result.total_verified > 0).to.equal(true)
        expect(ctx.result.answer).to.equal("The answer is 4.")
    end)

    it("error at step 2 triggers re-derive", function()
        local gen_calls = 0
        local log = mock_alc(function(prompt, _, n)
            -- Generation calls: "Solve step by step" or "Continue from"
            if prompt:match("Solve step by step") or prompt:match("Continue from") or prompt:match("Verified correct steps") then
                gen_calls = gen_calls + 1
                if gen_calls == 1 then
                    return "Step 1: Setup equations\nStep 2: Wrong calculation\nStep 3: Bad conclusion"
                else
                    return "Step 2: Correct calculation\nStep 3: Right conclusion"
                end
            end
            -- Verification calls contain "to verify:"
            if prompt:match("to verify:") then
                -- Fail on "Wrong calculation"
                if prompt:match("Wrong calculation") then
                    return "Error found. VERDICT: INCORRECT"
                end
                return "Looks correct. VERDICT: CORRECT"
            end
            -- Synthesis (contains "final answer")
            return "Final answer."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "Solve", max_repair_rounds = 1 })
        -- Should have 2 generation calls (initial + re-derive)
        expect(gen_calls).to.equal(2)
        expect(ctx.result.total_rounds > 1).to.equal(true)
    end)

    it("respects max_repair_rounds=0 (no re-derive)", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Solve step by step") then
                return "Step 1: Only step"
            end
            if prompt:match("VERDICT") then
                return "VERDICT: INCORRECT"
            end
            return "Synthesized."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "X", max_repair_rounds = 0 })
        -- Only 1 round (round 0), no re-derive
        expect(ctx.result.total_rounds).to.equal(1)
    end)

    it("synthesis is always the last LLM call", function()
        local last_prompt = nil
        mock_alc(function(prompt)
            last_prompt = prompt
            if prompt:match("Solve step by step") then
                return "Step 1: One step"
            end
            if prompt:match("VERDICT") then
                return "VERDICT: CORRECT"
            end
            return "Final synthesis."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        m.run({ task = "Test" })
        expect(last_prompt:match("final answer")).to_not.equal(nil)
    end)
end)
