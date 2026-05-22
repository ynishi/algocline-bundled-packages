--- Tests for meta_prompt package (Meta-Prompting, Suzgun & Kalai 2024
--- arXiv:2401.12954). M.run() is LLM-dependent and also calls
--- alc.log(); both are stubbed via a counter that switches behavior by
--- prompt substring.
---
--- Run via:
---   just alc-pkg-test-file meta_prompt/spec/meta_prompt_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc with alc.llm and alc.log. orchestrator_text
--- controls Phase 1 output (the analysis text). Subsequent calls return
--- "expert_<n>" then "synthesis_<n>". All calls are recorded in
--- call_log.
local function mock_alc(orchestrator_text)
    local call_log = {}
    local log_calls = {}
    local counter = { expert = 0, synthesis = 0 }
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            if prompt:find("META%-ORCHESTRATOR, analyze") then
                return orchestrator_text
            elseif prompt:find("integrate all expert analyses", 1, true) then
                counter.synthesis = counter.synthesis + 1
                return "synthesis_" .. counter.synthesis
            else
                counter.expert = counter.expert + 1
                return "expert_" .. counter.expert
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
    package.loaded["meta_prompt"] = nil
end

local THREE_EXPERTS =
    "EXPERT: Physicist | FOCUS: quantum mechanics | QUESTION: explain entanglement\n"
 .. "EXPERT: Philosopher | FOCUS: epistemology | QUESTION: what does it mean to know\n"
 .. "EXPERT: Engineer | FOCUS: applications | QUESTION: how is it used"

-- ================================================================
-- meta
-- ================================================================

describe("meta_prompt.meta", function()
    reset()
    mock_alc(THREE_EXPERTS)
    local mp = require("meta_prompt")

    it("has correct name", function()
        expect(mp.meta.name).to.equal("meta_prompt")
    end)

    it("has version 0.1.0", function()
        expect(mp.meta.version).to.equal("0.1.0")
    end)

    it("has category 'reasoning'", function()
        expect(mp.meta.category).to.equal("reasoning")
    end)

    it("has a non-empty description", function()
        expect(type(mp.meta.description)).to.equal("string")
        expect(#mp.meta.description > 0).to.equal(true)
    end)
end)

-- ================================================================
-- spec
-- ================================================================

describe("meta_prompt.spec", function()
    reset()
    mock_alc(THREE_EXPERTS)
    local mp = require("meta_prompt")
    local run_entry = mp.spec.entries.run

    it("declares a run entry with input and result shapes", function()
        expect(run_entry).to_not.equal(nil)
        expect(run_entry.input).to_not.equal(nil)
        expect(run_entry.result).to_not.equal(nil)
    end)
end)

-- ================================================================
-- M.run with stubbed alc.llm + alc.log
-- ================================================================

describe("meta_prompt.run with stubbed alc.llm", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        local ok, err = pcall(mp.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("parses 3 experts and makes 1+3+1 = 5 LLM calls", function()
        reset()
        local log = mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        local ctx = mp.run({ task = "What is entanglement?" })
        expect(ctx.result.total_experts).to.equal(3)
        expect(#ctx.result.experts_consulted).to.equal(3)
        expect(#log).to.equal(5)
    end)

    it("populates each consultation with role / focus / question / response", function()
        reset()
        mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        local ctx = mp.run({ task = "T" })
        local first = ctx.result.experts_consulted[1]
        expect(first.role).to.equal("Physicist")
        expect(first.focus).to.equal("quantum mechanics")
        expect(first.question).to.equal("explain entanglement")
        expect(first.response).to.equal("expert_1")
        expect(ctx.result.experts_consulted[3].role).to.equal("Engineer")
        expect(ctx.result.experts_consulted[3].response).to.equal("expert_3")
    end)

    it("falls back to a single general expert when parsing fails", function()
        reset()
        local log, log_calls = mock_alc("nothing parseable here\njust prose")
        local mp = require("meta_prompt")
        local ctx = mp.run({ task = "T" })
        expect(ctx.result.total_experts).to.equal(1)
        local only = ctx.result.experts_consulted[1]
        expect(only.role).to.equal("Domain Expert")
        expect(only.focus).to.equal("Complete analysis")
        expect(only.question).to.equal("T")
        -- 1 orchestrator + 1 fallback expert + 1 synthesis = 3
        expect(#log).to.equal(3)
        -- Fallback path emits a warn log
        local warn_seen = false
        for _, lc in ipairs(log_calls) do
            if lc.level == "warn" then warn_seen = true end
        end
        expect(warn_seen).to.equal(true)
    end)

    it("default max_experts 4 is embedded in the orchestrator prompt", function()
        reset()
        local log = mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        mp.run({ task = "T" })
        local orch_prompt = log[1].prompt
        expect(orch_prompt:find("up to 4 experts", 1, true)).to_not.equal(nil)
    end)

    it("honors max_experts override = 2 in the orchestrator prompt", function()
        reset()
        local log = mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        mp.run({ task = "T", max_experts = 2 })
        local orch_prompt = log[1].prompt
        expect(orch_prompt:find("up to 2 experts", 1, true)).to_not.equal(nil)
    end)

    it("returns the synthesis stub value as ctx.result.answer", function()
        reset()
        mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        local ctx = mp.run({ task = "T" })
        expect(ctx.result.answer).to.equal("synthesis_1")
    end)

    it("synthesis prompt embeds every expert role + response", function()
        reset()
        local log = mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        mp.run({ task = "T" })
        local synth_prompt = log[#log].prompt
        expect(synth_prompt:find("Physicist", 1, true)).to_not.equal(nil)
        expect(synth_prompt:find("expert_1", 1, true)).to_not.equal(nil)
        expect(synth_prompt:find("Engineer", 1, true)).to_not.equal(nil)
        expect(synth_prompt:find("expert_3", 1, true)).to_not.equal(nil)
    end)

    it("second expert receives accumulated context from the first", function()
        reset()
        local log = mock_alc(THREE_EXPERTS)
        local mp = require("meta_prompt")
        mp.run({ task = "T" })
        -- log[1]=orch, log[2]=expert1, log[3]=expert2, log[4]=expert3, log[5]=synth
        local expert2_prompt = log[3].prompt
        expect(expert2_prompt:find("Previous expert consultations", 1, true)).to_not.equal(nil)
        expect(expert2_prompt:find("expert_1", 1, true)).to_not.equal(nil)
        -- Expert 1 prompt should NOT have prior consultations section
        local expert1_prompt = log[2].prompt
        expect(expert1_prompt:find("Previous expert consultations", 1, true)).to.equal(nil)
    end)
end)

reset()
