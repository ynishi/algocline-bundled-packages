--- Tests for coa (Chain-of-Abstraction reasoning).
---
--- Coverage (5 cases):
---   1. Happy path — 1 placeholder → resolved in 1 parallel call
---   2. Input validation — ctx.task missing → error
---   3. No placeholders in chain → grounding loop exits, answer produced
---   4. Topological dependency — y2 depends on y1 → resolved in 2 depth passes
---   5. result structure — abstract_chain / grounded_chain / groundings correct

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

for _, name in ipairs({ "coa", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["coa"] = nil
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

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — 1 placeholder resolved in depth 1
-- ═══════════════════════════════════════════════════════════════════

describe("coa.run happy path", function()
    lust.after(reset)

    it("resolves 1 placeholder and produces final answer", function()
        reset()
        -- Step 1: abstract chain (1 llm) with 1 placeholder
        -- Step 2: depth 1: parallel(1 independent ph) → 1 llm call
        -- Step 3: final answer (1 llm)
        -- Total: 3 llm calls, 1 parallel call
        local stub, counter = make_alc_stub({
            fixtures = {
                -- Step 1: abstract chain with 1 placeholder
                'The capital city is [FUNC knowledge("capital of France") = y1]. France is in Europe.',
                -- Step 2: grounding y1
                "Paris",
                -- Step 3: final answer
                "The capital of France is Paris, located in Europe.",
            },
        })
        _G.alc = stub
        local m = require("coa")
        local ctx = m.run({
            task = "What is the capital of France?",
        })
        expect(ctx.result).to_not.equal(nil)
        expect(type(ctx.result.answer)).to.equal("string")
        expect(type(ctx.result.abstract_chain)).to.equal("string")
        expect(type(ctx.result.grounded_chain)).to.equal("string")
        expect(ctx.result.placeholders_resolved).to.equal(1)
        expect(#ctx.result.groundings).to.equal(1)
        expect(ctx.result.groundings[1].var).to.equal("y1")
        expect(counter.llm_calls).to.equal(3)
        expect(counter.parallel_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("coa.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("coa")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: No placeholders — grounding skipped, answer still produced
-- ═══════════════════════════════════════════════════════════════════

describe("coa.run no placeholders", function()
    lust.after(reset)

    it("produces answer with 0 groundings when no placeholders in chain", function()
        reset()
        -- Step 1: abstract chain with no placeholders
        -- Step 2: depth 1 finds 0 unresolved → exits immediately
        -- Step 3: final answer
        -- Total: 2 llm calls, 0 parallel calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "The answer is 42 because 6 times 7 equals 42.",  -- Step 1: no placeholders
                "The answer is 42.",                               -- Step 3: final answer
            },
        })
        _G.alc = stub
        local m = require("coa")
        local ctx = m.run({ task = "What is 6 × 7?" })
        expect(ctx.result.placeholders_resolved).to.equal(0)
        expect(#ctx.result.groundings).to.equal(0)
        expect(type(ctx.result.answer)).to.equal("string")
        expect(counter.llm_calls).to.equal(2)
        expect(counter.parallel_calls).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Topological dependency — y2 depends on y1 → 2 depth passes
-- ═══════════════════════════════════════════════════════════════════

describe("coa.run topological dependency", function()
    lust.after(reset)

    it("resolves y1 then y2(y1) in two depth passes", function()
        reset()
        -- Step 1: chain with y1 (independent) and y2 that references y1 in query
        -- Step 2 depth 1: parallel(y1) → 1 llm call
        -- Step 2 depth 2: parallel(y2) → 1 llm call
        -- Step 3: final answer → 1 llm call
        -- Total: 4 llm calls, 2 parallel calls
        local stub, counter = make_alc_stub({
            fixtures = {
                -- Step 1: abstract chain with y1 (independent) and y2 (depends on y1)
                '[FUNC knowledge("longest river in world") = y1] is the longest river.\n'
                .. '[FUNC knowledge("length of y1") = y2] km long.',
                -- Step 2 depth 1: resolve y1
                "The Nile",
                -- Step 2 depth 2: resolve y2 (query becomes "length of The Nile" after y1 substitution)
                "6650",
                -- Step 3: final answer
                "The Nile is the longest river at 6650 km.",
            },
        })
        _G.alc = stub
        local m = require("coa")
        local ctx = m.run({
            task = "What is the longest river and how long is it?",
            max_depth = 3,
        })
        expect(ctx.result.placeholders_resolved).to.equal(2)
        expect(#ctx.result.groundings).to.equal(2)
        -- depth of first grounding (y1) should be 1
        expect(ctx.result.groundings[1].depth).to.equal(1)
        -- depth of second grounding (y2) should be 2
        expect(ctx.result.groundings[2].depth).to.equal(2)
        expect(counter.llm_calls).to.equal(4)
        expect(counter.parallel_calls).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: result structure — all fields present and correct types
-- ═══════════════════════════════════════════════════════════════════

describe("coa.run result structure", function()
    lust.after(reset)

    it("result has abstract_chain, grounded_chain, groundings, tools_used", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                'Abstract chain with [FUNC knowledge("GDP of Japan") = y1].',
                "4.2 trillion USD",
                "Japan's GDP is 4.2 trillion USD.",
            },
        })
        _G.alc = stub
        local m = require("coa")
        local ctx = m.run({
            task = "What is Japan's GDP?",
            tools = { knowledge = "factual knowledge lookup" },
        })
        expect(type(ctx.result.abstract_chain)).to.equal("string")
        expect(type(ctx.result.grounded_chain)).to.equal("string")
        expect(type(ctx.result.groundings)).to.equal("table")
        expect(type(ctx.result.tools_used)).to.equal("table")
        expect(ctx.result.tools_used.knowledge).to_not.equal(nil)
        -- grounded_chain should contain resolved value
        expect(ctx.result.grounded_chain:find("4.2 trillion USD") ~= nil).to.equal(true)
    end)
end)
