--- Tests for ucb package (UCB1 hypothesis exploration).
---
--- Run via:
---   just alc-pkg-test-file ucb/spec/ucb_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc. Generation, scoring, refinement are routed
--- by prompt substring. Scores cycle through a deterministic sequence.
local function mock_alc()
    local call_log = {}
    local c = { gen = 0, score = 0, refine = 0 }
    local score_cycle = { "7", "5", "8", "6", "9" }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Rate hypothesis #", 1, true) then
                c.score = c.score + 1
                return score_cycle[((c.score - 1) % #score_cycle) + 1]
            elseif prompt:find("Refine and strengthen it", 1, true) then
                c.refine = c.refine + 1
                return "refined_" .. c.refine
            else
                c.gen = c.gen + 1
                return "hypothesis_" .. c.gen
            end
        end,
        parse_score = function(s)
            return tonumber((tostring(s):match("([%-]?%d+%.?%d*)"))) or 0
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["ucb"] = nil
end

describe("ucb.meta", function()
    reset()
    mock_alc()
    local m = require("ucb")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("ucb")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("selection")
    end)
end)

describe("ucb.spec", function()
    reset()
    mock_alc()
    local m = require("ucb")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("ucb.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("ucb")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default n=3 / rounds=2 → 3 gen + 2*(3 score + 1 refine) = 11 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("ucb")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(11)
        expect(#ctx.result.ranking).to.equal(3)
    end)

    it("n=2 / rounds=1 → 2 gen + 1*(2 score + 1 refine) = 5 calls", function()
        reset()
        local log = mock_alc()
        local m = require("ucb")
        local ctx = m.run({ task = "T", n = 2, rounds = 1 })
        expect(#log).to.equal(5)
        expect(#ctx.result.ranking).to.equal(2)
    end)

    it("ranking sorted by avg_score desc and ranks numbered 1..N", function()
        reset()
        mock_alc()
        local m = require("ucb")
        local ctx = m.run({ task = "T", n = 3, rounds = 2 })
        local r = ctx.result.ranking
        for i = 1, #r - 1 do
            expect(r[i].avg_score >= r[i + 1].avg_score).to.equal(true)
        end
        for i, entry in ipairs(r) do
            expect(entry.rank).to.equal(i)
        end
        expect(ctx.result.best).to.equal(r[1].hypothesis)
    end)

    it("each ranked entry carries pulls > 0", function()
        reset()
        mock_alc()
        local m = require("ucb")
        local ctx = m.run({ task = "T", n = 2, rounds = 2 })
        for _, entry in ipairs(ctx.result.ranking) do
            expect(entry.pulls > 0).to.equal(true)
        end
    end)

    it("rounds=0 → only generation, no scoring or refining", function()
        reset()
        local log = mock_alc()
        local m = require("ucb")
        local ctx = m.run({ task = "T", n = 3, rounds = 0 })
        expect(#log).to.equal(3)
        for _, entry in ipairs(ctx.result.ranking) do
            expect(entry.pulls).to.equal(0)
            expect(entry.avg_score).to.equal(0)
        end
    end)
end)

reset()
