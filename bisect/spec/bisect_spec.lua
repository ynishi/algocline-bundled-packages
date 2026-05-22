--- Tests for bisect package (binary-search-based reasoning chain
--- repair; PRM arXiv:2410.08146 + git bisect methodology).
---
--- Run via:
---   just alc-pkg-test-file bisect/spec/bisect_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local CHAIN_4_STEPS =
    "Step 1: first move\nStep 2: second move\nStep 3: third move\nStep 4: fourth move\nFinal Answer: x\n"

--- Build a mock _G.alc.
---   opts.verdict_fn(mid) — invoked per verify call with the current
---     `mid` (the size of the prefix being checked). Returns the verdict
---     string. Default verdict returns CORRECT (no error found).
local function mock_alc(opts)
    opts = opts or {}
    local verdict_fn = opts.verdict_fn or function() return "CORRECT — looks fine" end
    local chain_text = opts.chain_text or CHAIN_4_STEPS
    local call_log = {}
    local log_calls = {}
    local c = { chain = 0, verify = 0, regen = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("first %d+ steps of a reasoning chain") then
                c.verify = c.verify + 1
                -- Extract mid count from the prompt
                local mid = tonumber(prompt:match("first (%d+) steps")) or 0
                return verdict_fn(mid, c.verify)
            elseif prompt:find("Continue the reasoning from after", 1, true) then
                c.regen = c.regen + 1
                return string.format(
                    "Step %d: regen move\nFinal Answer: y",
                    tonumber(prompt:match("starting from Step (%d+)")) or 1
                )
            else
                c.chain = c.chain + 1
                return chain_text
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
    package.loaded["bisect"] = nil
end

describe("bisect.meta", function()
    reset()
    mock_alc()
    local m = require("bisect")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("bisect")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("debugging")
    end)
end)

describe("bisect.spec", function()
    reset()
    mock_alc()
    local m = require("bisect")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("bisect.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("bisect")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("all-correct chain → zero repairs (loop breaks on first no-error)", function()
        reset()
        local log = mock_alc()  -- default verdict CORRECT
        local m = require("bisect")
        local ctx = m.run({ task = "T", max_repairs = 2 })
        expect(ctx.result.total_repairs).to.equal(0)
        expect(#ctx.result.repairs).to.equal(0)
        -- 1 initial chain + 1 all-ok verify = 2 (loop breaks before 2nd repair)
        expect(#log).to.equal(2)
        expect(ctx.result.answer).to.equal(ctx.result.initial_chain)
    end)

    it("error chain → 1 repair, bisect_log non-empty, regenerate fires", function()
        reset()
        -- Step 3 onward is wrong: all-ok says INCORRECT; mid=2 CORRECT;
        -- mid=3 INCORRECT → first error at step 3.
        local function verdict(mid)
            if mid >= 3 then return "INCORRECT at later step" end
            return "CORRECT so far"
        end
        local log = mock_alc({ verdict_fn = verdict })
        local m = require("bisect")
        local ctx = m.run({ task = "T", max_repairs = 1 })
        expect(ctx.result.total_repairs).to.equal(1)
        local rep = ctx.result.repairs[1]
        expect(rep.repair_round).to.equal(1)
        expect(rep.error_step).to.equal(3)
        expect(rep.error_label:find("Step 3", 1, true)).to_not.equal(nil)
        expect(#rep.bisect_log >= 1).to.equal(true)
        expect(rep.regenerated:find("regen move", 1, true)).to_not.equal(nil)
        -- merged answer contains the regenerated suffix
        expect(ctx.result.answer:find("regen move", 1, true)).to_not.equal(nil)
    end)

    it("error_step=1 case → empty correct prefix, regenerate from step 1", function()
        reset()
        local function verdict(mid)
            return "INCORRECT from the start"
        end
        local log = mock_alc({ verdict_fn = verdict })
        local m = require("bisect")
        local ctx = m.run({ task = "T", max_repairs = 1 })
        expect(ctx.result.total_repairs).to.equal(1)
        expect(ctx.result.repairs[1].error_step).to.equal(1)
    end)

    it("chain too short to bisect (<=1 step) breaks the loop", function()
        reset()
        mock_alc({ chain_text = "Step 1: only step\nFinal Answer: x\n" })
        local m = require("bisect")
        local ctx = m.run({ task = "T", max_repairs = 2 })
        expect(ctx.result.total_repairs).to.equal(0)
    end)
end)

reset()
