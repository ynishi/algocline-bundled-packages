--- Tests for ambig package (Interactive Agents for Underspecified
--- Software Engineering Tasks, AMBIG-SWE ICLR 2026).
---
--- Run via:
---   just alc-pkg-test-file ambig/spec/ambig_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local DETECTION_SPEC =
    "- input_format: takes JSON file [SPECIFIED]\n"
 .. "- output_format: writes CSV file [SPECIFIED]\n"
 .. "VERDICT: SPECIFIED\n"

local DETECTION_UNDER =
    "- input_format: takes JSON file [SPECIFIED]\n"
 .. "- output_format: unknown column order [UNDERSPECIFIED]\n"
 .. "- delimiter: missing pick [UNDERSPECIFIED]\n"
 .. "VERDICT: UNDERSPECIFIED\n"

local QUESTIONS_TEXT =
    "1. What column order do you want?\n"
 .. "2. Should we use comma or tab?\n"

--- Build a mock _G.alc.
---   opts.detection_text — Phase 1 detection output.
---   opts.questions_text — Phase 2 questions output.
local function mock_alc(opts)
    opts = opts or {}
    local detection_text = opts.detection_text or DETECTION_UNDER
    local questions_text = opts.questions_text or QUESTIONS_TEXT
    local call_log = {}
    local log_calls = {}
    local specify_calls = {}
    local c = { detect = 0, clarify = 0, integrate = 0, specify = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Analyze this task for underspecification", 1, true) then
                c.detect = c.detect + 1
                return detection_text
            elseif prompt:find("Generate exactly one clarification question", 1, true) then
                c.clarify = c.clarify + 1
                return questions_text
            else
                c.integrate = c.integrate + 1
                return "integrated_task_text"
            end
        end,
        specify = function(prompt, options)
            c.specify = c.specify + 1
            specify_calls[#specify_calls + 1] = { prompt = prompt, opts = options }
            return "user_clarifications"
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls, specify_calls
end

local function reset()
    _G.alc = nil
    package.loaded["ambig"] = nil
end

describe("ambig.meta", function()
    reset()
    mock_alc()
    local m = require("ambig")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("ambig")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("intent")
    end)
end)

describe("ambig.spec", function()
    reset()
    mock_alc()
    local m = require("ambig")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("ambig.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("ambig")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("VERDICT: SPECIFIED early-returns (1 LLM call, no specify)", function()
        reset()
        local log, _, specify_log = mock_alc({ detection_text = DETECTION_SPEC })
        local m = require("ambig")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(1)
        expect(#specify_log).to.equal(0)
        expect(ctx.result.verdict).to.equal("specified")
        expect(ctx.result.was_underspecified).to.equal(false)
        expect(ctx.result.specified_task).to.equal("T")
        expect(#ctx.result.elements).to.equal(2)
    end)

    it("VERDICT: UNDERSPECIFIED runs detect + clarify + integrate (3 LLM + 1 specify)", function()
        reset()
        local log, _, specify_log = mock_alc()
        local m = require("ambig")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(3)
        expect(#specify_log).to.equal(1)
        expect(ctx.result.verdict).to.equal("underspecified")
        expect(ctx.result.was_underspecified).to.equal(true)
        expect(ctx.result.specified_task).to.equal("integrated_task_text")
        expect(ctx.result.user_response).to.equal("user_clarifications")
    end)

    it("elements parsed with name / description / status", function()
        reset()
        mock_alc()
        local m = require("ambig")
        local ctx = m.run({ task = "T" })
        -- 3 elements: 1 specified + 2 underspecified
        expect(#ctx.result.elements).to.equal(3)
        local spec = ctx.result.elements[1]
        expect(spec.name).to.equal("input_format")
        expect(spec.status).to.equal("specified")
        expect(ctx.result.elements[2].status).to.equal("underspecified")
    end)

    it("clarifications cover only underspecified elements", function()
        reset()
        mock_alc()
        local m = require("ambig")
        local ctx = m.run({ task = "T" })
        expect(#ctx.result.clarifications).to.equal(2)
        expect(ctx.result.clarifications[1].element).to.equal("output_format")
        expect(ctx.result.clarifications[1].question:find("column order")).to_not.equal(nil)
        expect(ctx.result.clarifications[2].element).to.equal("delimiter")
    end)

    it("integration prompt embeds original task + user response", function()
        reset()
        local log = mock_alc()
        local m = require("ambig")
        m.run({ task = "ORIGINAL_TASK_42" })
        local integ_prompt = log[3].prompt
        expect(integ_prompt:find("ORIGINAL_TASK_42", 1, true)).to_not.equal(nil)
        expect(integ_prompt:find("user_clarifications", 1, true)).to_not.equal(nil)
    end)
end)

reset()
