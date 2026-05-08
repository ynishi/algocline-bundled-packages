--- Tests for critic (rubric-based structured evaluation).
---
--- Coverage (4 cases):
---   1. Happy path — answer provided, single dimension rubric, all pass
---   2. Input validation — ctx.task missing → error
---   3. Single dimension evaluation — score parsed correctly
---   4. avg_score calculation — across multiple dimensions

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

for _, name in ipairs({ "critic", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["critic"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0 }
    local call_idx = 0

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or "SCORE: 8/10\nFEEDBACK: Good."
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

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — answer provided, 1 dimension, score above threshold
-- ═══════════════════════════════════════════════════════════════════

describe("critic.run happy path", function()
    lust.after(reset)

    it("evaluates single dimension and returns structured result", function()
        reset()
        -- 1 evaluation call for single dimension
        local stub, counter = make_alc_stub({
            fixtures = { "SCORE: 9\nFEEDBACK: Excellent answer." },
        })
        _G.alc = stub
        local m = require("critic")
        local ctx = m.run({
            task = "Explain gravity",
            answer = "Gravity is a force...",
            rubric = { "accuracy" },
            threshold = 7,
            max_revisions = 0,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.answer).to_not.equal(nil)
        expect(type(ctx.result.avg_score)).to.equal("number")
        expect(ctx.result.avg_score >= 1).to.equal(true)
        expect(ctx.result.revisions).to.equal(0)
        expect(#ctx.result.history).to.equal(1)
        -- Only evaluation calls (no gen, no revision)
        expect(counter.llm_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("critic.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("critic")
        local ok, err = pcall(m.run, { answer = "some answer" })
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Score parsing — SCORE: 9 pattern parsed correctly
-- ═══════════════════════════════════════════════════════════════════

describe("critic.run score parsing", function()
    lust.after(reset)

    it("parses score from evaluation response", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = { "SCORE: 9\nFEEDBACK: Well done." },
        })
        _G.alc = stub
        local m = require("critic")
        local ctx = m.run({
            task = "Test",
            answer = "Test answer",
            rubric = { "accuracy" },
            max_revisions = 0,
        })
        -- scores map should have "accuracy" key with value 9
        expect(type(ctx.result.scores)).to.equal("table")
        expect(ctx.result.scores["accuracy"]).to.equal(9)
        expect(ctx.result.avg_score).to.equal(9.0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: avg_score across 2 dimensions
-- ═══════════════════════════════════════════════════════════════════

describe("critic.run avg_score aggregation", function()
    lust.after(reset)

    it("averages scores across multiple dimensions correctly", function()
        reset()
        -- 2 dimensions: scores 6 and 8 → avg = 7.0
        local stub, _ = make_alc_stub({
            fixtures = {
                "SCORE: 6\nFEEDBACK: Needs work.",
                "SCORE: 8\nFEEDBACK: Good.",
            },
        })
        _G.alc = stub
        local m = require("critic")
        local ctx = m.run({
            task = "Explain topic",
            answer = "An answer here.",
            rubric = { "accuracy", "clarity" },
            threshold = 9,  -- set high so both fail threshold but max_revisions=0 stops it
            max_revisions = 0,
        })
        local expected_avg = 7.0
        local diff = math.abs(ctx.result.avg_score - expected_avg)
        expect(diff < 1e-9).to.equal(true)
        expect(ctx.result.scores["accuracy"]).to.equal(6)
        expect(ctx.result.scores["clarity"]).to.equal(8)
    end)
end)
