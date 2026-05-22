--- Tests for model_first package (Model-First Reasoning, Rana et al.
--- 2025 arXiv:2512.14474).
---
--- Run via:
---   just alc-pkg-test-file model_first/spec/model_first_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.verification_text — what the verify stub returns. Default
---     says "No violations found." (no repair triggered).
local function mock_alc(opts)
    opts = opts or {}
    local verification_text = opts.verification_text or "No violations found."
    local call_log = {}
    local log_calls = {}
    local c = { model = 0, solve = 0, verify = 0, repair = 0, extract = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Do NOT solve the problem yet", 1, true) then
                c.model = c.model + 1
                return "model_text entity constraint x"
            elseif prompt:find("Verify this solution against the model", 1, true) then
                c.verify = c.verify + 1
                return verification_text
            elseif prompt:find("Repair the solution to eliminate", 1, true) then
                c.repair = c.repair + 1
                return "repaired_solution"
            elseif prompt:find("Extract the final answer concisely", 1, true) then
                c.extract = c.extract + 1
                return "final_extracted"
            else
                c.solve = c.solve + 1
                return "initial_solution"
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
    package.loaded["model_first"] = nil
end

describe("model_first.meta", function()
    reset()
    mock_alc()
    local m = require("model_first")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("model_first")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("model_first.spec", function()
    reset()
    mock_alc()
    local m = require("model_first")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("model_first.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("model_first")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default (verify+extract, no violations) → model + solve + verify + extract = 4 calls", function()
        reset()
        local log = mock_alc()
        local m = require("model_first")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(4)
        expect(ctx.result.verified).to.equal(true)
        expect(ctx.result.violations_found).to.equal(0)
        expect(ctx.result.answer).to.equal("final_extracted")
        expect(ctx.result.solution).to.equal("initial_solution")
    end)

    it("verify=false → 2 LLM calls (model + solve), verified=false", function()
        reset()
        local log = mock_alc()
        local m = require("model_first")
        local ctx = m.run({ task = "T", verify = false, extract = false })
        expect(#log).to.equal(2)
        expect(ctx.result.verified).to.equal(false)
        expect(ctx.result.violations_found).to.equal(0)
    end)

    it("extract=false drops the final extraction step", function()
        reset()
        local log = mock_alc()
        local m = require("model_first")
        local ctx = m.run({ task = "T", extract = false })
        -- model + solve + verify = 3
        expect(#log).to.equal(3)
        expect(ctx.result.answer).to.equal("initial_solution")
    end)

    it("violations parsed → repair step fires, violations_found > 0", function()
        reset()
        local log = mock_alc({
            verification_text = "1. Violation: precondition failed at step 2\n2. Violation: capacity exceeded\n",
        })
        local m = require("model_first")
        local ctx = m.run({ task = "T" })
        -- model + solve + verify + repair + extract = 5
        expect(#log).to.equal(5)
        expect(ctx.result.violations_found).to.equal(2)
        expect(ctx.result.solution).to.equal("repaired_solution")
    end)

    it("'No violations found' triggers no repair", function()
        reset()
        local log = mock_alc({ verification_text = "No violations found." })
        local m = require("model_first")
        local ctx = m.run({ task = "T", extract = false })
        -- 3 calls; no repair
        expect(#log).to.equal(3)
        expect(ctx.result.violations_found).to.equal(0)
    end)
end)

reset()
