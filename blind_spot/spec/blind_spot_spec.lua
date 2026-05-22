--- Tests for blind_spot package (Self-Correction Blind Spot,
--- arXiv:2507.02778, 2025). Externalize → correct → optional "Wait".
---
--- Run via:
---   just alc-pkg-test-file blind_spot/spec/blind_spot_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.correction_text — what the correction stub returns (default
---     contains 'ERROR' which trips the corrections_detected counter).
---   opts.wait_text — what the wait stub returns.
local function mock_alc(opts)
    opts = opts or {}
    local correction_text = opts.correction_text or "Found an ERROR; fixed answer here"
    local wait_text = opts.wait_text or "confirmed solid"
    local call_log = {}
    local log_calls = {}
    local c = { initial = 0, correction = 0, wait = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("colleague submitted the following", 1, true)
                or prompt:find("Colleague's answer", 1, true) then
                c.correction = c.correction + 1
                return correction_text
            elseif prompt:find("Wait%. Before finalizing") then
                c.wait = c.wait + 1
                return wait_text
            else
                c.initial = c.initial + 1
                return "initial_answer"
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
    package.loaded["blind_spot"] = nil
end

describe("blind_spot.meta", function()
    reset()
    mock_alc()
    local m = require("blind_spot")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("blind_spot")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("correction")
    end)
end)

describe("blind_spot.spec", function()
    reset()
    mock_alc()
    local m = require("blind_spot")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("blind_spot.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("blind_spot")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default rounds=1, wait=true → 1 initial + 1 correction + 1 wait = 3 calls", function()
        reset()
        local log = mock_alc()
        local m = require("blind_spot")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(3)
        expect(ctx.result.rounds).to.equal(1)
        expect(ctx.result.wait_applied).to.equal(true)
        expect(ctx.result.initial_answer).to.equal("initial_answer")
        expect(ctx.result.answer).to.equal("confirmed solid")
    end)

    it("wait=false skips the wait reflection (2 calls)", function()
        reset()
        local log = mock_alc()
        local m = require("blind_spot")
        local ctx = m.run({ task = "T", wait = false })
        expect(#log).to.equal(2)
        expect(ctx.result.wait_applied).to.equal(false)
        -- answer is the correction text since wait was skipped
        expect(ctx.result.answer:find("Found an ERROR", 1, true)).to_not.equal(nil)
    end)

    it("rounds=2 produces 2 correction calls", function()
        reset()
        local log = mock_alc()
        local m = require("blind_spot")
        local ctx = m.run({ task = "T", rounds = 2, wait = false })
        -- 1 initial + 2 corrections = 3
        expect(#log).to.equal(3)
        expect(ctx.result.rounds).to.equal(2)
    end)

    it("counts ERROR / INCORRECT / WRONG / FIX keywords as corrections_detected", function()
        reset()
        mock_alc({ correction_text = "INCORRECT — needs WRONG fix" })
        local m = require("blind_spot")
        local ctx = m.run({ task = "T", rounds = 1, wait = false })
        -- 1 correction round whose text matches keywords → 1 detection
        expect(ctx.result.corrections_detected).to.equal(1)
    end)

    it("no-keyword response yields corrections_detected = 0", function()
        reset()
        mock_alc({ correction_text = "the answer is fine and complete" })
        local m = require("blind_spot")
        local ctx = m.run({ task = "T", rounds = 1, wait = false })
        expect(ctx.result.corrections_detected).to.equal(0)
    end)

    it("history records initial + correction(s) + wait_reflection in order", function()
        reset()
        mock_alc()
        local m = require("blind_spot")
        local ctx = m.run({ task = "T", rounds = 1 })
        expect(#ctx.result.history).to.equal(3)
        expect(ctx.result.history[1].role).to.equal("initial")
        expect(ctx.result.history[2].role).to.equal("correction")
        expect(ctx.result.history[3].role).to.equal("wait_reflection")
        expect(ctx.result.history[3].round).to.equal(2)
    end)
end)

reset()
