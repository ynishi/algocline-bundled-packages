--- Tests for analogical package (Analogical Prompting, Yasunaga et al.
--- 2023 arXiv:2310.01714).
---
--- Run via:
---   just alc-pkg-test-file analogical/spec/analogical_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.llm that returns distinguishable strings per
--- phase via prompt substring classification.
local function mock_alc()
    local call_log = {}
    local c = { problem = 0, solution = 0, patterns = 0, final = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("structurally similar problem", 1, true) then
                c.problem = c.problem + 1
                return "problem_" .. c.problem
            elseif prompt:find("Solve this step by step", 1, true) then
                c.solution = c.solution + 1
                return "solution_" .. c.solution
            elseif prompt:find("transferable insights", 1, true) then
                c.patterns = c.patterns + 1
                return "patterns_" .. c.patterns
            else
                c.final = c.final + 1
                return "final_" .. c.final
            end
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["analogical"] = nil
end

describe("analogical.meta", function()
    reset()
    mock_alc()
    local a = require("analogical")

    it("name / version / category", function()
        expect(a.meta.name).to.equal("analogical")
        expect(a.meta.version).to.equal("0.1.0")
        expect(a.meta.category).to.equal("reasoning")
    end)
end)

describe("analogical.spec", function()
    reset()
    mock_alc()
    local a = require("analogical")
    it("exposes run input + result shapes", function()
        expect(a.spec.entries.run.input).to_not.equal(nil)
        expect(a.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("analogical.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local a = require("analogical")
        local ok, err = pcall(a.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default n_analogies=3 → 2*3 + 1 + 1 = 8 LLM calls", function()
        reset()
        local log = mock_alc()
        local a = require("analogical")
        local ctx = a.run({ task = "T" })
        expect(#log).to.equal(8)
        expect(ctx.result.total_analogies).to.equal(3)
        expect(#ctx.result.analogies).to.equal(3)
    end)

    it("n_analogies=2 override → 2*2 + 1 + 1 = 6 calls", function()
        reset()
        local log = mock_alc()
        local a = require("analogical")
        local ctx = a.run({ task = "T", n_analogies = 2 })
        expect(#log).to.equal(6)
        expect(ctx.result.total_analogies).to.equal(2)
    end)

    it("populates each analogy with problem + solution", function()
        reset()
        mock_alc()
        local a = require("analogical")
        local ctx = a.run({ task = "T", n_analogies = 2 })
        expect(ctx.result.analogies[1].problem).to.equal("problem_1")
        expect(ctx.result.analogies[1].solution).to.equal("solution_1")
        expect(ctx.result.analogies[2].problem).to.equal("problem_2")
        expect(ctx.result.analogies[2].solution).to.equal("solution_2")
    end)

    it("returns final stub as ctx.result.answer and patterns separately", function()
        reset()
        mock_alc()
        local a = require("analogical")
        local ctx = a.run({ task = "T", n_analogies = 2 })
        expect(ctx.result.answer).to.equal("final_1")
        expect(ctx.result.patterns).to.equal("patterns_1")
    end)

    it("domain_hint is embedded in every analogy-generation prompt", function()
        reset()
        local log = mock_alc()
        local a = require("analogical")
        a.run({ task = "T", n_analogies = 2, domain_hint = "biology" })
        -- log[1] = analogy 1 gen, log[3] = analogy 2 gen
        expect(log[1].prompt:find("domain of biology", 1, true)).to_not.equal(nil)
        expect(log[3].prompt:find("domain of biology", 1, true)).to_not.equal(nil)
    end)

    it("subsequent analogy prompts list previously proposed analogies", function()
        reset()
        local log = mock_alc()
        local a = require("analogical")
        a.run({ task = "T", n_analogies = 2 })
        -- log[3] is the 2nd analogy generation
        local p2 = log[3].prompt
        expect(p2:find("Analogies already proposed", 1, true)).to_not.equal(nil)
        expect(p2:find("problem_1", 1, true)).to_not.equal(nil)
        -- First analogy prompt should NOT have the prior-list section
        expect(log[1].prompt:find("Analogies already proposed", 1, true)).to.equal(nil)
    end)

    it("patterns prompt and final prompt both embed every analogy", function()
        reset()
        local log = mock_alc()
        local a = require("analogical")
        a.run({ task = "T", n_analogies = 2 })
        -- log[5] = patterns extraction, log[6] = final solve
        local patterns_prompt = log[5].prompt
        local final_prompt = log[6].prompt
        for _, marker in ipairs({ "problem_1", "solution_1", "problem_2", "solution_2" }) do
            expect(patterns_prompt:find(marker, 1, true)).to_not.equal(nil)
            expect(final_prompt:find(marker, 1, true)).to_not.equal(nil)
        end
        expect(final_prompt:find("patterns_1", 1, true)).to_not.equal(nil)
    end)
end)

reset()
