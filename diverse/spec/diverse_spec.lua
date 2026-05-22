--- Tests for diverse package (DiVERSe step-aware verifier, Li et al.
--- 2022 arXiv:2206.02336).
---
--- Run via:
---   just alc-pkg-test-file diverse/spec/diverse_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc. Reasoning paths are generated with predictable
--- numbered steps so the parser can pick them up. Scores cycle through
--- a fixed sequence to make the per-path ordering deterministic.
local function mock_alc(opts)
    opts = opts or {}
    local reasoning_text = opts.reasoning_text
        or "Step 1: first step content here\nStep 2: second step content here\nStep 3: third step content here\n"
    local single_block = opts.single_block_text  -- when set, generation returns this (unparseable as steps)
    local call_log = {}
    local log_calls = {}
    local c = { gen = 0, verify = 0, fallback = 0, synth = 0 }
    -- Score cycles: rotate per gen path so path-2 (5/5/5=5) loses to
    -- path-1 (7/5/8 ≈ 6.67) etc.
    local score_cycle = { 7, 5, 8, 6, 9, 4 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Rate correctness 1%-10", 1, true) then
                c.verify = c.verify + 1
                return tostring(score_cycle[((c.verify - 1) % #score_cycle) + 1])
            elseif prompt:find("Rate the overall correctness", 1, true) then
                c.fallback = c.fallback + 1
                return "9"
            elseif prompt:find("Synthesize this reasoning", 1, true) then
                c.synth = c.synth + 1
                return "synthesis_" .. c.synth
            else
                c.gen = c.gen + 1
                return single_block or reasoning_text
            end
        end,
        parse_score = function(s)
            return tonumber((tostring(s):match("([%-]?%d+%.?%d*)"))) or 0
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls
end

local function reset()
    _G.alc = nil
    package.loaded["diverse"] = nil
end

describe("diverse.meta", function()
    reset()
    mock_alc()
    local m = require("diverse")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("diverse")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("diverse.spec", function()
    reset()
    mock_alc()
    local m = require("diverse")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("diverse.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("diverse")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default n_paths=3, 3 steps each → 3 gen + 3*3 verify + 1 synth = 13 calls", function()
        reset()
        local log = mock_alc()
        local m = require("diverse")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(13)
        expect(#ctx.result.paths).to.equal(3)
        expect(#ctx.result.ranking).to.equal(3)
        expect(ctx.result.answer:find("synthesis_", 1, true)).to_not.equal(nil)
    end)

    it("ranking is sorted by avg_score desc and best_path_id matches rank 1", function()
        reset()
        mock_alc()
        local m = require("diverse")
        local ctx = m.run({ task = "T", n_paths = 3 })
        expect(ctx.result.ranking[1].rank).to.equal(1)
        local r = ctx.result.ranking
        expect(r[1].avg_score >= r[2].avg_score).to.equal(true)
        expect(r[2].avg_score >= r[3].avg_score).to.equal(true)
        expect(ctx.result.best_path_id).to.equal(r[1].path_id)
        expect(ctx.result.best_avg_score).to.equal(r[1].avg_score)
    end)

    it("n_paths=2 with 3 steps each → 2 gen + 6 verify + 1 synth = 9 calls", function()
        reset()
        local log = mock_alc()
        local m = require("diverse")
        m.run({ task = "T", n_paths = 2 })
        expect(#log).to.equal(9)
    end)

    it("each path's verification has step_scores / total_score / avg_score", function()
        reset()
        mock_alc()
        local m = require("diverse")
        local ctx = m.run({ task = "T", n_paths = 2 })
        local v = ctx.result.paths[1].verification
        expect(#v.step_scores).to.equal(3)
        expect(v.total_score > 0).to.equal(true)
        expect(v.avg_score).to.equal(v.total_score / 3)
    end)

    it("unparseable reasoning falls back to single-block scoring + warn log", function()
        reset()
        local log, log_calls = mock_alc({ single_block_text = "one short line" })
        local m = require("diverse")
        local ctx = m.run({ task = "T", n_paths = 1 })
        -- 1 gen + 1 fallback score + 1 synth = 3
        expect(#log).to.equal(3)
        expect(#ctx.result.paths[1].verification.step_scores).to.equal(1)
        local warn_seen = false
        for _, lc in ipairs(log_calls) do
            if lc.level == "warn" then warn_seen = true end
        end
        expect(warn_seen).to.equal(true)
    end)
end)

reset()
