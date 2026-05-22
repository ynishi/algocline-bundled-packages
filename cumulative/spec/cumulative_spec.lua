--- Tests for cumulative package (Cumulative Reasoning, Zhang et al.
--- 2024 arXiv:2308.04371). proposer / verifier / reporter loop.
---
--- Run via:
---   just alc-pkg-test-file cumulative/spec/cumulative_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.verifier_verdict — string to return from the verifier
---     ("ACCEPTED" or "REJECTED ..."). Default: ACCEPTED.
---   opts.early_yes — if true, the "can_conclude" check returns YES
---     once it is triggered (>= round 2 with >= 3 established facts).
local function mock_alc(opts)
    opts = opts or {}
    local verifier_verdict = opts.verifier_verdict or "ACCEPTED — sound"
    local early_yes = opts.early_yes
    local call_log = {}
    local log_calls = {}
    local c = { proposer = 0, verifier = 0, conclude = 0, reporter = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("As the PROPOSER", 1, true) then
                c.proposer = c.proposer + 1
                return "proposition_" .. c.proposer
            elseif prompt:find("As the VERIFIER", 1, true) then
                c.verifier = c.verifier + 1
                return verifier_verdict
            elseif prompt:find("Can we now provide a complete answer", 1, true) then
                c.conclude = c.conclude + 1
                return early_yes and "YES" or "NO"
            else
                c.reporter = c.reporter + 1
                return "report_" .. c.reporter
            end
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
        reduce = function(arr, fn, init)
            local acc = init
            for _, v in ipairs(arr) do acc = fn(acc, v) end
            return acc
        end,
    }
    return call_log, log_calls
end

local function reset()
    _G.alc = nil
    package.loaded["cumulative"] = nil
end

describe("cumulative.meta", function()
    reset()
    mock_alc()
    local m = require("cumulative")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("cumulative")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("cumulative.spec", function()
    reset()
    mock_alc()
    local m = require("cumulative")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("cumulative.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("cumulative")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("max_rounds=2, props=2, all ACCEPTED, early YES at round 2 → reports", function()
        reset()
        local log = mock_alc({ early_yes = true })
        local m = require("cumulative")
        local ctx = m.run({ task = "T", max_rounds = 4, propositions_per_round = 2 })
        -- Round 1: 2 propose + 2 verify = 4
        -- Round 2: 2 propose + 2 verify + 1 conclude(YES) → break = 5
        -- Reporter = 1
        expect(#log).to.equal(4 + 5 + 1)
        expect(ctx.result.total_rounds).to.equal(2)
        expect(ctx.result.total_established).to.equal(4)
        expect(ctx.result.answer).to.equal("report_1")
    end)

    it("REJECTED verdicts produce zero established facts (no early-termination trigger)", function()
        reset()
        local log = mock_alc({ verifier_verdict = "REJECTED — unsound", early_yes = true })
        local m = require("cumulative")
        local ctx = m.run({ task = "T", max_rounds = 2, propositions_per_round = 2 })
        expect(ctx.result.total_established).to.equal(0)
        -- 2 rounds × (2 propose + 2 verify) + reporter = 9
        -- No early-termination call because established < 3
        expect(#log).to.equal(9)
        expect(ctx.result.total_rounds).to.equal(2)
    end)

    it("runs all max_rounds when can_conclude returns NO", function()
        reset()
        local log = mock_alc({ early_yes = false })
        local m = require("cumulative")
        local ctx = m.run({ task = "T", max_rounds = 3, propositions_per_round = 2 })
        -- Round 1: 2p + 2v (established 2, no conclude yet)
        -- Round 2: 2p + 2v (established 4) + 1 conclude(NO)
        -- Round 3: 2p + 2v + 1 conclude(NO)
        -- Reporter
        expect(#log).to.equal(4 + 5 + 5 + 1)
        expect(ctx.result.total_rounds).to.equal(3)
        expect(ctx.result.total_established).to.equal(6)
    end)

    it("each round_data has proposed[] and verified[] with accepted flag", function()
        reset()
        mock_alc()
        local m = require("cumulative")
        local ctx = m.run({ task = "T", max_rounds = 1, propositions_per_round = 2 })
        local round = ctx.result.rounds[1]
        expect(#round.proposed).to.equal(2)
        expect(#round.verified).to.equal(2)
        expect(round.verified[1].accepted).to.equal(true)
        expect(round.verified[1].proposition).to.equal("proposition_1")
    end)

    it("established_facts record proposition + round of acceptance", function()
        reset()
        mock_alc()
        local m = require("cumulative")
        local ctx = m.run({ task = "T", max_rounds = 1, propositions_per_round = 1 })
        expect(ctx.result.established_facts[1].proposition).to.equal("proposition_1")
        expect(ctx.result.established_facts[1].round).to.equal(1)
    end)
end)

reset()
