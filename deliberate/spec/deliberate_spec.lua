--- Tests for deliberate package (combinator over step_back /
--- meta_prompt / triad / calibrate / rank).
---
--- Run via:
---   just alc-pkg-test-file deliberate/spec/deliberate_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Stub the five sub-packages via package.loaded and a minimal _G.alc
--- (alc.llm is consulted only by the pairwise tournament in Phase 6).
local function mock_env()
    local call_log = {}
    local log_calls = {}
    local c = { llm = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            c.llm = c.llm + 1
            return "WINNER: A — option A wins"
        end,
        json_decode = function(s) return nil end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    package.loaded["step_back"] = {
        run = function(ctx)
            return { result = { answer = "principles_text", abstractions = {} } }
        end,
    }
    package.loaded["meta_prompt"] = {
        run = function(ctx)
            return {
                result = {
                    answer = "expert_analysis_text",
                    experts_consulted = { { role = "E1" }, { role = "E2" } },
                },
            }
        end,
    }
    package.loaded["triad"] = {
        run = function(ctx)
            return { result = { verdict = "verdict_text", winner = "proponent" } }
        end,
    }
    package.loaded["calibrate"] = {
        run = function(ctx)
            return { result = { confidence = 0.85, escalated = false } }
        end,
    }
    package.loaded["rank"] = { run = function() error("rank.run shouldn't be called directly", 0) end }
    return call_log, log_calls
end

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "deliberate", "step_back", "meta_prompt", "triad", "calibrate", "rank" }) do
        package.loaded[name] = nil
    end
end

describe("deliberate.meta", function()
    reset()
    mock_env()
    local m = require("deliberate")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("deliberate")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("combinator")
    end)
end)

describe("deliberate.spec", function()
    reset()
    mock_env()
    local m = require("deliberate")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("deliberate.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_env()
        local m = require("deliberate")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("with provided options, runs all 6 phases and produces a recommendation", function()
        reset()
        mock_env()
        local m = require("deliberate")
        local ctx = m.run({
            task = "T",
            options = {
                { name = "A", description = "alpha", strengths = "s", risks = "r" },
                { name = "B", description = "beta",  strengths = "s", risks = "r" },
            },
        })
        expect(ctx.result.principles).to.equal("principles_text")
        expect(ctx.result.expert_analysis).to.equal("expert_analysis_text")
        expect(#ctx.result.expert_consultations).to.equal(2)
        expect(ctx.result.total_options).to.equal(2)
        expect(#ctx.result.debates).to.equal(2)
        expect(ctx.result.confidence).to.equal(0.85)
        expect(ctx.result.confidence_escalated).to.equal(false)
        -- One pairwise match in Phase 6 (2 options → 1 match)
        expect(#ctx.result.ranking_matches).to.equal(1)
        -- Stub returns "WINNER: A" → option 1 wins
        expect(ctx.result.recommendation.name).to.equal("A")
        expect(ctx.result.recommendation.ranking_wins).to.equal(1)
    end)

    it("debates carry option / verdict / winner per option", function()
        reset()
        mock_env()
        local m = require("deliberate")
        local ctx = m.run({
            task = "T",
            options = { { name = "X", description = "x" } },
        })
        expect(ctx.result.debates[1].option.name).to.equal("X")
        expect(ctx.result.debates[1].verdict).to.equal("verdict_text")
        expect(ctx.result.debates[1].winner).to.equal("proponent")
    end)
end)

reset()
