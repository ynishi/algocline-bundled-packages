--- Tests for prism package ("Prism: Towards Lowering User Cognitive
--- Load in LLMs via Complex Intent Understanding" 2026
--- arXiv:2601.08653).
---
--- Run via:
---   just alc-pkg-test-file prism/spec/prism_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local DECOMP_ALL_SPEC =
    "1. [SPECIFIED] gather inputs cleanly\n"
 .. "2. [SPECIFIED] write the result file\n"

local DECOMP_TWO_UNDER =
    "1. [UNDERSPECIFIED] choose the output format\n"
 .. "2. [UNDERSPECIFIED] decide the destination directory\n"
 .. "3. [SPECIFIED] log on completion\n"

--- Build a mock _G.alc.
---   opts.decomp_text — Phase 1 decomposition output.
---   opts.deps_text — Phase 2 dependency output ("1 -> 2" or "NONE").
---   opts.questions_text — Phase 3 question generation output.
local function mock_alc(opts)
    opts = opts or {}
    local decomp_text = opts.decomp_text or DECOMP_TWO_UNDER
    local deps_text = opts.deps_text or "1 -> 2\n"
    local questions_text = opts.questions_text
        or "1. What format do you want?\n2. Where should we put it?\n"
    local call_log = {}
    local log_calls = {}
    local specify_calls = {}
    local c = { decomp = 0, deps = 0, questions = 0, specified = 0, specify = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Decompose this request into atomic", 1, true) then
                c.decomp = c.decomp + 1
                return decomp_text
            elseif prompt:find("Identify logical dependencies", 1, true) then
                c.deps = c.deps + 1
                return deps_text
            elseif prompt:find("Generate one clear, concise clarification", 1, true) then
                c.questions = c.questions + 1
                return questions_text
            else
                c.specified = c.specified + 1
                return "fully_specified_task_text"
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
    package.loaded["prism"] = nil
end

describe("prism.meta", function()
    reset()
    mock_alc()
    local m = require("prism")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("prism")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("intent")
    end)
end)

describe("prism.spec", function()
    reset()
    mock_alc()
    local m = require("prism")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("prism.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("prism")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("fully-specified decomposition skips clarification (1 LLM call, was_underspecified=false)", function()
        reset()
        local log, _, specify_log = mock_alc({ decomp_text = DECOMP_ALL_SPEC })
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(1)
        expect(#specify_log).to.equal(0)
        expect(ctx.result.was_underspecified).to.equal(false)
        expect(ctx.result.specified_task).to.equal("T")
        expect(#ctx.result.clarifications).to.equal(0)
        expect(#ctx.result.dependencies).to.equal(0)
        expect(#ctx.result.sub_intents).to.equal(2)
    end)

    it("underspecified path runs all 4 LLM calls + 1 specify", function()
        reset()
        local log, _, specify_log = mock_alc()
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        -- decomp + deps + questions + specified = 4 LLM, plus 1 specify
        expect(#log).to.equal(4)
        expect(#specify_log).to.equal(1)
        expect(ctx.result.was_underspecified).to.equal(true)
        expect(ctx.result.specified_task).to.equal("fully_specified_task_text")
        expect(ctx.result.user_response).to.equal("user_clarifications")
    end)

    it("sub_intents carry text + status (specified/underspecified)", function()
        reset()
        mock_alc()
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.sub_intents[1].status).to.equal("underspecified")
        expect(ctx.result.sub_intents[1].text:find("choose the output format")).to_not.equal(nil)
        expect(ctx.result.sub_intents[3].status).to.equal("specified")
    end)

    it("dependencies parsed from '1 -> 2' lines", function()
        reset()
        mock_alc()
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        expect(#ctx.result.dependencies).to.equal(1)
        expect(ctx.result.dependencies[1].from).to.equal(1)
        expect(ctx.result.dependencies[1].to).to.equal(2)
    end)

    it("'NONE' dependency response yields empty deps list", function()
        reset()
        mock_alc({ deps_text = "NONE\n" })
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        expect(#ctx.result.dependencies).to.equal(0)
    end)

    it("clarifications cover only underspecified sub-intents (in topological order)", function()
        reset()
        mock_alc()
        local m = require("prism")
        local ctx = m.run({ task = "T" })
        expect(#ctx.result.clarifications).to.equal(2)
        -- 1 -> 2 dependency means 2 must be clarified before 1
        expect(ctx.result.clarifications[1].sub_intent_index).to.equal(2)
        expect(ctx.result.clarifications[2].sub_intent_index).to.equal(1)
    end)
end)

reset()
