--- Tests for rank (tournament selection).
---
--- Coverage (4 cases):
---   1. Happy path — 2 candidates, winner determined
---   2. Input validation — ctx.task missing → error
---   3. Single candidate — no tournament, winner is candidate 1
---   4. Sort correctness — "B" wins a match when verdict starts with B

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

for _, name in ipairs({ "rank", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["rank"] = nil
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
        return fixtures[call_idx] or "A wins."
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
-- Case 1: Happy path — 2 candidates, A wins
-- ═══════════════════════════════════════════════════════════════════

describe("rank.run happy path", function()
    lust.after(reset)

    it("selects winner from 2 candidates", function()
        reset()
        -- 2 generation calls (parallel) + 1 compare call = 3 total
        local stub, counter = make_alc_stub({
            fixtures = {
                "Candidate 1 answer",   -- gen 1
                "Candidate 2 answer",   -- gen 2
                "A is better.",         -- compare: A wins
            },
        })
        _G.alc = stub
        local m = require("rank")
        local ctx = m.run({ task = "What is 2+2?", candidates = 2 })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.best).to_not.equal(nil)
        expect(type(ctx.result.best_index)).to.equal("number")
        expect(ctx.result.best_index >= 1).to.equal(true)
        expect(#ctx.result.candidates).to.equal(2)
        -- 1 compare call for 2 candidates
        expect(#ctx.result.matches).to.equal(1)
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("rank.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("rank")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Single candidate — no tournament needed
-- ═══════════════════════════════════════════════════════════════════

describe("rank.run single candidate", function()
    lust.after(reset)

    it("returns candidate 1 as winner when candidates=1", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = { "Only candidate" },  -- 1 gen call
        })
        _G.alc = stub
        local m = require("rank")
        local ctx = m.run({ task = "Simple task", candidates = 1 })
        expect(ctx.result.best_index).to.equal(1)
        expect(#ctx.result.candidates).to.equal(1)
        -- No compare calls (only 1 candidate — odd gets a bye)
        expect(#ctx.result.matches).to.equal(0)
        expect(counter.llm_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Sort correctness — B wins when verdict says "B"
-- ═══════════════════════════════════════════════════════════════════

describe("rank.run sort correctness", function()
    lust.after(reset)

    it("selects B as winner when compare verdict says B", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Candidate 1 text",   -- gen 1
                "Candidate 2 text",   -- gen 2
                "B is better.",       -- compare: B wins (starts with B)
            },
        })
        _G.alc = stub
        local m = require("rank")
        local ctx = m.run({ task = "Evaluate", candidates = 2 })
        -- B wins means candidate index 2 is best
        expect(ctx.result.best_index).to.equal(2)
    end)
end)
