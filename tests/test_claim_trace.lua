--- Tests for claim_trace (span-level evidence attribution).
---
--- Coverage (4 cases):
---   1. Happy path — answer provided, 2 claims extracted, both supported
---   2. Input validation — ctx.task missing → error
---   3. Empty claims — extraction yields nothing → early return (total=0)
---   4. Attribution score calculation — supported + partial mix

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

for _, name in ipairs({ "claim_trace", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["claim_trace"] = nil
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
-- Case 1: Happy path — answer provided, 2 claims, both supported
-- ═══════════════════════════════════════════════════════════════════

describe("claim_trace.run happy path", function()
    lust.after(reset)

    it("attributes 2 claims from a provided answer", function()
        reset()
        -- fixtures: [1] extraction "1. Claim A\n2. Claim B", [2] attr for claim 1, [3] attr for claim 2
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. Claim A is true.\n2. Claim B is also true.",  -- extraction
                'ATTRIBUTION: SUPPORTED\nSPAN: "evidence A"\nREASONING: it is clear',
                'ATTRIBUTION: SUPPORTED\nSPAN: "evidence B"\nREASONING: it is clear',
            },
        })
        _G.alc = stub
        local m = require("claim_trace")
        local ctx = m.run({
            task = "Describe the topic",
            answer = "Claim A is true. Claim B is also true.",
            sources = "Evidence A is here. Evidence B is here.",
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.total).to.equal(2)
        expect(ctx.result.supported).to.equal(2)
        expect(ctx.result.attribution_score).to.equal(1.0)
        -- extraction (1) + 2 attribution calls = 3 llm calls total
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("claim_trace.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("claim_trace")
        local ok, err = pcall(m.run, { sources = "some source" })
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Empty claims — extraction returns nothing → early return
-- ═══════════════════════════════════════════════════════════════════

describe("claim_trace.run empty claims", function()
    lust.after(reset)

    it("returns empty claims when extraction yields nothing", function()
        reset()
        -- extraction returns no numbered lines
        local stub, counter = make_alc_stub({
            fixtures = { "No claims here." },  -- extraction returns no numbered list
        })
        _G.alc = stub
        local m = require("claim_trace")
        local ctx = m.run({
            task = "What happened?",
            answer = "Nothing to report.",
            sources = "Some source text.",
        })
        expect(ctx.result.total).to.equal(0)
        expect(ctx.result.attribution_score).to.equal(1.0)
        expect(#ctx.result.claims).to.equal(0)
        -- Only 1 LLM call (extraction), no attribution calls
        expect(counter.llm_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Attribution score calculation — 1 supported + 1 partial
-- ═══════════════════════════════════════════════════════════════════

describe("claim_trace.run attribution score", function()
    lust.after(reset)

    it("calculates attribution_score correctly with 1 supported + 1 partial", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "1. First claim.\n2. Second claim.",     -- extraction
                'ATTRIBUTION: SUPPORTED\nSPAN: "span1"\nREASONING: clear',
                'ATTRIBUTION: PARTIAL\nSPAN: "partial span"\nREASONING: partly',
            },
        })
        _G.alc = stub
        local m = require("claim_trace")
        local ctx = m.run({
            task = "Evaluate",
            answer = "First claim. Second claim.",
            sources = "Some reference.",
        })
        -- attribution_score = (1 + 0.5) / 2 = 0.75
        local expected = 0.75
        local diff = math.abs(ctx.result.attribution_score - expected)
        expect(diff < 1e-9).to.equal(true)
        expect(ctx.result.supported).to.equal(1)
        expect(ctx.result.partial).to.equal(1)
        expect(ctx.result.total).to.equal(2)
    end)
end)
