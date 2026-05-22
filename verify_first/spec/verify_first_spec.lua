--- Tests for verify_first package ("Asking LLMs to Verify First is
--- Almost Free Lunch" 2025 arXiv:2511.21734).
---
--- Run via:
---   just alc-pkg-test-file verify_first/spec/verify_first_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.verification_text — what the verify stub returns. Default
---     contains "The answer is FORTY-TWO." so extract_answer picks it up.
local function mock_alc(opts)
    opts = opts or {}
    local verification_text = opts.verification_text
        or "verification reasoning steps; The answer is FORTY-TWO.\n"
    local call_log = {}
    local log_calls = {}
    local c = { cot = 0, verify = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("A possible answer is", 1, true) then
                c.verify = c.verify + 1
                return verification_text
            else
                c.cot = c.cot + 1
                return "cot_candidate"
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
    package.loaded["verify_first"] = nil
end

describe("verify_first.meta", function()
    reset()
    mock_alc()
    local m = require("verify_first")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("verify_first")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("verify_first.spec", function()
    reset()
    mock_alc()
    local m = require("verify_first")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("verify_first.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("verify_first")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default (cot + 1 verify) → 2 LLM calls, candidate_source='cot'", function()
        reset()
        local log = mock_alc()
        local m = require("verify_first")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(2)
        expect(ctx.result.candidate_source).to.equal("cot")
        expect(ctx.result.iterations).to.equal(1)
        expect(ctx.result.extracted_answer).to.equal("FORTY-TWO")
    end)

    it("trivial=true → 1 LLM call, candidate '1', candidate_source='trivial'", function()
        reset()
        local log = mock_alc()
        local m = require("verify_first")
        local ctx = m.run({ task = "T", trivial = true })
        expect(#log).to.equal(1)
        expect(ctx.result.candidate_source).to.equal("trivial")
        -- verify prompt embeds the trivial "1" candidate inside """ ... """
        expect(log[1].prompt:find("\"\"\"\n1\n\"\"\"", 1, true)).to_not.equal(nil)
    end)

    it("provided candidate → 1 LLM call, candidate_source='provided'", function()
        reset()
        local log = mock_alc()
        local m = require("verify_first")
        local ctx = m.run({ task = "T", candidate = "preset answer" })
        expect(#log).to.equal(1)
        expect(ctx.result.candidate_source).to.equal("provided")
        expect(log[1].prompt:find("preset answer", 1, true)).to_not.equal(nil)
    end)

    it("iterations=3 (cot mode) → 1 cot + 3 verify = 4 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("verify_first")
        local ctx = m.run({ task = "T", iterations = 3 })
        expect(#log).to.equal(4)
        expect(ctx.result.iterations).to.equal(3)
        expect(#ctx.result.history).to.equal(3)
    end)

    it("Iter-VF is Markovian: round N candidate = round N-1 extracted answer", function()
        reset()
        local log = mock_alc()
        local m = require("verify_first")
        m.run({ task = "T", trivial = true, iterations = 2 })
        -- log[1] = round 1 verify (candidate "1")
        -- log[2] = round 2 verify (candidate = extracted "FORTY-TWO")
        expect(log[2].prompt:find("FORTY%-TWO")).to_not.equal(nil)
    end)

    it("extract_answer falls back to full text when no marker pattern found", function()
        reset()
        mock_alc({ verification_text = "plain reasoning with no canonical marker phrase here" })
        local m = require("verify_first")
        local ctx = m.run({ task = "T", trivial = true })
        expect(ctx.result.extracted_answer:find("plain reasoning", 1, true)).to_not.equal(nil)
    end)
end)

reset()
