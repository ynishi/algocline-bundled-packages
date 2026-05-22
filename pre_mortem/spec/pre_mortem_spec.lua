--- Tests for pre_mortem package (feasibility-gated proposal filter,
--- combinator over factscore / contrastive / calibrate + rank).
---
--- Run via:
---   just alc-pkg-test-file pre_mortem/spec/pre_mortem_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build stub sub-packages. opts can override per-call results.
---   opts.fs_result_fn(idx)  — factscore result selector per proposal idx
---   opts.cal_result_fn(idx) — calibrate result selector per proposal idx
local function mock_env(opts)
    opts = opts or {}
    local fs_result_fn = opts.fs_result_fn or function()
        return {
            total = 3, supported = 3, unsupported = 0, uncertain = 0,
            claims = {
                { status = "supported", claim = "c1" },
                { status = "supported", claim = "c2" },
                { status = "supported", claim = "c3" },
            },
        }
    end
    local cal_result_fn = opts.cal_result_fn or function()
        return {
            confidence = 0.9,
            answer = "VERDICT: ADOPT — looks feasible",
        }
    end
    local llm_log = {}
    local log_calls = {}
    local fs_idx, cal_idx = 0, 0
    _G.alc = {
        llm = function(prompt, options)
            llm_log[#llm_log + 1] = { prompt = prompt, opts = options }
            -- Default: pairwise tournament returns A as winner
            return "A wins because it is better"
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    package.loaded["factscore"] = {
        run = function(ctx)
            fs_idx = fs_idx + 1
            return { result = fs_result_fn(fs_idx) }
        end,
    }
    package.loaded["contrastive"] = {
        run = function(ctx)
            return {
                result = {
                    answer = "contrastive_answer",
                    contrasts = {
                        { wrong_reasoning = "wrong_r", error_analysis = "rejection_reason_1" },
                    },
                    total_contrasts = 1,
                },
            }
        end,
    }
    package.loaded["calibrate"] = {
        run = function(ctx)
            cal_idx = cal_idx + 1
            return { result = cal_result_fn(cal_idx) }
        end,
    }
    return llm_log, log_calls
end

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "pre_mortem", "factscore", "contrastive", "calibrate" }) do
        package.loaded[name] = nil
    end
end

describe("pre_mortem.meta", function()
    reset()
    mock_env()
    local m = require("pre_mortem")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("pre_mortem")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("combinator")
    end)
end)

describe("pre_mortem.spec", function()
    reset()
    mock_env()
    local m = require("pre_mortem")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("pre_mortem.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_env()
        local m = require("pre_mortem")
        local ok, err = pcall(m.run, { proposals = { "P1" } })
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("errors when ctx.proposals is missing", function()
        reset()
        mock_env()
        local m = require("pre_mortem")
        local ok, err = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.proposals")).to_not.equal(nil)
    end)

    it("all-supported / high-confidence ADOPT path accepts all proposals", function()
        reset()
        mock_env()
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1", "P2", "P3" } })
        expect(ctx.result.total).to.equal(3)
        expect(ctx.result.accepted).to.equal(3)
        expect(ctx.result.rejected).to.equal(0)
        expect(ctx.result.needs_investigation).to.equal(0)
    end)

    it("unsupported prerequisites force rejection regardless of verdict", function()
        reset()
        mock_env({
            fs_result_fn = function()
                return {
                    total = 2, supported = 1, unsupported = 1, uncertain = 0,
                    claims = {
                        { status = "supported", claim = "ok" },
                        { status = "unsupported", claim = "missing" },
                    },
                }
            end,
        })
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1" } })
        expect(ctx.result.rejected).to.equal(1)
        expect(ctx.result.accepted).to.equal(0)
        expect(ctx.result.proposals[1].status).to.equal("rejected")
    end)

    it("low calibrate confidence routes to needs_investigation", function()
        reset()
        mock_env({
            cal_result_fn = function()
                return { confidence = 0.3, answer = "VERDICT: ADOPT" }
            end,
        })
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1" } })
        expect(ctx.result.needs_investigation).to.equal(1)
        expect(ctx.result.accepted).to.equal(0)
        expect(ctx.result.proposals[1].status).to.equal("needs_investigation")
    end)

    it("high-confidence REJECT verdict yields rejected status", function()
        reset()
        mock_env({
            cal_result_fn = function()
                return { confidence = 0.9, answer = "VERDICT: REJECT — infeasible" }
            end,
        })
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1" } })
        expect(ctx.result.rejected).to.equal(1)
        expect(ctx.result.proposals[1].verdict).to.equal("reject")
    end)

    it("ranks 2+ accepted proposals via pairwise tournament", function()
        reset()
        mock_env()
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1", "P2" } })
        expect(ctx.result.accepted).to.equal(2)
        expect(#ctx.result.ranking).to.equal(2)
        expect(ctx.result.ranking[1].rank).to.equal(1)
        expect(ctx.result.ranking[2].rank).to.equal(2)
    end)

    it("single accepted proposal gets rank=1 without tournament", function()
        reset()
        mock_env()
        local m = require("pre_mortem")
        local ctx = m.run({ task = "T", proposals = { "P1" } })
        expect(#ctx.result.ranking).to.equal(1)
        expect(ctx.result.ranking[1].rank).to.equal(1)
    end)
end)

reset()
