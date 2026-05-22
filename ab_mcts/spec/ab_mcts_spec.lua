--- Tests for ab_mcts package (Adaptive Branching MCTS, Inoue et al.
--- 2025 arXiv:2503.04412 / NeurIPS 2025 Spotlight). The tree search has
--- internal randomness (Thompson Sampling on Beta posteriors); tests
--- pin math.randomseed() and verify call-count invariants + shape,
--- not the exact tree shape.
---
--- Run via:
---   just alc-pkg-test-file ab_mcts/spec/ab_mcts_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   alc.llm returns "thought_<n>" for expansion prompts and a numeric
---     string for evaluation prompts (parsed by alc.parse_score).
---   alc.parse_score parses the leading number out of a string.
---   alc.log records calls.
local function mock_alc()
    local call_log = {}
    local log_calls = {}
    local c = { thought = 0, score = 0, synth = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Rate this reasoning on a 0%-10 scale") then
                c.score = c.score + 1
                -- Return scores in [0,10] (cycling 7, 5, 8, 6 ...)
                local cycle = { "7", "5", "8", "6" }
                return cycle[((c.score - 1) % #cycle) + 1]
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
    package.loaded["ab_mcts"] = nil
    math.randomseed(42)
end

describe("ab_mcts.meta", function()
    reset()
    mock_alc()
    local m = require("ab_mcts")

    it("name / version / category", function()
        expect(m.meta.name).to.equal("ab_mcts")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("ab_mcts.spec", function()
    reset()
    mock_alc()
    local m = require("ab_mcts")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("ab_mcts.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("ab_mcts")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("budget=2 produces exactly 2*budget + 1 = 5 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 2, max_depth = 3 })
        expect(#log).to.equal(5)
        expect(ctx.result.tree_stats.budget).to.equal(2)
    end)

    it("budget=4 produces 9 LLM calls and wider+deeper == budget", function()
        reset()
        local log = mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 4, max_depth = 3 })
        expect(#log).to.equal(9)
        local w = ctx.result.tree_stats.wider_decisions
        local d = ctx.result.tree_stats.deeper_decisions
        expect(w + d).to.equal(4)
    end)

    it("result has answer + best_path + best_score + tree_stats", function()
        reset()
        mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 3, max_depth = 2 })
        expect(type(ctx.result.answer)).to.equal("string")
        expect(type(ctx.result.best_path)).to.equal("table")
        expect(type(ctx.result.best_score)).to.equal("number")
        expect(ctx.result.tree_stats.max_depth).to.equal(2)
        -- branching_ratio in [0, 1]
        local br = ctx.result.tree_stats.branching_ratio
        expect(br >= 0 and br <= 1).to.equal(true)
    end)

    it("synthesis prompt is the last call and uses the synthesis stub", function()
        reset()
        local log = mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 2 })
        local last_prompt = log[#log].prompt
        expect(last_prompt:find("Synthesize these reasoning steps", 1, true)).to_not.equal(nil)
        expect(ctx.result.answer:find("synthesis_", 1, true)).to_not.equal(nil)
    end)

    it("first iteration is always WIDER (empty tree forces gen)", function()
        reset()
        local log = mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 1, max_depth = 3 })
        expect(ctx.result.tree_stats.wider_decisions).to.equal(1)
        expect(ctx.result.tree_stats.deeper_decisions).to.equal(0)
        -- best_path has length 1 after a single expansion
        expect(#ctx.result.best_path).to.equal(1)
        expect(ctx.result.best_path[1]:find("thought_", 1, true)).to_not.equal(nil)
    end)

    it("total_nodes equals budget + 1 (root + one node per iteration)", function()
        reset()
        mock_alc()
        local m = require("ab_mcts")
        local ctx = m.run({ task = "T", budget = 3, max_depth = 3 })
        expect(ctx.result.tree_stats.total_nodes).to.equal(4)
    end)
end)

reset()
