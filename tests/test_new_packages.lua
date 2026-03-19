--- Tests for new packages: s2a, plan_solve, rstar, faithful, moa, bot
--- Structural tests + parse logic tests (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

--- Build a mock alc global. call_log records all llm calls.
--- llm_fn is called with (prompt, opts) and should return a string.
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
            -- minimal: not needed by these 6 packages
            return nil
        end,
    }
    _G.alc = a
    return call_log
end

--- Reset alc and unload packages from cache.
local function reset()
    _G.alc = nil
    for _, name in ipairs({ "s2a", "plan_solve", "rstar", "faithful", "moa", "bot" }) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- s2a
-- ================================================================
describe("s2a", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("s2a")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("s2a")
        expect(m.meta.category).to.equal("preprocessing")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("uses 2 LLM calls with context", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "denoised relevant facts only" end
            return "answer based on clean context"
        end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ctx = m.run({ task = "What is X?", context = "Noisy irrelevant text about X" })
        expect(#log).to.equal(2)
        expect(ctx.result.denoised_context).to.equal("denoised relevant facts only")
        expect(ctx.result.answer).to.equal("answer based on clean context")
    end)

    it("uses 2 LLM calls without context (denoises task itself)", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "reformulated question" end
            return "clean answer"
        end)
        package.loaded["s2a"] = nil
        local m = require("s2a")
        local ctx = m.run({ task = "Don't you think X is great?" })
        expect(#log).to.equal(2)
        expect(ctx.result.denoised_context).to.equal("reformulated question")
    end)
end)

-- ================================================================
-- plan_solve
-- ================================================================
describe("plan_solve", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("plan_solve")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("plan_solve")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["plan_solve"] = nil
        local m = require("plan_solve")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("counts plan steps correctly", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then
                return "1. Identify variables\n2. Set up equation\n3. Solve\n4. Verify"
            elseif n == 2 then
                return "Step 1: x=5. Step 2: 5+3=8. Step 3: verified. Answer: 8"
            else
                return "The answer is 8."
            end
        end)
        package.loaded["plan_solve"] = nil
        local m = require("plan_solve")
        local ctx = m.run({ task = "What is 5+3?" })
        expect(ctx.result.plan_steps).to.equal(4)
        expect(#log).to.equal(3) -- plan + execute + extract
    end)

    it("skips extraction when extract=false", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "1. Do it" end
            return "Done: 42"
        end)
        package.loaded["plan_solve"] = nil
        local m = require("plan_solve")
        local ctx = m.run({ task = "Compute", extract = false })
        expect(#log).to.equal(2) -- plan + execute only
        expect(ctx.result.answer).to.equal("Done: 42")
    end)
end)

-- ================================================================
-- rstar
-- ================================================================
describe("rstar", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("rstar")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("rstar")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("full agreement = 4 LLM calls, no resolution", function()
        local call_count = 0
        local log = mock_alc(function(prompt, _, n)
            call_count = call_count + 1
            -- Paths (called via alc.map, so n tracks global count)
            if prompt:match("first principles") then
                return "Step 1: analyze. Step 2: conclude. Conclusion: 42"
            elseif prompt:match("multiple angles") then
                return "Approach A: 42. Approach B: 42. Conclusion: 42"
            elseif prompt:match("Verify Path") then
                return "All steps are correct. VERDICT: AGREE"
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "What is the answer?" })
        expect(ctx.result.agreement).to.equal("full")
        expect(ctx.result.resolution_needed).to.equal(false)
        -- 2 (paths) + 2 (verifications) = 4
        expect(#log).to.equal(4)
    end)

    it("mutual disagreement = 5 LLM calls with resolution", function()
        local log = mock_alc(function(prompt)
            if prompt:match("first principles") then
                return "Conclusion: 42"
            elseif prompt:match("multiple angles") then
                return "Conclusion: 99"
            elseif prompt:match("Verify Path") then
                return "The reasoning has errors. VERDICT: DISAGREE. Wrong formula."
            elseif prompt:match("Two solvers produced") then
                return "After analysis, the correct answer is 42."
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "Solve" })
        expect(ctx.result.agreement).to.equal("none")
        expect(ctx.result.resolution_needed).to.equal(true)
        -- 2 paths + 2 verifications + 1 resolution = 5
        expect(#log).to.equal(5)
    end)

    it("partial agreement (A agrees B, B disagrees A) = uses B", function()
        local log = mock_alc(function(prompt)
            if prompt:match("first principles") then
                return "Conclusion: wrong answer"
            elseif prompt:match("multiple angles") then
                return "Conclusion: correct answer"
            elseif prompt:match("A_checks_B") or prompt:match("Path B") and prompt:match("Verify") then
                -- A checking B
                if prompt:match("Your reasoning %(Path A%)") then
                    return "Path B looks correct. VERDICT: AGREE"
                end
                -- B checking A
                return "Path A has errors. VERDICT: DISAGREE"
            end
            -- Disambiguation: first verify call = A checks B, second = B checks A
            if prompt:match("Verify Path B") then
                return "Looks correct. VERDICT: AGREE"
            elseif prompt:match("Verify Path A") then
                return "Has errors. VERDICT: DISAGREE"
            end
            return "mock"
        end)
        package.loaded["rstar"] = nil
        local m = require("rstar")
        local ctx = m.run({ task = "Solve" })
        expect(ctx.result.agreement).to.equal("partial")
        expect(ctx.result.resolution_needed).to.equal(false)
        expect(#log).to.equal(4) -- no resolution needed
    end)
end)

-- ================================================================
-- faithful
-- ================================================================
describe("faithful", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("faithful")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("faithful")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("auto-detects 'code' format for math tasks", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "Step 1: 5+3=8" end
            if n == 2 then return "print(5+3)" end
            if n == 3 then return "EXPECTED OUTPUT: 8\nERRORS FOUND: NONE\nCORRECTED ANSWER: 8" end
            return "The answer is 8."
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "Calculate 5+3" })
        expect(ctx.result.format).to.equal("code")
        expect(ctx.result.errors_found).to.equal(false)
        expect(#log).to.equal(4)
    end)

    it("auto-detects 'logic' format for logical tasks", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "All A are B. X is A. Therefore X is B." end
            if n == 2 then return "P1: All A are B\nP2: X is A\nCONCLUSION: X is B\nVALIDITY: VALID" end
            if n == 3 then return "VALIDITY: VALID\nERRORS FOUND: NONE\nCORRECTED CONCLUSION: X is B" end
            return "X is B."
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "If all cats are animals and Whiskers is a cat, is Whiskers an animal?" })
        expect(ctx.result.format).to.equal("logic")
    end)

    it("detects errors when verification finds issues", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "reasoning" end
            if n == 2 then return "code" end
            if n == 3 then return "ERRORS FOUND: Off-by-one in loop\nCORRECTED ANSWER: 7" end
            return "Corrected: 7"
        end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "Calculate something", format = "code" })
        expect(ctx.result.errors_found).to.equal(true)
    end)

    it("respects explicit format override", function()
        local log = mock_alc(function() return "mock\nERRORS FOUND: NONE" end)
        package.loaded["faithful"] = nil
        local m = require("faithful")
        local ctx = m.run({ task = "generic task", format = "logic" })
        expect(ctx.result.format).to.equal("logic")
    end)
end)

-- ================================================================
-- moa
-- ================================================================
describe("moa", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("moa")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("moa")
        expect(m.meta.category).to.equal("selection")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["moa"] = nil
        local m = require("moa")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("default config: 3 agents x 2 layers + 1 agg = 7 calls", function()
        local log = mock_alc(function() return "agent response" end)
        package.loaded["moa"] = nil
        local m = require("moa")
        local ctx = m.run({ task = "Solve X" })
        -- 3 (layer1) + 3 (layer2) + 1 (aggregation) = 7
        expect(#log).to.equal(7)
        expect(ctx.result.n_agents).to.equal(3)
        expect(ctx.result.n_layers).to.equal(2)
        expect(ctx.result.total_calls).to.equal(7)
    end)

    it("custom config: 2 agents x 1 layer = 3 calls", function()
        local log = mock_alc(function() return "resp" end)
        package.loaded["moa"] = nil
        local m = require("moa")
        local ctx = m.run({ task = "Q", n_agents = 2, n_layers = 1 })
        -- 2 (layer1) + 1 (aggregation) = 3
        expect(#log).to.equal(3)
        expect(ctx.result.total_calls).to.equal(3)
    end)

    it("layer 2 prompts reference layer 1 outputs", function()
        local layer2_saw_refs = false
        local call_count = 0
        mock_alc(function(prompt)
            call_count = call_count + 1
            if call_count > 2 and call_count <= 4 then
                -- Layer 2 calls (agents 1-2, with n_agents=2)
                if prompt:match("Other agents have provided") then
                    layer2_saw_refs = true
                end
            end
            return "response " .. call_count
        end)
        package.loaded["moa"] = nil
        local m = require("moa")
        m.run({ task = "Q", n_agents = 2, n_layers = 2 })
        expect(layer2_saw_refs).to.equal(true)
    end)

    it("caps agents to persona count", function()
        local log = mock_alc(function() return "r" end)
        package.loaded["moa"] = nil
        local m = require("moa")
        local ctx = m.run({ task = "Q", n_agents = 100, n_layers = 1 })
        -- Should cap to 5 (PERSONAS count) + 1 aggregation
        expect(ctx.result.n_agents).to.equal(5)
        expect(#log).to.equal(6)
    end)
end)

-- ================================================================
-- bot
-- ================================================================
describe("bot", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("bot")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("bot")
        expect(m.meta.category).to.equal("reasoning")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("classifies and uses arithmetic template", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "arithmetic" end
            if n == 2 then return "Step 1: x=5. Step 2: 5*3=15" end
            if n == 3 then return "ERRORS: NONE\nFINAL ANSWER: The result is 15." end
            return "mock"
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Calculate 5*3" })
        expect(ctx.result.template_key).to.equal("arithmetic")
        expect(ctx.result.errors_found).to.equal(false)
        expect(ctx.result.answer).to.equal("The result is 15.")
        expect(#log).to.equal(3)
    end)

    it("classifies logic template", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "logic" end
            if n == 2 then return "Premises identified..." end
            return "ERRORS: NONE\nFINAL ANSWER: Valid syllogism."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Is this syllogism valid?" })
        expect(ctx.result.template_key).to.equal("logic")
    end)

    it("falls back to analytical for unrecognized classification", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "xyzzy_unknown_type" end
            if n == 2 then return "analysis..." end
            return "ERRORS: NONE\nFINAL ANSWER: Done."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Something unusual" })
        expect(ctx.result.template_key).to.equal("analytical")
    end)

    it("detects errors in verification", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "arithmetic" end
            if n == 2 then return "wrong calculation" end
            return "ERRORS: Step 2 used wrong formula\nFINAL ANSWER: Corrected to 42."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({ task = "Calculate" })
        expect(ctx.result.errors_found).to.equal(true)
        expect(ctx.result.answer).to.equal("Corrected to 42.")
    end)

    it("accepts custom templates", function()
        mock_alc(function(_, _, n)
            if n == 1 then return "custom" end
            if n == 2 then return "custom reasoning" end
            return "ERRORS: NONE\nFINAL ANSWER: Custom result."
        end)
        package.loaded["bot"] = nil
        local m = require("bot")
        local ctx = m.run({
            task = "Do custom thing",
            templates = {
                custom = {
                    name = "Custom Template",
                    pattern = "1. Custom step\n2. Custom step 2",
                },
            },
        })
        expect(ctx.result.template_key).to.equal("custom")
        expect(ctx.result.template_name).to.equal("Custom Template")
    end)
end)
