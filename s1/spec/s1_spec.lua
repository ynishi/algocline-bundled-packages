--- Tests for s1 package (Simple test-time scaling via budget forcing,
--- Muennighoff et al. 2025 arXiv:2501.19393). Initial think → Wait
--- extensions → forced finalization, with leak strip (paper §3
--- Minimum Token Enforcement at prompt level) and optional
--- max_total_thinking_tokens budget early-exit (paper §3 Maximum
--- Token Enforcement at prompt level).
---
--- Run via:
---   just alc-pkg-test-file s1/spec/s1_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc that distinguishes the three call kinds by
--- prompt substring (matches the literal user-prompt strings used in
--- s1/init.lua: "Begin your reasoning" for initial,
--- "Reasoning so far" for extend, otherwise finalize). Records every
--- call so tests can verify call counts, ordering, and system-prompt
--- consistency.
local function mock_alc(opts)
    opts = opts or {}
    local call_log = {}
    local c = { initial = 0, extend = 0, finalize = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options or {} }
            if prompt:find("Begin your reasoning", 1, true) then
                c.initial = c.initial + 1
                if opts.long_returns then
                    return string.rep("x", 8000)
                end
                return "initial_trace"
            elseif prompt:find("Reasoning so far", 1, true) then
                c.extend = c.extend + 1
                if opts.leak_at_extend and c.extend == opts.leak_at_extend then
                    return "tail before leak. Final Answer: 42 and trailing"
                end
                if opts.long_returns then
                    return string.rep("x", 8000)
                end
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

-- ============================================================
-- meta + spec exposure
-- ============================================================

describe("s1.meta", function()
    reset()
    mock_alc()
    local m = require("s1")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("s1")
        expect(m.meta.version).to.equal("0.2.0")
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

-- ============================================================
-- think_initial
-- ============================================================

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

-- ============================================================
-- extend (default Wait + leak detection)
-- ============================================================

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
        expect(ctx.result.leak_stripped).to.equal(false)
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

    -- Paper §3 Minimum Token Enforcement (prompt-level analogue):
    -- when the continuation leaks a final-answer-shaped closing,
    -- strip the leaked tail before accumulating into the trace.
    it("detects 'Final Answer:' leak, strips tail, sets leak_stripped=true", function()
        reset()
        _G.alc = {
            llm = function(_, _)
                return "intermediate reasoning. Final Answer: 42 and more"
            end,
            log = function() end,
        }
        local m = require("s1")
        local ctx = m.extend({ task = "Q", trace = "prior" })
        expect(ctx.result.leak_stripped).to.equal(true)
        expect(ctx.result.leak_pattern).to.equal("Final Answer:")
        -- continuation must not retain the leaked tail
        expect(ctx.result.continuation:find("Final Answer:", 1, true)).to.equal(nil)
        expect(ctx.result.continuation:find("intermediate reasoning", 1, true)).to_not.equal(nil)
        -- trace must not retain the leaked tail either
        expect(ctx.result.trace:find("Final Answer:", 1, true)).to.equal(nil)
        -- wait_literal is still appended (paper's forced-lengthen intent)
        expect(ctx.result.trace:find("Wait", 1, true)).to_not.equal(nil)
    end)

    it("leak_stripped=false when no pattern matches", function()
        reset()
        _G.alc = {
            llm = function(_, _) return "just plain reasoning" end,
            log = function() end,
        }
        local m = require("s1")
        local ctx = m.extend({ task = "Q", trace = "prior" })
        expect(ctx.result.leak_stripped).to.equal(false)
        expect(ctx.result.continuation).to.equal("just plain reasoning")
    end)

    it("respects caller-provided leak_patterns override", function()
        reset()
        _G.alc = {
            llm = function(_, _) return "thinking... TERMINATE_HERE done" end,
            log = function() end,
        }
        local m = require("s1")
        local ctx = m.extend({
            task = "Q",
            trace = "prior",
            leak_patterns = { "TERMINATE_HERE" },
        })
        expect(ctx.result.leak_stripped).to.equal(true)
        expect(ctx.result.leak_pattern).to.equal("TERMINATE_HERE")
        expect(ctx.result.continuation:find("TERMINATE_HERE", 1, true)).to.equal(nil)
    end)

    it("picks the earliest leak pattern when multiple match", function()
        reset()
        _G.alc = {
            llm = function(_, _)
                -- "Final answer:" appears before "Final Answer:" -- both in defaults
                return "x. Final answer: A. then. Final Answer: B"
            end,
            log = function() end,
        }
        local m = require("s1")
        local ctx = m.extend({ task = "Q", trace = "prior" })
        expect(ctx.result.leak_stripped).to.equal(true)
        expect(ctx.result.leak_pattern).to.equal("Final answer:")
        expect(ctx.result.continuation:find("Final answer:", 1, true)).to.equal(nil)
        expect(ctx.result.continuation:find("Final Answer:", 1, true)).to.equal(nil)
    end)
end)

-- ============================================================
-- finalize
-- ============================================================

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

-- ============================================================
-- run
-- ============================================================

describe("s1.run — basics + extensions_used contract", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("s1")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default max_extensions=4 → 1 initial + 4 extend + 1 finalize = 6 calls, exit_reason='max_extensions'", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q" })
        expect(#log).to.equal(6)
        expect(c.initial).to.equal(1)
        expect(c.extend).to.equal(4)
        expect(c.finalize).to.equal(1)
        expect(ctx.result.extensions_used).to.equal(4)
        expect(ctx.result.exit_reason).to.equal("max_extensions")
        expect(ctx.result.final_answer).to.equal("final_answer_text")
    end)

    it("max_extensions=0 → 1 initial + 0 extend + 1 finalize = 2 calls, exit_reason='max_extensions'", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 0 })
        expect(#log).to.equal(2)
        expect(c.initial).to.equal(1)
        expect(c.extend).to.equal(0)
        expect(c.finalize).to.equal(1)
        expect(ctx.result.extensions_used).to.equal(0)
        expect(ctx.result.exit_reason).to.equal("max_extensions")
    end)

    it("max_extensions=2 → 1 initial + 2 extend + 1 finalize = 4 calls", function()
        reset()
        local log, c = mock_alc()
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 2 })
        expect(#log).to.equal(4)
        expect(c.extend).to.equal(2)
        expect(ctx.result.extensions_used).to.equal(2)
        expect(ctx.result.exit_reason).to.equal("max_extensions")
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

-- ============================================================
-- run — paper §3 Maximum Token Enforcement (T_max early-exit)
-- ============================================================

describe("s1.run — max_total_thinking_tokens (paper Maximum Token Enforcement)", function()
    it("T_max=nil (default) → loop runs full max_extensions even with long traces", function()
        reset()
        local _, c = mock_alc({ long_returns = true })
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 3 })
        -- T_max disabled → no budget exit regardless of trace length
        expect(c.extend).to.equal(3)
        expect(ctx.result.extensions_used).to.equal(3)
        expect(ctx.result.exit_reason).to.equal("max_extensions")
    end)

    it("T_max triggers budget early-exit after partial extensions", function()
        reset()
        local _, c = mock_alc({ long_returns = true })
        local m = require("s1")
        -- Each long return is 8000 chars ≈ 2000 tokens at the default
        -- 4 chars/token heuristic. trace accumulates:
        --   after initial: ~2000 tokens
        --   after ext 1:   ~4000+ tokens  (still < 5000)
        --   after ext 2:   ~6000+ tokens  (>= 5000 → budget exit before ext 3)
        local ctx = m.run({
            task = "Q",
            max_extensions = 4,
            max_total_thinking_tokens = 5000,
        })
        expect(ctx.result.exit_reason).to.equal("budget")
        expect(ctx.result.extensions_used).to.equal(2)
        expect(c.extend).to.equal(2)
        expect(c.finalize).to.equal(1)
    end)

    it("T_max=0 → immediate budget exit before any extension", function()
        reset()
        local _, c = mock_alc()
        local m = require("s1")
        -- initial_trace is 13 chars ≈ 3 tokens, which is >= 0 → exit
        -- before any extend call fires.
        local ctx = m.run({
            task = "Q",
            max_extensions = 4,
            max_total_thinking_tokens = 0,
        })
        expect(ctx.result.exit_reason).to.equal("budget")
        expect(ctx.result.extensions_used).to.equal(0)
        expect(c.extend).to.equal(0)
        expect(c.finalize).to.equal(1)
    end)

    it("chars_per_token override (e.g. 2 for CJK) tightens the budget", function()
        reset()
        local _, c = mock_alc()
        local m = require("s1")
        -- initial_trace "initial_trace" is 13 chars. At chars_per_token=2
        -- the estimate is floor(13/2)=6 tokens. T_max=5 triggers exit
        -- immediately. At default 4 chars/token estimate=3 (< 5, no exit).
        local ctx = m.run({
            task = "Q",
            max_extensions = 4,
            max_total_thinking_tokens = 5,
            chars_per_token = 2,
        })
        expect(ctx.result.exit_reason).to.equal("budget")
        expect(ctx.result.extensions_used).to.equal(0)
    end)
end)

-- ============================================================
-- run — paper §3 single-persona invariant (unified system prompt)
-- ============================================================

describe("s1.run — unified system prompt across phases", function()
    it("every LLM call uses the same system prompt", function()
        reset()
        local log = mock_alc()
        local m = require("s1")
        m.run({ task = "Q", max_extensions = 2 })
        expect(#log).to.equal(4) -- 1 initial + 2 extend + 1 finalize
        local first_sys = log[1].opts.system
        expect(first_sys).to_not.equal(nil)
        for i = 2, #log do
            expect(log[i].opts.system).to.equal(first_sys)
        end
    end)
end)

-- ============================================================
-- run — nested dispatch via M.<entry> (alc_shapes README §Producer
-- usage "Nested dispatch"). Verified by monkey-patching the table
-- entries: if M.run calls through M.<entry>, the patched marker fires;
-- if M.run calls local closures, the marker is bypassed.
-- ============================================================

describe("s1.run — nested dispatch via M.<entry>", function()
    it("M.run calls through M.think_initial (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("s1")
        local marker = 0
        local orig = m.think_initial
        m.think_initial = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q", max_extensions = 2 })
        expect(marker).to.equal(1)
    end)

    it("M.run calls through M.extend (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("s1")
        local marker = 0
        local orig = m.extend
        m.extend = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q", max_extensions = 3 })
        expect(marker).to.equal(3)
    end)

    it("M.run calls through M.finalize (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("s1")
        local marker = 0
        local orig = m.finalize
        m.finalize = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q", max_extensions = 2 })
        expect(marker).to.equal(1)
    end)
end)

-- ============================================================
-- run — leak strip integration in the full pipeline
-- ============================================================

describe("s1.run — leak strip integration", function()
    it("leaked tail in extension does not contaminate the accumulated trace", function()
        reset()
        local _, c = mock_alc({ leak_at_extend = 2 })
        local m = require("s1")
        local ctx = m.run({ task = "Q", max_extensions = 4 })
        -- 4 extensions complete normally (leak is stripped, not skipped)
        expect(c.extend).to.equal(4)
        expect(ctx.result.extensions_used).to.equal(4)
        -- The leaked "Final Answer: 42" tail must not survive in the
        -- final accumulated trace (paper §3 forced-lengthen intent).
        expect(ctx.result.trace:find("Final Answer:", 1, true)).to.equal(nil)
        expect(ctx.result.trace:find("tail before leak", 1, true)).to_not.equal(nil)
    end)
end)
