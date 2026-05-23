--- Tests for propose_verify package.
--- 2-call Propose->Verify Strategy.
--- References: Cobbe 2021 arXiv:2110.14168 §3, LATS arXiv:2309.08987 §3.2

local describe, it, expect = lust.describe, lust.it, lust.expect

local function reset()
    _G.alc = nil
    package.loaded["propose_verify"] = nil
end

local function mock_alc(propose_reply, verify_reply)
    propose_reply = propose_reply or "Candidate answer text."
    verify_reply  = verify_reply  or "ACCEPT: yes\nSCORE: 0.85\nRATIONALE: Looks good."
    local calls = {}
    _G.alc = {
        llm = function(prompt, opts)
            calls[#calls + 1] = { prompt = prompt, opts = opts }
            -- Identify call by presence of "ACCEPT" in prompt (verify prompt)
            if prompt:find("ACCEPT", 1, true) then
                return verify_reply
            else
                return propose_reply
            end
        end,
        log = function() end,
    }
    return calls
end

-- ─── M.meta ──────────────────────────────────────────────────────────────────

describe("propose_verify.meta", function()
    reset()
    mock_alc()
    local pv = require("propose_verify")
    it("exports M.meta with required fields", function()
        expect(pv.meta).to_not.equal(nil)
        expect(pv.meta.name).to.equal("propose_verify")
        expect(type(pv.meta.version)).to.equal("string")
        expect(type(pv.meta.description)).to.equal("string")
        expect(pv.meta.category).to.equal("validation")
    end)
end)

-- ─── build_propose_prompt (pure) ─────────────────────────────────────────────

describe("propose_verify.build_propose_prompt", function()
    reset()
    mock_alc()
    local pv = require("propose_verify")

    it("returns a non-empty string for a task", function()
        local prompt = pv.build_propose_prompt("What is 2+2?")
        expect(type(prompt)).to.equal("string")
        expect(#prompt > 0).to.equal(true)
        expect(prompt:find("What is 2+2", 1, true) ~= nil).to.equal(true)
    end)

    it("includes proposer_hint when supplied", function()
        local prompt = pv.build_propose_prompt("What is 2+2?", "answer in one word")
        expect(prompt:find("answer in one word", 1, true) ~= nil).to.equal(true)
    end)

    it("does not include hint section when proposer_hint is nil", function()
        local prompt = pv.build_propose_prompt("Task?")
        expect(prompt:find("Additional guidance", 1, true)).to.equal(nil)
    end)
end)

-- ─── build_verify_prompt (pure) ──────────────────────────────────────────────

describe("propose_verify.build_verify_prompt", function()
    reset()
    mock_alc()
    local pv = require("propose_verify")

    it("includes the candidate in the prompt", function()
        local prompt = pv.build_verify_prompt("What is 2+2?", "The answer is 4.", nil)
        expect(type(prompt)).to.equal("string")
        expect(prompt:find("The answer is 4.", 1, true) ~= nil).to.equal(true)
    end)

    it("includes the task in the prompt", function()
        local prompt = pv.build_verify_prompt("What is 2+2?", "The answer is 4.", nil)
        expect(prompt:find("What is 2+2?", 1, true) ~= nil).to.equal(true)
    end)

    it("prompt asks for ACCEPT / SCORE / RATIONALE format", function()
        local prompt = pv.build_verify_prompt("T", "C", nil)
        expect(prompt:find("ACCEPT", 1, true) ~= nil).to.equal(true)
        expect(prompt:find("SCORE", 1, true) ~= nil).to.equal(true)
        expect(prompt:find("RATIONALE", 1, true) ~= nil).to.equal(true)
    end)

    it("includes verifier_hint when supplied", function()
        local prompt = pv.build_verify_prompt("T", "C", "focus on factual accuracy")
        expect(prompt:find("focus on factual accuracy", 1, true) ~= nil).to.equal(true)
    end)
end)

-- ─── parse_verify (pure) ─────────────────────────────────────────────────────

describe("propose_verify.parse_verify", function()
    reset()
    mock_alc()
    local pv = require("propose_verify")

    it("extracts accept/score/rationale from a well-formed verifier output", function()
        local sample = "ACCEPT: yes\nSCORE: 0.92\nRATIONALE: The answer is mathematically correct."
        local result = pv.parse_verify(sample)
        expect(result.accept).to.equal(true)
        expect(result.score).to.equal(0.92)
        expect(type(result.rationale)).to.equal("string")
        expect(#result.rationale > 0).to.equal(true)
    end)

    it("handles malformed verifier output gracefully (returns accept=false, score=0)", function()
        local bad = "I cannot parse this text at all."
        local result = pv.parse_verify(bad)
        expect(result.accept).to.equal(false)
        expect(result.score).to.equal(0.0)
        expect(type(result.rationale)).to.equal("string")
    end)

    it("parses ACCEPT: no correctly", function()
        local sample = "ACCEPT: no\nSCORE: 0.2\nRATIONALE: The candidate answer is wrong."
        local result = pv.parse_verify(sample)
        expect(result.accept).to.equal(false)
        expect(result.score).to.equal(0.2)
    end)
end)

-- ─── run ─────────────────────────────────────────────────────────────────────

describe("propose_verify.run", function()

    it("uses ctx.task fallback chain (task -> text -> idea -> question)", function()
        reset()
        local calls = mock_alc()
        local pv = require("propose_verify")
        -- Supply via ctx.text (not ctx.task)
        local ctx = { text = "What is gravity?", score_threshold = 0.5 }
        local r = pv.run(ctx)
        expect(r.result).to_not.equal(nil)
        expect(r.result.total_llm_calls).to.equal(2)
        expect(#calls).to.equal(2)
        -- Propose prompt must reference the task from ctx.text
        expect(calls[1].prompt:find("What is gravity?", 1, true) ~= nil).to.equal(true)
    end)

    it("sets total_llm_calls = 2", function()
        reset()
        mock_alc()
        local pv = require("propose_verify")
        local r = pv.run({ task = "T", score_threshold = 0.5 })
        expect(r.result.total_llm_calls).to.equal(2)
    end)

    it("sets verdict DONE path=accepted when score >= threshold and accept=yes", function()
        reset()
        mock_alc("My proposed answer.", "ACCEPT: yes\nSCORE: 0.9\nRATIONALE: Correct.")
        local pv = require("propose_verify")
        local r = pv.run({ task = "Test task", score_threshold = 0.8 })
        expect(r.result.verdict).to.equal("DONE path=accepted")
    end)

    it("sets verdict DONE path=rejected when score < threshold", function()
        reset()
        mock_alc("A weak answer.", "ACCEPT: yes\nSCORE: 0.4\nRATIONALE: Partially correct.")
        local pv = require("propose_verify")
        local r = pv.run({ task = "Test task", score_threshold = 0.8 })
        -- score 0.4 < threshold 0.8 => rejected even if accept=yes
        expect(r.result.verdict).to.equal("DONE path=rejected")
    end)

    it("errors when score_threshold is missing", function()
        reset()
        mock_alc()
        local pv = require("propose_verify")
        local ok, err = pcall(pv.run, { task = "Test" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("score_threshold") ~= nil).to.equal(true)
    end)

    it("errors when task and all fallbacks are absent", function()
        reset()
        mock_alc()
        local pv = require("propose_verify")
        local ok, err = pcall(pv.run, { score_threshold = 0.5 })
        expect(ok).to.equal(false)
    end)

end)

reset()
