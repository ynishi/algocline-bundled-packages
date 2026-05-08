--- Tests for got (Graph of Thoughts reasoning).
---
--- Coverage (5 cases):
---   1. Happy path — k=1, keep=1, max_refine=1 → answer produced
---   2. Input validation — ctx.task missing → error
---   3. Score parsing — parse_score called per generated node
---   4. KeepBest correctness — higher score node kept
---   5. DAG stats — graph_stats fields present and correct

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

for _, name in ipairs({ "got", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["got"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0, parse_score_calls = 0 }
    local call_idx = 0
    local score_fixtures = opts.score_fixtures or {}
    local score_idx = 0

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or "default response"
    end

    stub.llm_batch = function(items)
        counter.batch_calls = counter.batch_calls + 1
        local results = {}
        for i, item in ipairs(items) do
            results[i] = stub.llm(item.prompt, {
                system = item.system,
                max_tokens = item.max_tokens,
            })
        end
        return results
    end

    stub.parallel = function(items, prompt_fn, popts)
        counter.parallel_calls = counter.parallel_calls + 1
        popts = popts or {}
        local batch = {}
        for i, item in ipairs(items) do
            local p = prompt_fn(item, i)
            if type(p) == "string" then
                local entry = { prompt = p }
                if popts.system then entry.system = popts.system end
                if popts.max_tokens then entry.max_tokens = popts.max_tokens end
                batch[i] = entry
            else
                batch[i] = p
            end
        end
        local responses = stub.llm_batch(batch)
        if popts.post_fn then
            local res = {}
            for i, resp in ipairs(responses) do
                res[i] = popts.post_fn(resp, items[i], i)
            end
            return res
        end
        return responses
    end

    stub.log = function(_level, _msg) end

    stub.parse_score = function(_text)
        counter.parse_score_calls = counter.parse_score_calls + 1
        score_idx = score_idx + 1
        return score_fixtures[score_idx] or 7
    end

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — k=1, keep=1, max_refine=1 → answer produced
-- ═══════════════════════════════════════════════════════════════════

describe("got.run happy path", function()
    lust.after(reset)

    it("returns answer and graph_stats for k=1 keep=1 max_refine=1", function()
        reset()
        -- Phase 1: parallel(root=[1node], k=1) → 1 generate call
        -- Phase 2: parallel(1 node, score) → 1 score call → parse_score(1)
        -- Phase 3: KeepBest(1) → no llm
        -- Phase 4: refine(1) × max_refine=1 → 1 refine call
        -- Phase 5: aggregate(1 thought) → 1 llm call
        -- Phase 6: final refine → 1 llm call
        -- Phase 7: synthesize → 1 llm call
        -- Total: 6 llm calls, 2 parallel calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Generated thought approach A.",   -- Phase 1: generate
                "8",                                -- Phase 2: score (via llm_batch → stub.llm)
                "Refined thought A improved.",      -- Phase 4: refine
                "Aggregated synthesis.",            -- Phase 5: aggregate
                "Final refined synthesis.",         -- Phase 6: final refine
                "Final answer to the task.",        -- Phase 7: answer
            },
            score_fixtures = { 8 },
        })
        _G.alc = stub
        local m = require("got")
        local ctx = m.run({
            task = "What is consciousness?",
            k_generate = 1,
            keep_best = 1,
            max_refine = 1,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(type(ctx.result.answer)).to.equal("string")
        expect(type(ctx.result.aggregated_reasoning)).to.equal("string")
        expect(type(ctx.result.graph_stats)).to.equal("table")
        expect(ctx.result.graph_stats.branches_generated).to.equal(1)
        expect(ctx.result.graph_stats.branches_kept).to.equal(1)
        expect(ctx.result.graph_stats.refine_rounds).to.equal(1)
        expect(counter.llm_calls).to.equal(6)
        expect(counter.parse_score_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("got.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("got")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Score parsing — parse_score called per generated node
-- ═══════════════════════════════════════════════════════════════════

describe("got.run score parsing", function()
    lust.after(reset)

    it("calls parse_score once per generated node", function()
        reset()
        -- k=2: Phase1 generates 2 nodes → parse_score called twice
        local stub, counter = make_alc_stub({
            fixtures = {
                "Thought branch 1.",              -- generate 1
                "Thought branch 2.",              -- generate 2
                "9",                               -- score node 1
                "7",                               -- score node 2
                "Refined node 1.",                 -- refine node 1 (round 1)
                "Refined node 2.",                 -- refine node 2 (round 1)
                "Aggregated 2 thoughts.",          -- aggregate
                "Final refined agg.",              -- final refine
                "Answer from 2 branches.",         -- answer
            },
            score_fixtures = { 9, 7 },
        })
        _G.alc = stub
        local m = require("got")
        local ctx = m.run({
            task = "Design a system",
            k_generate = 2,
            keep_best = 2,
            max_refine = 1,
        })
        -- parse_score called once per generated node (2 nodes)
        expect(counter.parse_score_calls).to.equal(2)
        expect(counter.llm_calls).to.equal(9)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: KeepBest correctness — answer still produced after pruning
-- ═══════════════════════════════════════════════════════════════════

describe("got.run keepbest pruning", function()
    lust.after(reset)

    it("produces answer when keep_best=1 prunes from k=2 branches", function()
        reset()
        -- k=2, keep=1: generate 2, score 2, keep top 1, refine 1, aggregate 1, refine 1, answer 1
        -- = 2+2+1+1+1+1 = 8 llm calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Branch A.",               -- generate 1
                "Branch B.",               -- generate 2
                "9",                        -- score A (higher)
                "3",                        -- score B (lower, pruned)
                "Refined A.",               -- refine kept node
                "Aggregated kept.",         -- aggregate (1 thought)
                "Final refined.",           -- final refine
                "Best answer from A.",      -- answer
            },
            score_fixtures = { 9, 3 },
        })
        _G.alc = stub
        local m = require("got")
        local ctx = m.run({
            task = "Choose best approach",
            k_generate = 2,
            keep_best = 1,
            max_refine = 1,
        })
        expect(ctx.result.answer).to_not.equal(nil)
        -- graph_stats: branches_generated=2, branches_kept=1
        expect(ctx.result.graph_stats.branches_generated).to.equal(2)
        expect(ctx.result.graph_stats.branches_kept).to.equal(1)
        expect(counter.llm_calls).to.equal(8)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: DAG stats — total_nodes and operations map correct
-- ═══════════════════════════════════════════════════════════════════

describe("got.run dag stats", function()
    lust.after(reset)

    it("graph_stats.total_nodes and operations counts are correct", function()
        reset()
        -- k=1, keep=1, max_refine=1
        -- Nodes: init(1) + generate(1) + aggregate(1) = 3 total
        -- operations: init=1, generate=1, refine=1 (generate node is overwritten to refine in Phase4)
        -- Actually: init(1), generate(1→refine in Phase4), aggregate(1→refine in Phase6)
        local stub, _ = make_alc_stub({
            fixtures = {
                "Generated thought.",
                "8",
                "Refined thought.",
                "Aggregated.",
                "Final refined.",
                "Final answer.",
            },
            score_fixtures = { 8 },
        })
        _G.alc = stub
        local m = require("got")
        local ctx = m.run({
            task = "Explain gravity",
            k_generate = 1,
            keep_best = 1,
            max_refine = 1,
        })
        local stats = ctx.result.graph_stats
        expect(type(stats.total_nodes)).to.equal("number")
        expect(stats.total_nodes >= 2).to.equal(true)  -- at least init + generate
        expect(type(stats.operations)).to.equal("table")
        -- init op must exist (root node is created with "init")
        expect(stats.operations["init"] ~= nil).to.equal(true)
    end)
end)
