--- Tests for anti_cascade (pipeline error cascade detection).
---
--- Coverage (5 cases):
---   1. Happy path — 2 steps, no drift flagged
---   2. Input validation — ctx.task missing → error
---   3. Input validation — ctx.steps empty → error
---   4. Phase 2 detects divergence — drift_score >= threshold → step flagged
---   5. Phase boundary correctness — step_results count equals #steps

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

for _, name in ipairs({ "anti_cascade", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["anti_cascade"] = nil
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
-- Case 1: Happy path — 2 steps, no drift flagged
-- ═══════════════════════════════════════════════════════════════════

describe("anti_cascade.run happy path", function()
    lust.after(reset)

    it("returns step_results with no flagged steps when drift is low", function()
        reset()
        -- Phase 1: parallel(2 steps) → 2 rederive calls
        -- Phase 2: parallel(2 compare items) → 2 compare calls
        -- Summary: 1 llm call
        -- Total: 5 llm calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Independent rederivation of step A.",   -- rederive step 1
                "Independent rederivation of step B.",   -- rederive step 2
                "DRIFT_SCORE: 0.1\nDRIFT_TYPE: NONE\nCASCADE_RISK: LOW",   -- compare step 1
                "DRIFT_SCORE: 0.1\nDRIFT_TYPE: NONE\nCASCADE_RISK: LOW",   -- compare step 2
                "## Cascade Analysis Summary\nPipeline is healthy.",         -- summary
            },
        })
        _G.alc = stub
        local m = require("anti_cascade")
        local ctx = m.run({
            task = "Summarize the document",
            steps = {
                { name = "extract", instruction = "extract key facts", output = "Fact A, Fact B" },
                { name = "summarize", instruction = "create summary", output = "The document covers A and B." },
            },
        })
        expect(ctx.result).to_not.equal(nil)
        expect(#ctx.result.step_results).to.equal(2)
        expect(#ctx.result.flagged_steps).to.equal(0)
        expect(ctx.result.max_drift).to.equal(0.1)
        expect(type(ctx.result.summary)).to.equal("string")
        expect(counter.llm_calls).to.equal(5)
        expect(counter.parallel_calls).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("anti_cascade.run input validation task", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("anti_cascade")
        local ok, err = pcall(m.run, {
            steps = { { name = "s1", output = "out" } },
        })
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Input validation — ctx.steps empty → error
-- ═══════════════════════════════════════════════════════════════════

describe("anti_cascade.run input validation steps", function()
    lust.after(reset)

    it("errors when ctx.steps is empty", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("anti_cascade")
        local ok, err = pcall(m.run, {
            task = "Some task",
            steps = {},
        })
        expect(ok).to.equal(false)
        expect(err:find("step") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Phase 2 detects divergence — drift_score >= threshold → flagged
-- ═══════════════════════════════════════════════════════════════════

describe("anti_cascade.run drift detection", function()
    lust.after(reset)

    it("flags step when drift_score meets threshold (default 0.4)", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Independent output for step X.",        -- rederive step 1
                "DRIFT_SCORE: 0.7\nDRIFT_TYPE: FACTUAL_DIVERGENCE\nCASCADE_RISK: HIGH",  -- compare step 1
                "## Cascade Analysis Summary\nStep X flagged.",  -- summary
            },
        })
        _G.alc = stub
        local m = require("anti_cascade")
        local ctx = m.run({
            task = "Analyze the data",
            steps = {
                { name = "step_x", instruction = "analyze", output = "Completely different analysis." },
            },
        })
        expect(#ctx.result.flagged_steps).to.equal(1)
        expect(ctx.result.flagged_steps[1]).to.equal("step_x")
        expect(ctx.result.max_drift).to.equal(0.7)
        expect(ctx.result.step_results[1].flagged).to.equal(true)
        expect(ctx.result.step_results[1].drift_type).to.equal("FACTUAL_DIVERGENCE")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: Phase boundary correctness — step_results count equals #steps
-- ═══════════════════════════════════════════════════════════════════

describe("anti_cascade.run phase boundary", function()
    lust.after(reset)

    it("step_results length equals number of input steps", function()
        reset()
        -- 3 steps: Phase1 parallel(3) + Phase2 parallel(3) + summary(1) = 7 calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Rederive A.",                                               -- rederive 1
                "Rederive B.",                                               -- rederive 2
                "Rederive C.",                                               -- rederive 3
                "DRIFT_SCORE: 0.1\nDRIFT_TYPE: NONE\nCASCADE_RISK: LOW",    -- compare 1
                "DRIFT_SCORE: 0.2\nDRIFT_TYPE: MINOR_REFINEMENT\nCASCADE_RISK: LOW",  -- compare 2
                "DRIFT_SCORE: 0.3\nDRIFT_TYPE: ADDED_DETAIL\nCASCADE_RISK: MEDIUM",  -- compare 3
                "## Cascade Analysis Summary\nAll steps within acceptable range.",    -- summary
            },
        })
        _G.alc = stub
        local m = require("anti_cascade")
        local ctx = m.run({
            task = "Process data",
            steps = {
                { name = "step_a", output = "Output A" },
                { name = "step_b", output = "Output B" },
                { name = "step_c", output = "Output C" },
            },
        })
        expect(#ctx.result.step_results).to.equal(3)
        expect(ctx.result.max_drift).to.equal(0.3)
        -- No steps flagged (all below default threshold 0.4)
        expect(#ctx.result.flagged_steps).to.equal(0)
        expect(counter.llm_calls).to.equal(7)
    end)
end)
