--- Tests for php package (Progressive-Hint Prompting, Zheng et al.
--- 2023 arXiv:2304.09797).
---
--- Run via:
---   just alc-pkg-test-file php/spec/php_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.match_at — round at which conclusions_match returns SAME
---     (controls early convergence). Use math.huge for never-converge.
local function mock_alc(opts)
    opts = opts or {}
    local match_at = opts.match_at or math.huge
    local call_log = {}
    local log_calls = {}
    local c = { solve = 0, extract = 0, match = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Extract ONLY the core conclusion", 1, true) then
                c.extract = c.extract + 1
                return "conclusion_" .. c.extract
            elseif prompt:find("Do these two conclusions reach the SAME", 1, true) then
                c.match = c.match + 1
                if c.match >= match_at then return "SAME" else return "DIFFERENT" end
            else
                c.solve = c.solve + 1
                return "answer_" .. c.solve
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
    package.loaded["php"] = nil
end

describe("php.meta", function()
    reset()
    mock_alc()
    local m = require("php")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("php")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("php.spec", function()
    reset()
    mock_alc()
    local m = require("php")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("php.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("php")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("converges at round 2 (SAME on first match check)", function()
        reset()
        local log = mock_alc({ match_at = 1 })
        local m = require("php")
        local ctx = m.run({ task = "T" })
        -- R1: solve + extract = 2
        -- R2: solve + extract + match(SAME → break) = 3
        -- After: 1 final converged check = 1
        expect(#log).to.equal(6)
        expect(ctx.result.total_rounds).to.equal(2)
        expect(ctx.result.converged).to.equal(true)
        expect(ctx.result.rounds[1].hint_used).to.equal(false)
        expect(ctx.result.rounds[2].hint_used).to.equal(true)
    end)

    it("max_rounds=4 with no convergence → 2 + 3 + 3 + 3 + 1 final = 12 LLM calls", function()
        reset()
        local log = mock_alc({ match_at = math.huge })
        local m = require("php")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(12)
        expect(ctx.result.total_rounds).to.equal(4)
        expect(ctx.result.converged).to.equal(false)
    end)

    it("max_rounds=1 produces only round 1 (no hint round, converged=false)", function()
        reset()
        local log = mock_alc()
        local m = require("php")
        local ctx = m.run({ task = "T", max_rounds = 1 })
        -- R1: solve + extract = 2. After loop: #rounds < 2 → converged=false, no final match call
        expect(#log).to.equal(2)
        expect(ctx.result.total_rounds).to.equal(1)
        expect(ctx.result.converged).to.equal(false)
    end)

    it("round records carry round / answer / conclusion / hint_used", function()
        reset()
        mock_alc({ match_at = 1 })
        local m = require("php")
        local ctx = m.run({ task = "T" })
        local r1 = ctx.result.rounds[1]
        expect(r1.round).to.equal(1)
        expect(r1.answer).to.equal("answer_1")
        expect(r1.conclusion).to.equal("conclusion_1")
        expect(r1.hint_used).to.equal(false)
    end)

    it("hint round prompt embeds prior conclusions", function()
        reset()
        local log = mock_alc({ match_at = math.huge })
        local m = require("php")
        m.run({ task = "T", max_rounds = 2 })
        -- log[3] is the round-2 solve prompt (with hints)
        local hint_prompt = log[3].prompt
        expect(hint_prompt:find("Previous attempts", 1, true)).to_not.equal(nil)
        expect(hint_prompt:find("conclusion_1", 1, true)).to_not.equal(nil)
    end)
end)

reset()
