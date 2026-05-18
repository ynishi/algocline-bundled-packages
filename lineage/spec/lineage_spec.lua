--- Tests for lineage (pipeline-spanning claim lineage tracking).
---
--- Coverage (5 cases):
---   1. Happy path — 2 steps, extract + trace + analysis
---   2. Input validation — ctx.task missing → error
---   3. Input validation — ctx.steps < 2 → error
---   4. Phase boundary — traces count equals #steps - 1
---   5. Integrity score parsed from analysis output

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

for _, name in ipairs({ "lineage", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["lineage"] = nil
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

    stub.stats = { record = function(_key, _val) end }

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — 2 steps, extract + trace + analysis
-- ═══════════════════════════════════════════════════════════════════

describe("lineage.run happy path", function()
    lust.after(reset)

    it("returns step_claims, traces, and analysis for 2 steps", function()
        reset()
        -- Phase 1: parallel(2 steps, post_fn) → 2 llm calls
        -- Phase 2: parallel(1 pair, post_fn) → 1 llm call
        -- Phase 4: 1 llm call
        -- Total: 4 llm calls
        local stub, counter = make_alc_stub({
            fixtures = {
                -- Phase 1: extract claims from step 1 (plan)
                "1. The system should process data.\n2. Input format is JSON.",
                -- Phase 1: extract claims from step 2 (implement)
                "1. Data processing is implemented.\n2. JSON parser is included.",
                -- Phase 2: trace step1 → step2
                "CLAIM 1: Data processing is implemented.\nDERIVES_FROM: 1\nTRANSFORMATION: PRESERVED\nCLAIM 2: JSON parser is included.\nDERIVES_FROM: 2\nTRANSFORMATION: REFINED",
                -- Phase 4: conflict analysis
                "## Conflicts\nNone detected\n## Integrity Score\nSCORE: 0.9",
            },
        })
        _G.alc = stub
        local m = require("lineage")
        local ctx = m.run({
            task = "Build a data pipeline",
            steps = {
                { name = "plan",      output = "The system should process data in JSON format." },
                { name = "implement", output = "Data processing implemented with JSON parser." },
            },
        })
        expect(ctx.result).to_not.equal(nil)
        expect(#ctx.result.step_claims).to.equal(2)
        expect(#ctx.result.traces).to.equal(1)
        expect(type(ctx.result.lineage_graph)).to.equal("string")
        expect(type(ctx.result.analysis)).to.equal("string")
        expect(counter.llm_calls).to.equal(4)
        expect(counter.parallel_calls).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("lineage.run input validation task", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("lineage")
        local ok, err = pcall(m.run, {
            steps = {
                { name = "s1", output = "out1" },
                { name = "s2", output = "out2" },
            },
        })
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Input validation — ctx.steps < 2 → error
-- ═══════════════════════════════════════════════════════════════════

describe("lineage.run input validation steps", function()
    lust.after(reset)

    it("errors when ctx.steps has fewer than 2 entries", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("lineage")
        local ok, err = pcall(m.run, {
            task = "Some task",
            steps = { { name = "only", output = "single step" } },
        })
        expect(ok).to.equal(false)
        expect(err:find("2") ~= nil or err:find("step") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Phase boundary — traces count equals #steps - 1
-- ═══════════════════════════════════════════════════════════════════

describe("lineage.run phase boundary", function()
    lust.after(reset)

    it("produces (N-1) traces for N steps", function()
        reset()
        -- 3 steps: Phase1(3) + Phase2(2 pairs) + analysis(1) = 6 calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. Claim from step A.",         -- extract step A
                "1. Claim from step B.",         -- extract step B
                "1. Claim from step C.",         -- extract step C
                "CLAIM 1: From B.\nDERIVES_FROM: 1\nTRANSFORMATION: PRESERVED",  -- trace A→B
                "CLAIM 1: From C.\nDERIVES_FROM: 1\nTRANSFORMATION: REFINED",    -- trace B→C
                "## Conflicts\nNone detected\n## Integrity Score\nSCORE: 0.95",   -- analysis
            },
        })
        _G.alc = stub
        local m = require("lineage")
        local ctx = m.run({
            task = "Multi-step pipeline",
            steps = {
                { name = "step_a", output = "Output A" },
                { name = "step_b", output = "Output B" },
                { name = "step_c", output = "Output C" },
            },
        })
        -- 3 steps → 2 traces
        expect(#ctx.result.traces).to.equal(2)
        expect(#ctx.result.step_claims).to.equal(3)
        expect(ctx.result.traces[1].from_step).to.equal("step_a")
        expect(ctx.result.traces[1].to_step).to.equal("step_b")
        expect(ctx.result.traces[2].from_step).to.equal("step_b")
        expect(ctx.result.traces[2].to_step).to.equal("step_c")
        expect(counter.llm_calls).to.equal(6)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: Integrity score parsed from analysis output
-- ═══════════════════════════════════════════════════════════════════

describe("lineage.run integrity score", function()
    lust.after(reset)

    it("parses integrity_score from SCORE: field in analysis", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "1. Fact one.\n2. Fact two.",     -- extract step 1
                "1. Derived fact.",               -- extract step 2
                "CLAIM 1: Derived.\nDERIVES_FROM: 1\nTRANSFORMATION: INFERRED",  -- trace
                "## Conflicts\nNone detected\n## Integrity Score\nSCORE: 0.85",   -- analysis
            },
        })
        _G.alc = stub
        local m = require("lineage")
        local ctx = m.run({
            task = "Verify claims",
            steps = {
                { name = "source", output = "Fact one. Fact two." },
                { name = "result", output = "A derived fact." },
            },
        })
        expect(ctx.result.integrity_score).to_not.equal(nil)
        expect(ctx.result.integrity_score).to.equal(0.85)
    end)
end)
