--- Tests for intent_belief package ("Probabilistic Modeling of
--- Intentions in Socially Intelligent LLM Agents" 2025
--- arXiv:2510.18476). Bayesian belief update with diagnostic
--- questions; uses alc.llm + alc.specify + alc.log.
---
--- Run via:
---   just alc-pkg-test-file intent_belief/spec/intent_belief_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local PRIOR_TEXT =
    "H1: first interpretation here\n"
 .. "H2: second interpretation here\n"
 .. "H3: third interpretation here\n"
 .. "PRIOR: H1: 0.34, H2: 0.33, H3: 0.33\n"

--- Build a mock _G.alc.
---   opts.prior_text — output of Phase 1 prior generator.
---   opts.update_likelihood — likelihood line to embed in update output
---     (controls Bayesian update direction). Default: H1 dominates.
local function mock_alc(opts)
    opts = opts or {}
    local prior_text = opts.prior_text or PRIOR_TEXT
    local update_likelihood = opts.update_likelihood
        or "H1: 0.9 — supports H1\nH2: 0.05 — contradicts H2\nH3: 0.05 — contradicts H3"
    local call_log = {}
    local log_calls = {}
    local specify_calls = {}
    local c = { prior = 0, diag = 0, update = 0, specify = 0, final = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Generate exactly %d+ distinct interpretations") then
                c.prior = c.prior + 1
                return prior_text
            elseif prompt:find("Design ONE diagnostic question", 1, true) then
                c.diag = c.diag + 1
                return string.format(
                    "QUESTION: diagnostic_q_%d\nPREDICTIONS:\nH1 predicts: a\nH2 predicts: b",
                    c.diag
                )
            elseif prompt:find("re%-estimate the likelihood of each", 1, true) then
                c.update = c.update + 1
                return update_likelihood
            else
                c.final = c.final + 1
                return "specified_task_text"
            end
        end,
        specify = function(prompt, options)
            c.specify = c.specify + 1
            specify_calls[#specify_calls + 1] = { prompt = prompt, opts = options }
            return "user_ans_" .. c.specify
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls, specify_calls
end

local function reset()
    _G.alc = nil
    package.loaded["intent_belief"] = nil
end

describe("intent_belief.meta", function()
    reset()
    mock_alc()
    local m = require("intent_belief")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("intent_belief")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("intent")
    end)
end)

describe("intent_belief.spec", function()
    reset()
    mock_alc()
    local m = require("intent_belief")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("intent_belief.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("intent_belief")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("runs to max_rounds with default flat-ish prior, emits MAP + ranked", function()
        reset()
        local log, _, specify_log = mock_alc()
        local m = require("intent_belief")
        local ctx = m.run({ task = "T" })
        -- 1 prior + max_rounds × (1 diag + 1 update) + 1 final = 1 + 6 + 1 = 8
        expect(#log).to.equal(8)
        expect(#specify_log).to.equal(3)
        expect(ctx.result.rounds).to.equal(3)
        expect(type(ctx.result.map_confidence)).to.equal("number")
        expect(ctx.result.specified_task).to.equal("specified_task_text")
    end)

    it("ranked_hypotheses is sorted by posterior desc and MAP matches rank 1", function()
        reset()
        mock_alc()
        local m = require("intent_belief")
        local ctx = m.run({ task = "T" })
        local r = ctx.result.ranked_hypotheses
        expect(#r).to.equal(3)
        expect(r[1].belief >= r[2].belief).to.equal(true)
        expect(r[2].belief >= r[3].belief).to.equal(true)
        expect(ctx.result.map_confidence).to.equal(r[1].belief)
    end)

    it("flat likelihoods → no convergence, runs all max_rounds", function()
        reset()
        local log, _, specify_log = mock_alc({
            update_likelihood = "H1: 0.33\nH2: 0.34\nH3: 0.33",
        })
        local m = require("intent_belief")
        local ctx = m.run({ task = "T", max_rounds = 2, confidence_threshold = 0.9 })
        -- 1 prior + 2 × (diag + update) + 1 final = 6
        expect(#log).to.equal(6)
        expect(#specify_log).to.equal(2)
        expect(ctx.result.rounds).to.equal(2)
        expect(ctx.result.converged).to.equal(false)
    end)

    it("update_log entries carry prior / likelihoods / posterior / entropy", function()
        reset()
        mock_alc()
        local m = require("intent_belief")
        local ctx = m.run({ task = "T" })
        local entry = ctx.result.update_log[1]
        expect(#entry.prior).to.equal(3)
        expect(#entry.likelihoods).to.equal(3)
        expect(#entry.posterior).to.equal(3)
        expect(type(entry.entropy)).to.equal("number")
        expect(entry.question:find("diagnostic_q_")).to_not.equal(nil)
        expect(entry.answer).to.equal("user_ans_1")
    end)

    it("prior parse failure → error-shape result with raw payload", function()
        reset()
        mock_alc({ prior_text = "no hypotheses parseable at all" })
        local m = require("intent_belief")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.error).to_not.equal(nil)
        expect(ctx.result.raw:find("no hypotheses", 1, true)).to_not.equal(nil)
        expect(ctx.result.map_hypothesis).to.equal(nil)
    end)
end)

reset()
