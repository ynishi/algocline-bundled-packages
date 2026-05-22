--- Tests for robust_qa package (3-phase pipeline: p_tts / negation /
--- critic).
---
--- Run via:
---   just alc-pkg-test-file robust_qa/spec/robust_qa_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local function mock_env()
    local log_calls = {}
    _G.alc = {
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    local p_tts_calls = {}
    local negation_calls = {}
    local critic_calls = {}
    package.loaded["p_tts"] = {
        run = function(ctx)
            p_tts_calls[#p_tts_calls + 1] = ctx
            return {
                result = {
                    answer = "p_tts_answer",
                    total_constraints = 3,
                    pass_count = 3,
                    fail_count = 0,
                    repairs = 0,
                    all_passed = true,
                    plan = "plan_text",
                    constraints = {},
                },
            }
        end,
    }
    package.loaded["negation"] = {
        run = function(ctx)
            negation_calls[#negation_calls + 1] = ctx
            return {
                result = {
                    answer = "negation_answer",
                    total = 4,
                    holding = 0,
                    refuted = 4,
                    survived = true,
                    revised = false,
                },
            }
        end,
    }
    package.loaded["critic"] = {
        run = function(ctx)
            critic_calls[#critic_calls + 1] = ctx
            return {
                result = {
                    answer = "critic_answer",
                    scores = { clarity = 8, accuracy = 9 },
                    avg_score = 8.5,
                    revisions = 0,
                },
            }
        end,
    }
    return p_tts_calls, negation_calls, critic_calls, log_calls
end

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "robust_qa", "p_tts", "negation", "critic" }) do
        package.loaded[name] = nil
    end
end

describe("robust_qa.meta", function()
    reset()
    mock_env()
    local m = require("robust_qa")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("robust_qa")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("pipeline")
    end)
end)

describe("robust_qa.spec", function()
    reset()
    mock_env()
    local m = require("robust_qa")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("robust_qa.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_env()
        local m = require("robust_qa")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("runs all 3 phases and merges convenience fields", function()
        reset()
        local p_tts_calls, negation_calls, critic_calls = mock_env()
        local m = require("robust_qa")
        local ctx = m.run({ task = "T" })
        expect(#p_tts_calls).to.equal(1)
        expect(#negation_calls).to.equal(1)
        expect(#critic_calls).to.equal(1)
        expect(#ctx.result.phases).to.equal(3)
        expect(ctx.result.phases[1].name).to.equal("p_tts")
        expect(ctx.result.phases[2].name).to.equal("negation")
        expect(ctx.result.phases[3].name).to.equal("critic")
        expect(ctx.result.answer).to.equal("critic_answer")
        expect(ctx.result.constraints_passed).to.equal(true)
        expect(ctx.result.adversarial_survived).to.equal(true)
        expect(ctx.result.critic_avg_score).to.equal(8.5)
    end)

    it("phase 2 receives the phase 1 answer as input", function()
        reset()
        local _, negation_calls = mock_env()
        local m = require("robust_qa")
        m.run({ task = "T" })
        expect(negation_calls[1].answer).to.equal("p_tts_answer")
    end)

    it("phase 3 receives the phase 2 answer as input", function()
        reset()
        local _, _, critic_calls = mock_env()
        local m = require("robust_qa")
        m.run({ task = "T" })
        expect(critic_calls[1].answer).to.equal("negation_answer")
    end)

    it("traceability fields capture per-phase answers", function()
        reset()
        mock_env()
        local m = require("robust_qa")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.phase1_answer).to.equal("p_tts_answer")
        expect(ctx.result.phase2_answer).to.equal("negation_answer")
        expect(ctx.result.phase3_answer).to.equal("critic_answer")
    end)

    it("forwards configuration knobs to each sub-package", function()
        reset()
        local p_tts_calls, negation_calls, critic_calls = mock_env()
        local m = require("robust_qa")
        m.run({
            task = "T",
            max_constraints = 7,
            max_conditions = 6,
            threshold = 9,
            max_revisions = 2,
        })
        expect(p_tts_calls[1].max_constraints).to.equal(7)
        expect(negation_calls[1].max_conditions).to.equal(6)
        expect(critic_calls[1].threshold).to.equal(9)
        expect(critic_calls[1].max_revisions).to.equal(2)
    end)
end)

reset()
