--- Tests for reflect package (Self-Refine, Madaan et al. 2023
--- arXiv:2303.17651). Generate → Critique → Revise loop.
---
--- Run via:
---   just alc-pkg-test-file reflect/spec/reflect_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.critique_sequence — list of critique strings returned in order.
---     Use "NO_MAJOR_ISSUES" to converge. After the list is exhausted,
---     the stub keeps returning the last element.
local function mock_alc(opts)
    opts = opts or {}
    local critiques = opts.critique_sequence or { "needs work" }
    local call_log = {}
    local log_calls = {}
    local c = { gen = 0, critique = 0, revise = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Critique this draft", 1, true) then
                c.critique = c.critique + 1
                return critiques[math.min(c.critique, #critiques)]
            elseif prompt:find("Revise the draft", 1, true) then
                c.revise = c.revise + 1
                return "revised_" .. c.revise
            else
                c.gen = c.gen + 1
                return "draft_" .. c.gen
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
    package.loaded["reflect"] = nil
end

describe("reflect.meta", function()
    reset()
    mock_alc()
    local r = require("reflect")

    it("name / version / category", function()
        expect(r.meta.name).to.equal("reflect")
        expect(r.meta.version).to.equal("0.1.0")
        expect(r.meta.category).to.equal("refinement")
    end)
end)

describe("reflect.spec", function()
    reset()
    mock_alc()
    local r = require("reflect")
    it("exposes run input + result shapes", function()
        expect(r.spec.entries.run.input).to_not.equal(nil)
        expect(r.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("reflect.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local r = require("reflect")
        local ok, err = pcall(r.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("converges immediately on NO_MAJOR_ISSUES (1 gen + 1 critique = 2 calls)", function()
        reset()
        local log = mock_alc({ critique_sequence = { "NO_MAJOR_ISSUES looks good" } })
        local r = require("reflect")
        local ctx = r.run({ task = "T" })
        expect(#log).to.equal(2)
        expect(ctx.result.converged).to.equal(true)
        expect(ctx.result.total_rounds).to.equal(1)
        expect(ctx.result.rounds[1].converged).to.equal(true)
        expect(ctx.result.output).to.equal("draft_1")
    end)

    it("loops once then converges (gen + crit + rev + crit = 4 calls)", function()
        reset()
        local log = mock_alc({ critique_sequence = { "needs fix", "NO_MAJOR_ISSUES" } })
        local r = require("reflect")
        local ctx = r.run({ task = "T" })
        expect(#log).to.equal(4)
        expect(ctx.result.total_rounds).to.equal(2)
        expect(ctx.result.converged).to.equal(true)
        expect(ctx.result.output).to.equal("revised_1")
    end)

    it("hits max_rounds when never converging", function()
        reset()
        local log = mock_alc({ critique_sequence = { "fix", "fix", "fix" } })
        local r = require("reflect")
        local ctx = r.run({ task = "T", max_rounds = 2 })
        -- gen + crit + rev + crit + rev = 5 (loop body always finishes
        -- with revise; convergence check only short-circuits the revise)
        expect(#log).to.equal(5)
        expect(ctx.result.total_rounds).to.equal(2)
        expect(ctx.result.converged).to.equal(false)
    end)

    it("skips initial generation when initial_draft is supplied", function()
        reset()
        local log = mock_alc({ critique_sequence = { "NO_MAJOR_ISSUES" } })
        local r = require("reflect")
        local ctx = r.run({ task = "T", initial_draft = "preset draft" })
        -- only critique runs (1 call)
        expect(#log).to.equal(1)
        expect(ctx.result.output).to.equal("preset draft")
        -- critique prompt receives the supplied draft
        expect(log[1].prompt:find("preset draft", 1, true)).to_not.equal(nil)
    end)

    it("stop_when='no_issues' rejects NO_MAJOR_ISSUES as convergence", function()
        reset()
        local log = mock_alc({ critique_sequence = { "NO_MAJOR_ISSUES", "NO_ISSUES" } })
        local r = require("reflect")
        local ctx = r.run({ task = "T", stop_when = "no_issues" })
        -- gen + crit(NO_MAJOR_ISSUES, no stop) + rev + crit(NO_ISSUES, stop) = 4
        expect(#log).to.equal(4)
        expect(ctx.result.total_rounds).to.equal(2)
        expect(ctx.result.converged).to.equal(true)
    end)
end)

reset()
