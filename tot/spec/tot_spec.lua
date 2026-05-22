--- Tests for tot package (Tree-of-Thoughts, Yao et al. 2023
--- arXiv:2305.10601). Beam-search with thought generation + scoring.
---
--- Run via:
---   just alc-pkg-test-file tot/spec/tot_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc. Scores cycle 7 / 5 / 8 so beam ordering is
--- predictable. Thoughts and scores are routed by prompt substring.
local function mock_alc()
    local call_log = {}
    local log_calls = {}
    local c = { thought = 0, score = 0, synth = 0 }
    local score_cycle = { "7", "5", "8", "6" }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Reply with ONLY the number", 1, true)
                and prompt:find("Evaluate this reasoning direction", 1, true) then
                c.score = c.score + 1
                return score_cycle[((c.score - 1) % #score_cycle) + 1]
            elseif prompt:find("Synthesize these reasoning steps", 1, true) then
                c.synth = c.synth + 1
                return "synthesis_" .. c.synth
            else
                c.thought = c.thought + 1
                return "thought_" .. c.thought
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
    package.loaded["tot"] = nil
end

describe("tot.meta", function()
    reset()
    mock_alc()
    local m = require("tot")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("tot")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("tot.spec", function()
    reset()
    mock_alc()
    local m = require("tot")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("tot.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("tot")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("depth=1, breadth=2, beam_width=1 → 2 gen + 2 score + 1 synth = 5 calls", function()
        reset()
        local log = mock_alc()
        local m = require("tot")
        local ctx = m.run({ task = "T", depth = 1, breadth = 2, beam_width = 1 })
        expect(#log).to.equal(5)
        expect(#ctx.result.explored_paths).to.equal(1)
        expect(#ctx.result.best_path).to.equal(1)
        expect(ctx.result.tree_stats.depth).to.equal(1)
        expect(ctx.result.tree_stats.breadth).to.equal(2)
        expect(ctx.result.tree_stats.beam_width).to.equal(1)
    end)

    it("depth=2, breadth=2, beam_width=1 → 1*2*2 gen + 4 score + 1 synth = 9 calls", function()
        reset()
        local log = mock_alc()
        local m = require("tot")
        local ctx = m.run({ task = "T", depth = 2, breadth = 2, beam_width = 1 })
        expect(#log).to.equal(9)
        expect(#ctx.result.best_path).to.equal(2)
    end)

    it("conclusion is the synthesis stub value", function()
        reset()
        mock_alc()
        local m = require("tot")
        local ctx = m.run({ task = "T", depth = 1, breadth = 2, beam_width = 1 })
        expect(ctx.result.conclusion).to.equal("synthesis_1")
    end)

    it("explored_paths are rank-ordered by score (best first)", function()
        reset()
        mock_alc()
        local m = require("tot")
        -- breadth=3 with scores cycling 7/5/8 → best is the 3rd (score 8)
        local ctx = m.run({ task = "T", depth = 1, breadth = 3, beam_width = 2 })
        expect(#ctx.result.explored_paths).to.equal(2)
        expect(ctx.result.explored_paths[1].rank).to.equal(1)
        expect(ctx.result.explored_paths[1].score >= ctx.result.explored_paths[2].score).to.equal(true)
        expect(ctx.result.best_score).to.equal(ctx.result.explored_paths[1].score)
    end)

    it("synthesis prompt is the final call and embeds best path", function()
        reset()
        local log = mock_alc()
        local m = require("tot")
        m.run({ task = "T", depth = 1, breadth = 2, beam_width = 1 })
        local last = log[#log].prompt
        expect(last:find("Synthesize these reasoning steps", 1, true)).to_not.equal(nil)
        expect(last:find("thought_", 1, true)).to_not.equal(nil)
    end)
end)

reset()
