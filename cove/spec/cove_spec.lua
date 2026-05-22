--- Tests for cove package (Chain-of-Verification, Dhuliawala et al.
--- 2023 arXiv:2309.11495). Draft → verify questions → independently
--- answer → revise.
---
--- Run via:
---   just alc-pkg-test-file cove/spec/cove_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.vq_text — verification-question list returned by Phase 2.
---     Default: "1. q one\n2. q two\n3. q three\n" (parseable).
local function mock_alc(opts)
    opts = opts or {}
    local vq_text = opts.vq_text
        or "1. is claim X correct\n2. does fact Y hold\n3. is Z accurate\n"
    local call_log = {}
    local c = { draft = 0, vq = 0, ans = 0, final = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Generate exactly %d+ verification questions") then
                c.vq = c.vq + 1
                return vq_text
            elseif prompt:find("Answer this question accurately and concisely") then
                c.ans = c.ans + 1
                return "answer_" .. c.ans
            elseif prompt:find("Revise the draft answer based on", 1, true) then
                c.final = c.final + 1
                return "final_revised"
            else
                c.draft = c.draft + 1
                return "initial draft"
            end
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["cove"] = nil
end

describe("cove.meta", function()
    reset()
    mock_alc()
    local m = require("cove")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("cove")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("validation")
    end)
end)

describe("cove.spec", function()
    reset()
    mock_alc()
    local m = require("cove")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("cove.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("cove")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default n_questions=3 with parseable VQ → 6 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("cove")
        local ctx = m.run({ task = "T" })
        -- 1 draft + 1 vq + 3 answers + 1 final = 6
        expect(#log).to.equal(6)
        expect(#ctx.result.verifications).to.equal(3)
        expect(ctx.result.draft).to.equal("initial draft")
        expect(ctx.result.final_response).to.equal("final_revised")
    end)

    it("populates verifications with question + answer", function()
        reset()
        mock_alc()
        local m = require("cove")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.verifications[1].question).to.equal("is claim X correct")
        expect(ctx.result.verifications[1].answer).to.equal("answer_1")
        expect(ctx.result.verifications[3].question).to.equal("is Z accurate")
        expect(ctx.result.verifications[3].answer).to.equal("answer_3")
    end)

    it("n_questions=2 → 1 draft + 1 vq + 2 answers + 1 final = 5 calls", function()
        reset()
        local log = mock_alc()
        local m = require("cove")
        local ctx = m.run({ task = "T", n_questions = 2 })
        expect(#log).to.equal(5)
        expect(#ctx.result.verifications).to.equal(2)
    end)

    it("unparseable VQ output → zero verifications (only draft + vq + final = 3)", function()
        reset()
        local log = mock_alc({ vq_text = "rambling prose with no numbered list" })
        local m = require("cove")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(3)
        expect(#ctx.result.verifications).to.equal(0)
    end)

    it("supports bullet-style ('- q') verification questions", function()
        reset()
        local log = mock_alc({ vq_text = "- bullet q one is long enough\n- bullet q two is long enough\n" })
        local m = require("cove")
        local ctx = m.run({ task = "T", n_questions = 2 })
        expect(#ctx.result.verifications).to.equal(2)
    end)
end)

reset()
