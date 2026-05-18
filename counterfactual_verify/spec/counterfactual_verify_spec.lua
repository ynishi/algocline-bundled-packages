--- Tests for counterfactual_verify (causal faithfulness verification).
---
--- Coverage (5 cases):
---   1. Happy path — n=1, faithful (all match)
---   2. Input validation — ctx.task missing → error
---   3. Unfaithful path — mismatch triggers re-solve (Step 6)
---   4. Judgments use predictions[i] and actuals[i] closures correctly
---   5. counterfactual_results and mismatches structure correct

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

for _, name in ipairs({ "counterfactual_verify", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["counterfactual_verify"] = nil
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

-- CF fixture with proper CHANGE: + MODIFIED PROBLEM: format
local CF_FIXTURE = "CHANGE: The temperature is 100°C instead of 25°C\nMODIFIED PROBLEM: What happens to water at 100°C?"

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — n=1, faithful (MATCH)
-- ═══════════════════════════════════════════════════════════════════

describe("counterfactual_verify.run happy path", function()
    lust.after(reset)

    it("returns faithful=true when counterfactual matches", function()
        reset()
        -- Step 1: solve original (1 llm)
        -- Step 2: generate CFs (1 llm) → 1 CF parsed
        -- Step 3: parallel predictions (1 llm via llm_batch)
        -- Step 4: parallel actuals (1 llm via llm_batch)
        -- Step 5: parallel judgments (1 llm via llm_batch)
        -- Total: 5 llm calls, 3 parallel calls (no Step 6 since faithful)
        local stub, counter = make_alc_stub({
            fixtures = {
                "CoT: Water at 25°C is liquid. Answer: water is liquid.",   -- Step 1: original
                CF_FIXTURE,                                                   -- Step 2: CF generation
                "If temp rises, water would boil. Answer: steam.",           -- Step 3: prediction
                "At 100°C water boils and becomes steam.",                   -- Step 4: actual
                "MATCH\nREASON: Both conclude water becomes steam.",         -- Step 5: judgment
            },
        })
        _G.alc = stub
        local m = require("counterfactual_verify")
        local ctx = m.run({
            task = "What happens to water at 25°C?",
            n_counterfactuals = 1,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.faithful).to.equal(true)
        expect(ctx.result.match_count).to.equal(1)
        expect(ctx.result.total_counterfactuals).to.equal(1)
        expect(#ctx.result.mismatches).to.equal(0)
        expect(#ctx.result.counterfactual_results).to.equal(1)
        expect(counter.llm_calls).to.equal(5)
        expect(counter.parallel_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("counterfactual_verify.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("counterfactual_verify")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Unfaithful path — MISMATCH triggers Step 6 re-solve
-- ═══════════════════════════════════════════════════════════════════

describe("counterfactual_verify.run unfaithful", function()
    lust.after(reset)

    it("sets faithful=false and re-solves when judgment is MISMATCH", function()
        reset()
        -- 5 calls (same as faithful) + 1 re-solve = 6 total
        local stub, counter = make_alc_stub({
            fixtures = {
                "CoT: Original reasoning. Answer: 42.",                          -- Step 1
                CF_FIXTURE,                                                        -- Step 2
                "Predicted: still 42.",                                            -- Step 3 prediction
                "Actual independent: completely different answer 99.",             -- Step 4 actual
                "MISMATCH\nREASON: Predicted 42 but actual is 99.",               -- Step 5 judgment
                "Re-solved with explicit grounding. Answer: 99.",                  -- Step 6 re-solve
            },
        })
        _G.alc = stub
        local m = require("counterfactual_verify")
        local ctx = m.run({
            task = "Calculate something",
            n_counterfactuals = 1,
        })
        expect(ctx.result.faithful).to.equal(false)
        expect(ctx.result.match_count).to.equal(0)
        expect(#ctx.result.mismatches).to.equal(1)
        -- final answer should be the re-solved one
        expect(ctx.result.answer).to.equal("Re-solved with explicit grounding. Answer: 99.")
        expect(counter.llm_calls).to.equal(6)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Judgments closure — predictions[i] and actuals[i] used correctly
-- ═══════════════════════════════════════════════════════════════════

describe("counterfactual_verify.run judgment closure", function()
    lust.after(reset)

    it("counterfactual_results[1] has predicted and actual fields from phases 3+4", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Original CoT answer.",              -- Step 1
                CF_FIXTURE,                           -- Step 2
                "Predicted response text.",           -- Step 3 (prediction)
                "Actual solved response.",            -- Step 4 (actual)
                "MATCH\nREASON: Both agree.",         -- Step 5 judgment
            },
        })
        _G.alc = stub
        local m = require("counterfactual_verify")
        local ctx = m.run({
            task = "Simple question",
            n_counterfactuals = 1,
        })
        local r = ctx.result.counterfactual_results[1]
        expect(r).to_not.equal(nil)
        expect(r.predicted).to.equal("Predicted response text.")
        expect(r.actual).to.equal("Actual solved response.")
        expect(r.match).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: Structure check — original_cot set, total_counterfactuals correct
-- ═══════════════════════════════════════════════════════════════════

describe("counterfactual_verify.run structure", function()
    lust.after(reset)

    it("original_cot equals Step 1 output and total_counterfactuals is set", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "The original reasoning chain.",     -- Step 1
                CF_FIXTURE,                           -- Step 2
                "Prediction.",                        -- Step 3
                "Actual.",                            -- Step 4
                "MATCH\nREASON: Agree.",              -- Step 5
            },
        })
        _G.alc = stub
        local m = require("counterfactual_verify")
        local ctx = m.run({
            task = "Test structure",
            n_counterfactuals = 1,
        })
        expect(ctx.result.original_cot).to.equal("The original reasoning chain.")
        expect(ctx.result.total_counterfactuals).to.equal(1)
        expect(type(ctx.result.answer)).to.equal("string")
    end)
end)
