--- Tests for s1 package (Simple test-time scaling via budget forcing,
--- Muennighoff et al. 2025 arXiv:2501.19393). Initial think → Wait
--- extensions → forced finalization.
---
--- Run via:
---   just alc-pkg-test-file s1/spec/s1_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc that distinguishes the three call kinds by prompt
--- substring (matches the literal strings used in s1/init.lua).
local function mock_alc()
    local call_log = {}
    local c = { initial = 0, extend = 0, finalize = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Think through this step by step", 1, true) then
                c.initial = c.initial + 1
                return "initial_trace"
            elseif prompt:find("Reasoning so far", 1, true) then
                c.extend = c.extend + 1
                return "ext_" .. c.extend
            else
                c.finalize = c.finalize + 1
                return "final_answer_text"
            end
        end,
        log = function() end,
    }
    return call_log, c
end

local function reset()
    _G.alc = nil
    package.loaded["s1"] = nil
end

describe("s1.meta", function()
    reset()
    mock_alc()
    local m = require("s1")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("s1")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("refinement")
    end)
end)

describe("s1.spec", function()
    reset()
    mock_alc()
    local m = require("s1")
    it("exposes think_initial / extend / finalize / run input + result", function()
        for _, entry in ipairs({ "think_initial", "extend", "finalize", "run" }) do
            expect(m.spec.entries[entry]).to_not.equal(nil)
            expect(m.spec.entries[entry].input).to_not.equal(nil)
            expect(m.spec.entries[entry].result).to_not.equal(nil)
        end
    end)
end)

describe("s1.think_initial", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.think_initial, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("produces a trace from a single initial LLM call", function()
        reset()
        local log = mock_alc()
        local m = require("s1")
        local ctx = m.think_initial({ task = "Q" })
        expect(#log).to.equal(1)
        expect(ctx.result.trace).to.equal("initial_trace")
    end)
end)

describe("s1.extend", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.extend, { trace = "T" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("errors when ctx.trace is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.extend, { task = "Q" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.trace")).to_not.equal(nil)
    end)

    it("appends default wait_literal 'Wait' and continuation to trace", function()
        reset()
        local log = mock_alc()
        local m = require("s1")
        local ctx = m.extend({ task = "Q", trace = "prior_trace" })
        expect(#log).to.equal(1)
        expect(ctx.result.continuation).to.equal("ext_1")
        -- The trace must literally include the wait cue between prior
        -- trace and continuation, so subsequent extensions see it as
        -- part of the accumulated reasoning context.
        expect(ctx.result.trace:find("prior_trace", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("Wait", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("ext_1", 1, true)).to_not.equal(nil)
    end)

    it("respects wait_literal override (e.g. 'Alternatively')", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ctx = m.extend({
            task = "Q",
            trace = "prior",
            wait_literal = "Alternatively",
        })
        expect(ctx.result.trace:find("Alternatively", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("Wait", 1, true)).to.equal(nil)
    end)
end)

describe("s1.finalize", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.finalize, { trace = "T" })
        expect(ok).to.equal(false)
    end)

    it("errors when ctx.trace is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.finalize, { task = "Q" })
        expect(ok).to.equal(false)
    end)

    it("produces a final_answer from one LLM call", function()
        reset()
        local log = mock_alc()
        local m = require("s1")
        local ctx = m.finalize({ task = "Q", trace = "full_trace" })
        expect(#log).to.equal(1)
        expect(ctx.result.final_answer).to.equal("final_answer_text")
    end)
end)

describe("s1.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default max_extensions=4 → 1 initial + 4 extend + 1 finalize = 6 calls", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q" })
        expect(#log).to.equal(6)
        expect(c.initial).to.equal(1)
        expect(c.extend).to.equal(4)
        expect(c.finalize).to.equal(1)
        expect(ctx.result.extensions_used).to.equal(4)
        expect(ctx.result.final_answer).to.equal("final_answer_text")
    end)

    it("max_extensions=0 → 1 initial + 0 extend + 1 finalize = 2 calls", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 0 })
        expect(#log).to.equal(2)
        expect(c.initial).to.equal(1)
        expect(c.extend).to.equal(0)
        expect(c.finalize).to.equal(1)
        expect(ctx.result.extensions_used).to.equal(0)
    end)

    it("max_extensions=2 → 1 initial + 2 extend + 1 finalize = 4 calls", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 2 })
        expect(#log).to.equal(4)
        expect(c.extend).to.equal(2)
        expect(ctx.result.extensions_used).to.equal(2)
    end)

    it("trace accumulates initial + all extensions", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 3 })
        expect(ctx.result.trace:find("initial_trace", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("ext_1", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("ext_2", 1, true)).to_not.equal(nil)
        expect(ctx.result.trace:find("ext_3", 1, true)).to_not.equal(nil)
    end)

    it("wait_literal override propagates into trace", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ctx = m.run({
            task = "Q",
            max_extensions = 2,
            wait_literal = "Hmm",
        })
        local _, hmm_count = ctx.result.trace:gsub("Hmm", "")
        expect(hmm_count).to.equal(2)
        -- Default "Wait" must not leak when overridden
        expect(ctx.result.trace:find("Wait", 1, true)).to.equal(nil)
    end)
end)

reset()
