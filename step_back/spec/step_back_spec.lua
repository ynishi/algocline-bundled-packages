--- Tests for step_back package (Step-Back Prompting, Zheng et al. 2023
--- arXiv:2310.06117). M.run() drives alc.llm five times in the default
--- (verified) path and six times in the revised path; both are
--- exercised via a stubbed alc.llm that classifies the call by a
--- prompt substring.
---
--- Run via:
---   just alc-pkg-test-file step_back/spec/step_back_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.verified — if true (default), verification returns
---     "VERIFIED ...". If false, returns "needs fix" and revision fires.
local function mock_alc(opts)
    opts = opts or {}
    local verified = opts.verified
    if verified == nil then verified = true end

    local call_log = {}
    local log_calls = {}
    local c = { sbq = 0, principle = 0, solution = 0, verify = 0, revise = 0 }

    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            -- Order matters: revise prompt contains "Previous solution"
            -- AND "Verification feedback"; check it before verify.
            if prompt:find("Verification feedback", 1, true) then
                c.revise = c.revise + 1
                return "revised_" .. c.revise
            elseif prompt:find("output VERIFIED", 1, true) then
                c.verify = c.verify + 1
                if verified then
                    return "VERIFIED — looks consistent"
                else
                    return "needs fix at line 2"
                end
            elseif prompt:find("Reply with ONLY the step%-back question") then
                c.sbq = c.sbq + 1
                return "sbq_" .. c.sbq
            elseif prompt:find("apply these principles", 1, true) then
                c.solution = c.solution + 1
                return "solution_" .. c.solution
            else
                c.principle = c.principle + 1
                return "principle_" .. c.principle
            end
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls
end

local function reset()
    _G.alc = nil
    package.loaded["step_back"] = nil
end

-- ================================================================
-- meta
-- ================================================================

describe("step_back.meta", function()
    reset()
    mock_alc()
    local sb = require("step_back")

    it("has correct name", function()
        expect(sb.meta.name).to.equal("step_back")
    end)

    it("has version 0.1.0", function()
        expect(sb.meta.version).to.equal("0.1.0")
    end)

    it("has category 'reasoning'", function()
        expect(sb.meta.category).to.equal("reasoning")
    end)

    it("has a non-empty description", function()
        expect(type(sb.meta.description)).to.equal("string")
        expect(#sb.meta.description > 0).to.equal(true)
    end)
end)

-- ================================================================
-- spec
-- ================================================================

describe("step_back.spec", function()
    reset()
    mock_alc()
    local sb = require("step_back")
    local run_entry = sb.spec.entries.run

    it("declares a run entry with input and result shapes", function()
        expect(run_entry).to_not.equal(nil)
        expect(run_entry.input).to_not.equal(nil)
        expect(run_entry.result).to_not.equal(nil)
    end)
end)

-- ================================================================
-- M.run — verified path (no revision)
-- ================================================================

describe("step_back.run verified path", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local sb = require("step_back")
        local ok, err = pcall(sb.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default levels=1 → 2+1+1 = 4 LLM calls and verified=true", function()
        reset()
        local log = mock_alc({ verified = true })
        local sb = require("step_back")
        local ctx = sb.run({ task = "Why does ice float?" })
        expect(#log).to.equal(4)
        expect(#ctx.result.abstractions).to.equal(1)
        expect(ctx.result.verified).to.equal(true)
        expect(ctx.result.revised).to.equal(false)
        expect(ctx.result.answer).to.equal("solution_1")
    end)

    it("levels=2 → 4+1+1 = 6 LLM calls", function()
        reset()
        local log = mock_alc({ verified = true })
        local sb = require("step_back")
        local ctx = sb.run({ task = "T", abstraction_levels = 2 })
        expect(#log).to.equal(6)
        expect(#ctx.result.abstractions).to.equal(2)
        expect(ctx.result.abstractions[1].level).to.equal(1)
        expect(ctx.result.abstractions[2].level).to.equal(2)
    end)

    it("populates each abstraction with level / question / principle", function()
        reset()
        mock_alc({ verified = true })
        local sb = require("step_back")
        local ctx = sb.run({ task = "T", abstraction_levels = 2 })
        expect(ctx.result.abstractions[1].question).to.equal("sbq_1")
        expect(ctx.result.abstractions[1].principle).to.equal("principle_1")
        expect(ctx.result.abstractions[2].question).to.equal("sbq_2")
        expect(ctx.result.abstractions[2].principle).to.equal("principle_2")
    end)

    it("level-2 step-back question targets the level-1 question", function()
        reset()
        local log = mock_alc({ verified = true })
        local sb = require("step_back")
        sb.run({ task = "T", abstraction_levels = 2 })
        -- log order: sbq1, prin1, sbq2, prin2, solution, verify
        local sbq2_prompt = log[3].prompt
        expect(sbq2_prompt:find("Original question: sbq_1", 1, true)).to_not.equal(nil)
    end)

    it("domain_hint is embedded only in the level-1 step-back prompt", function()
        reset()
        local log = mock_alc({ verified = true })
        local sb = require("step_back")
        sb.run({ task = "T", abstraction_levels = 2, domain_hint = "physics" })
        local sbq1_prompt = log[1].prompt
        local sbq2_prompt = log[3].prompt
        expect(sbq1_prompt:find("Domain: physics", 1, true)).to_not.equal(nil)
        expect(sbq2_prompt:find("Domain: physics", 1, true)).to.equal(nil)
    end)

    it("solution and verify prompts both embed the principles text", function()
        reset()
        local log = mock_alc({ verified = true })
        local sb = require("step_back")
        sb.run({ task = "T" })
        local solution_prompt = log[3].prompt
        local verify_prompt = log[4].prompt
        expect(solution_prompt:find("principle_1", 1, true)).to_not.equal(nil)
        expect(verify_prompt:find("principle_1", 1, true)).to_not.equal(nil)
        expect(verify_prompt:find("solution_1", 1, true)).to_not.equal(nil)
    end)
end)

-- ================================================================
-- M.run — revised path
-- ================================================================

describe("step_back.run revised path", function()
    it("triggers revision when verifier does not say VERIFIED (5 calls)", function()
        reset()
        local log = mock_alc({ verified = false })
        local sb = require("step_back")
        local ctx = sb.run({ task = "T" })
        -- sbq1, prin1, solution, verify, revise = 5
        expect(#log).to.equal(5)
        expect(ctx.result.verified).to.equal(false)
        expect(ctx.result.revised).to.equal(true)
        expect(ctx.result.answer).to.equal("revised_1")
    end)

    it("revision prompt embeds verification feedback and prior solution", function()
        reset()
        local log = mock_alc({ verified = false })
        local sb = require("step_back")
        sb.run({ task = "T" })
        local revise_prompt = log[#log].prompt
        expect(revise_prompt:find("needs fix at line 2", 1, true)).to_not.equal(nil)
        expect(revise_prompt:find("solution_1", 1, true)).to_not.equal(nil)
    end)
end)

reset()
