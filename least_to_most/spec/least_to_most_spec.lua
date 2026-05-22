--- Tests for least_to_most package (Least-to-Most Prompting, Zhou et
--- al. 2022 arXiv:2205.10625).
---
--- Run via:
---   just alc-pkg-test-file least_to_most/spec/least_to_most_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.decomp_text — Phase 1 decomposition output (default: 3
---     parseable numbered lines).
local function mock_alc(opts)
    opts = opts or {}
    local decomp_text = opts.decomp_text
        or "1. easiest subproblem here\n2. medium subproblem here\n3. hardest subproblem here\n"
    local call_log = {}
    local log_calls = {}
    local c = { decomp = 0, solve = 0, synth = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Decompose this into subproblems", 1, true) then
                c.decomp = c.decomp + 1
                return decomp_text
            elseif prompt:find("Synthesize all solutions", 1, true) then
                c.synth = c.synth + 1
                return "synthesis_" .. c.synth
            else
                c.solve = c.solve + 1
                return "solution_" .. c.solve
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
    package.loaded["least_to_most"] = nil
end

describe("least_to_most.meta", function()
    reset()
    mock_alc()
    local m = require("least_to_most")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("least_to_most")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("least_to_most.spec", function()
    reset()
    mock_alc()
    local m = require("least_to_most")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("least_to_most.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("least_to_most")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("3-subproblem decomposition → 1 decomp + 3 solve + 1 synth = 5 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("least_to_most")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(5)
        expect(ctx.result.total_subproblems).to.equal(3)
        expect(#ctx.result.subproblems).to.equal(3)
        expect(ctx.result.answer).to.equal("synthesis_1")
    end)

    it("populates subproblems[i] with subproblem + solution", function()
        reset()
        mock_alc()
        local m = require("least_to_most")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.subproblems[1].subproblem).to.equal("easiest subproblem here")
        expect(ctx.result.subproblems[1].solution).to.equal("solution_1")
        expect(ctx.result.subproblems[3].subproblem).to.equal("hardest subproblem here")
        expect(ctx.result.subproblems[3].solution).to.equal("solution_3")
    end)

    it("max_subproblems is embedded into the decomposition prompt", function()
        reset()
        local log = mock_alc()
        local m = require("least_to_most")
        m.run({ task = "T", max_subproblems = 7 })
        expect(log[1].prompt:find("up to 7 subproblems", 1, true)).to_not.equal(nil)
    end)

    it("fallback to single-pass when decomposition has no parseable lines", function()
        reset()
        local log, log_calls = mock_alc({ decomp_text = "rambling prose, no numbered list" })
        local m = require("least_to_most")
        local ctx = m.run({ task = "the original task" })
        expect(ctx.result.total_subproblems).to.equal(1)
        expect(ctx.result.subproblems[1].subproblem).to.equal("the original task")
        -- 1 decomp + 1 solve + 1 synth = 3
        expect(#log).to.equal(3)
        local warn_seen = false
        for _, lc in ipairs(log_calls) do
            if lc.level == "warn" then warn_seen = true end
        end
        expect(warn_seen).to.equal(true)
    end)

    it("subproblem #2 prompt embeds the previous solution as context", function()
        reset()
        local log = mock_alc()
        local m = require("least_to_most")
        m.run({ task = "T" })
        -- log[1]=decomp, log[2]=solve1, log[3]=solve2, log[4]=solve3, log[5]=synth
        local p2 = log[3].prompt
        expect(p2:find("Previously solved", 1, true)).to_not.equal(nil)
        expect(p2:find("solution_1", 1, true)).to_not.equal(nil)
        -- First solve prompt should NOT have "Previously solved"
        expect(log[2].prompt:find("Previously solved", 1, true)).to.equal(nil)
    end)

    it("synthesis prompt embeds every subproblem + solution pair", function()
        reset()
        local log = mock_alc()
        local m = require("least_to_most")
        m.run({ task = "T" })
        local synth_prompt = log[#log].prompt
        for _, marker in ipairs({ "easiest subproblem", "hardest subproblem", "solution_1", "solution_3" }) do
            expect(synth_prompt:find(marker, 1, true)).to_not.equal(nil)
        end
    end)
end)

reset()
