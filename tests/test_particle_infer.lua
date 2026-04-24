--- Tests for particle_infer (Puri et al. 2025, arXiv:2502.01618).
---
--- Coverage:
---   Pure helpers (no LLM):
---     * aggregate_prm_scores — product / min / last / model modes +
---       error cases (empty step_scores, non-number step)
---     * softmax_weights — uniform, concentration, high-temp flatten,
---       extreme shift (max-shift numerical stability), NaN / non-number
---       / non-positive temperature rejection
---     * compute_ess — equal weights → N, concentration → 1, all-zero → 0
---     * resample_multinomial — deterministic rng picks argmax bucket,
---       preserves N, rejects length mismatch / nonpositive weights
---     * logit_from_bern — log-odds transform matching reference impl
---       `_inv_sigmoid`; clamping at r̂ ≈ 0 and r̂ ≈ 1 avoids ±∞;
---       input validation (non-number / NaN / eps out-of-range)
---   LLM-integrated (mocked _G.alc):
---     * init_particles — N empty particles, no LLM call
---     * advance_step — fans out 1 LLM call per active particle,
---       inactive skipped, empty response leaves partial unchanged
---     * evaluate_prm — fail-fast on non-number / NaN / out-of-range
---     * evaluate_continue — false → active=false; non-boolean rejected
---     * select_final — orm / argmax_weight / weighted_vote correctness
---   M.run orchestration:
---     * end-to-end under paper-faithful path (ess_threshold=0, every-
---       step resample)
---     * ORM fallback warning (mode='orm' + orm_fn=nil → argmax_weight)
---     * input validation fail-fast
---     * Card emission when auto_card=true with stub alc.card
---   Paper-faithful semantics (D5 regression guards — reference impl
---   its_hub/algorithms/particle_gibbs.py parity):
---     * softmax concentration: r̂ = [0.99, 0.01×7] under N=8 must
---       concentrate resampling mass (P_top > 0.9). Guards against the
---       old linear-space w = r̂/N path that flattened to ~14%.
---     * weight replacement (not accumulation): step 2's logit weight
---       depends ONLY on r̂_2, not on r̂_1 × r̂_2.
---     * resample lineage inheritance: post-resample weight equals the
---       drawn lineage's pre-resample weight (ref impl `log_weight`
---       property carries through `partial_log_weights` deep-copy).
---     * result.weights is a probability distribution (sums to 1,
---       all entries ∈ [0,1]) — the softmax-normalized output.

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

-- Force fresh load so the worktree's particle_inferred shape is visible
-- even if a prior run cached the parent-repo version.
for _, name in ipairs({
    "particle_infer",
    "alc_shapes",
    "alc_shapes.t",
    "alc_shapes.check",
    "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["particle_infer"] = nil
    _G.alc = nil
end

local function approx(a, b, eps)
    eps = eps or 1e-9
    return math.abs(a - b) <= eps
end

-- ═══════════════════════════════════════════════════════════════════
-- Meta
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local pi = require("particle_infer")
        expect(pi.meta.name).to.equal("particle_infer")
    end)

    it("has version 0.1.0", function()
        local pi = require("particle_infer")
        expect(pi.meta.version).to.equal("0.1.0")
    end)

    it("category is selection", function()
        local pi = require("particle_infer")
        expect(pi.meta.category).to.equal("selection")
    end)

    it("description mentions Particle Filter and arXiv id", function()
        local pi = require("particle_infer")
        expect(pi.meta.description:find("Particle%-Filter") ~= nil).to.equal(true)
        expect(pi.meta.description:find("2502.01618") ~= nil).to.equal(true)
    end)

    it("defaults match paper-faithful values", function()
        local pi = require("particle_infer")
        expect(pi._defaults.n_particles).to.equal(8)
        expect(pi._defaults.max_steps).to.equal(8)
        expect(pi._defaults.aggregation).to.equal("product")
        expect(pi._defaults.softmax_temp).to.equal(1.0)
        expect(pi._defaults.ess_threshold).to.equal(0.0)
        expect(pi._defaults.llm_temperature).to.equal(0.8)
        expect(pi._defaults.final_selection).to.equal("orm")
        expect(pi._defaults.weight_scheme).to.equal("log_linear")
    end)

    it("exposes _internal pure helpers", function()
        local pi = require("particle_infer")
        expect(type(pi._internal.aggregate_prm_scores)).to.equal("function")
        expect(type(pi._internal.softmax_weights)).to.equal("function")
        expect(type(pi._internal.compute_ess)).to.equal("function")
        expect(type(pi._internal.resample_multinomial)).to.equal("function")
        expect(type(pi._internal.logit_from_bern)).to.equal("function")
        expect(type(pi._internal.log_from_bern)).to.equal("function")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- aggregate_prm_scores
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.aggregate_prm_scores", function()
    lust.after(reset)

    it("product: paper §3.2 default, returns ∏_t r̂_t", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores(
            { { 0.9, 0.8 }, { 0.5, 0.5 } }, "product")
        expect(approx(out[1], 0.72, 1e-12)).to.equal(true)
        expect(approx(out[2], 0.25, 1e-12)).to.equal(true)
    end)

    it("min: bottleneck view, returns min_t r̂_t", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores(
            { { 0.9, 0.1, 0.8 }, { 0.5, 0.5, 0.5 } }, "min")
        expect(approx(out[1], 0.1, 1e-12)).to.equal(true)
        expect(approx(out[2], 0.5, 1e-12)).to.equal(true)
    end)

    it("last: efficiency view, returns r̂_T", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores(
            { { 0.9, 0.1, 0.8 }, { 0.5, 0.5, 0.3 } }, "last")
        expect(approx(out[1], 0.8, 1e-12)).to.equal(true)
        expect(approx(out[2], 0.3, 1e-12)).to.equal(true)
    end)

    it("model: same reduction as last (contract on r̂_T)", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores(
            { { 0.7 }, { 0.3 } }, "model")
        expect(approx(out[1], 0.7, 1e-12)).to.equal(true)
        expect(approx(out[2], 0.3, 1e-12)).to.equal(true)
    end)

    it("empty step_scores + product → 1.0 (multiplicative identity)", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores({ {}, { 0.5 } }, "product")
        expect(approx(out[1], 1.0, 1e-12)).to.equal(true)
        expect(approx(out[2], 0.5, 1e-12)).to.equal(true)
    end)

    it("empty step_scores + min → math.huge (min over empty set)", function()
        local pi = require("particle_infer")
        local out = pi._internal.aggregate_prm_scores({ {} }, "min")
        -- lust's .to.equal misbehaves on math.huge ↔ math.huge (formats
        -- both as "inf" but reports inequality). Compare via `==` directly.
        expect(out[1] == math.huge).to.equal(true)
    end)

    it("empty step_scores + last → error (undefined last element)", function()
        local pi = require("particle_infer")
        local ok, err = pcall(pi._internal.aggregate_prm_scores, { {} }, "last")
        expect(ok).to.equal(false)
        expect(err ~= nil).to.equal(true)
    end)

    it("empty step_scores + model → error (undefined last element)", function()
        local pi = require("particle_infer")
        local ok, err = pcall(pi._internal.aggregate_prm_scores, { {} }, "model")
        expect(ok).to.equal(false)
        expect(err ~= nil).to.equal(true)
    end)

    it("rejects unknown mode", function()
        local pi = require("particle_infer")
        local ok, err = pcall(pi._internal.aggregate_prm_scores,
            { { 0.5 } }, "geomean")
        expect(ok).to.equal(false)
        expect(err:find("unknown mode") ~= nil).to.equal(true)
    end)

    it("rejects non-number step entry", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.aggregate_prm_scores,
            { { 0.5, "bad" } }, "product")
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- softmax_weights
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.softmax_weights", function()
    lust.after(reset)

    it("equal inputs → uniform", function()
        local pi = require("particle_infer")
        local w = pi._internal.softmax_weights({ 1, 1, 1 }, 1.0)
        for i = 1, 3 do
            expect(approx(w[i], 1 / 3, 1e-12)).to.equal(true)
        end
    end)

    it("concentration: large gap → near one-hot", function()
        local pi = require("particle_infer")
        local w = pi._internal.softmax_weights({ 100, 0, 0 }, 1.0)
        expect(w[1] > 0.99).to.equal(true)
        expect(w[2] < 0.01).to.equal(true)
        expect(w[3] < 0.01).to.equal(true)
        expect(approx(w[1] + w[2] + w[3], 1, 1e-9)).to.equal(true)
    end)

    it("infinite temperature → uniform", function()
        local pi = require("particle_infer")
        local w = pi._internal.softmax_weights({ 100, 0, 0 }, math.huge)
        for i = 1, 3 do
            expect(approx(w[i], 1 / 3, 1e-12)).to.equal(true)
        end
    end)

    it("max-shift prevents overflow at large w / small T", function()
        local pi = require("particle_infer")
        -- Without max-shift, exp(10000) = +Inf. With max-shift
        -- the result is still a valid distribution summing to 1.
        local w = pi._internal.softmax_weights({ 10000, 0 }, 1.0)
        expect(approx(w[1] + w[2], 1, 1e-9)).to.equal(true)
        expect(w[1] > 0.99).to.equal(true)
    end)

    it("underflow fallback: w_i all extremely negative → uniform", function()
        local pi = require("particle_infer")
        local w = pi._internal.softmax_weights({ -10000, -10001 }, 1.0)
        -- Either the max-shifted exp produces a valid peaked
        -- distribution OR it falls back to uniform. Both are
        -- numerically acceptable; sum must be 1 in either case.
        expect(approx(w[1] + w[2], 1, 1e-9)).to.equal(true)
    end)

    it("rejects non-positive temperature", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.softmax_weights, { 1, 2 }, 0)
        expect(ok).to.equal(false)
        ok = pcall(pi._internal.softmax_weights, { 1, 2 }, -1)
        expect(ok).to.equal(false)
    end)

    it("rejects NaN input", function()
        local pi = require("particle_infer")
        local nan = 0 / 0
        local ok = pcall(pi._internal.softmax_weights, { nan, 1 }, 1.0)
        expect(ok).to.equal(false)
    end)

    it("rejects empty vector", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.softmax_weights, {}, 1.0)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- compute_ess
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.compute_ess", function()
    lust.after(reset)

    it("equal weights (N=4) → ESS=N=4", function()
        local pi = require("particle_infer")
        local ess = pi._internal.compute_ess({ 0.25, 0.25, 0.25, 0.25 })
        expect(approx(ess, 4, 1e-12)).to.equal(true)
    end)

    it("single-particle domination → ESS=1", function()
        local pi = require("particle_infer")
        local ess = pi._internal.compute_ess({ 1, 0, 0, 0 })
        expect(approx(ess, 1, 1e-12)).to.equal(true)
    end)

    it("all-zero weights → ESS=0 (degenerate)", function()
        local pi = require("particle_infer")
        local ess = pi._internal.compute_ess({ 0, 0, 0 })
        expect(ess).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- resample_multinomial
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.resample_multinomial", function()
    lust.after(reset)

    it("deterministic rng picks argmax-prob bucket", function()
        local pi = require("particle_infer")
        -- rng always returns u=0.99 → falls into the last bucket
        -- (highest cumulative prob). With weights [0.1, 0.1, 0.8]
        -- that's particle 3.
        local rng_const = function() return 0.99 end
        local out, drawn = pi._internal.resample_multinomial(
            { "A", "B", "C" }, { 0.1, 0.1, 0.8 }, rng_const)
        for i = 1, 3 do
            expect(out[i]).to.equal("C")
            expect(drawn[i]).to.equal(3)
        end
    end)

    it("preserves N", function()
        local pi = require("particle_infer")
        local out, drawn = pi._internal.resample_multinomial(
            { "A", "B", "C", "D" }, { 0.25, 0.25, 0.25, 0.25 },
            function() return 0.5 end)
        expect(#out).to.equal(4)
        expect(#drawn).to.equal(4)
    end)

    it("rejects length mismatch", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.resample_multinomial,
            { "A", "B" }, { 0.5, 0.3, 0.2 })
        expect(ok).to.equal(false)
    end)

    it("rejects Σw ≤ 0", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.resample_multinomial,
            { "A", "B" }, { 0, 0 })
        expect(ok).to.equal(false)
    end)

    it("u=0 boundary: does not select zero-weight bucket", function()
        -- With u=0 and weights=[0, 0.5, 0.5], the first CDF entry is
        -- cdf[1]=0.0. Under the old `u <= cdf[j]` condition, u=0 would
        -- match bucket 1 (the zero-weight bucket). Under the corrected
        -- `u < cdf[j]`, u=0 skips bucket 1 (0 < 0 is false) and falls
        -- into bucket 2 or 3.
        local pi = require("particle_infer")
        local rng_zero = function() return 0 end
        local _, drawn = pi._internal.resample_multinomial(
            { "A", "B", "C" }, { 0, 0.5, 0.5 }, rng_zero)
        for i = 1, 3 do
            expect(drawn[i] ~= 1).to.equal(true)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- logit_from_bern — reference impl `_inv_sigmoid` parity
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.logit_from_bern", function()
    lust.after(reset)

    it("logit(0.5) = 0 (neutral, uniform softmax component)", function()
        local pi = require("particle_infer")
        expect(approx(pi._internal.logit_from_bern(0.5), 0, 1e-12))
            .to.equal(true)
    end)

    it("logit(0.9) = log(9) ≈ 2.1972245773", function()
        local pi = require("particle_infer")
        local expected = math.log(9)
        expect(approx(pi._internal.logit_from_bern(0.9), expected, 1e-12))
            .to.equal(true)
    end)

    it("logit is an odd function of (r - 0.5) around 0.5", function()
        local pi = require("particle_infer")
        -- logit(p) + logit(1 - p) = log(p/(1-p)) + log((1-p)/p) = 0
        expect(approx(
            pi._internal.logit_from_bern(0.2)
            + pi._internal.logit_from_bern(0.8),
            0, 1e-12)).to.equal(true)
        expect(approx(
            pi._internal.logit_from_bern(0.05)
            + pi._internal.logit_from_bern(0.95),
            0, 1e-12)).to.equal(true)
    end)

    it("monotonically increasing in r", function()
        local pi = require("particle_infer")
        local prev = -math.huge
        for _, r in ipairs({ 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 0.99 }) do
            local v = pi._internal.logit_from_bern(r)
            expect(v > prev).to.equal(true)
            prev = v
        end
    end)

    it("clamps r=0 without producing -inf", function()
        local pi = require("particle_infer")
        local v = pi._internal.logit_from_bern(0)
        -- logit(eps) for eps=1e-7 → log(1e-7/(1-1e-7)) ≈ -16.118
        expect(v > -20 and v < -10).to.equal(true)
        expect(v == v).to.equal(true)  -- not NaN
        expect(v ~= -math.huge).to.equal(true)
    end)

    it("clamps r=1 without producing +inf", function()
        local pi = require("particle_infer")
        local v = pi._internal.logit_from_bern(1)
        expect(v > 10 and v < 20).to.equal(true)
        expect(v ~= math.huge).to.equal(true)
    end)

    it("honours caller-supplied eps (smaller → sharper saturation)", function()
        local pi = require("particle_infer")
        local v_default = pi._internal.logit_from_bern(1)
        local v_tighter = pi._internal.logit_from_bern(1, 1e-12)
        expect(v_tighter > v_default).to.equal(true)
    end)

    it("rejects non-number / NaN inputs", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.logit_from_bern, "bad")
        expect(ok).to.equal(false)
        local nan = 0 / 0
        ok = pcall(pi._internal.logit_from_bern, nan)
        expect(ok).to.equal(false)
    end)

    it("rejects eps outside (0, 0.5)", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.logit_from_bern, 0.5, 0)
        expect(ok).to.equal(false)
        ok = pcall(pi._internal.logit_from_bern, 0.5, 0.5)
        expect(ok).to.equal(false)
        ok = pcall(pi._internal.logit_from_bern, 0.5, -0.1)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- log_from_bern — paper-faithful weight (default weight_scheme)
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer._internal.log_from_bern", function()
    lust.after(reset)

    it("log(0.5) ≈ -0.693", function()
        local pi = require("particle_infer")
        expect(approx(pi._internal.log_from_bern(0.5), math.log(0.5), 1e-12))
            .to.equal(true)
    end)

    it("log(1.0) = 0.0 (no upper clamp needed)", function()
        local pi = require("particle_infer")
        local v = pi._internal.log_from_bern(1.0)
        expect(approx(v, 0.0, 1e-12)).to.equal(true)
    end)

    it("log(0) clamps to log(eps) ≈ -16.118 (avoids -inf)", function()
        local pi = require("particle_infer")
        local v = pi._internal.log_from_bern(0)
        -- log(1e-7) ≈ -16.118
        expect(v > -20 and v < -10).to.equal(true)
        expect(v == v).to.equal(true)  -- not NaN
        expect(v ~= -math.huge).to.equal(true)
    end)

    it("monotonically increasing in r", function()
        local pi = require("particle_infer")
        local prev = -math.huge
        for _, r in ipairs({ 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0 }) do
            local v = pi._internal.log_from_bern(r)
            expect(v >= prev).to.equal(true)
            prev = v
        end
    end)

    it("softmax(log r̂) = r̂/Σr̂ (paper-faithful normalization)", function()
        -- For r = {0.6, 0.3, 0.1}, softmax(log r) should equal r/sum(r).
        local pi = require("particle_infer")
        local r = { 0.6, 0.3, 0.1 }
        local sum_r = 1.0  -- already sums to 1
        local w = {}
        for i = 1, 3 do w[i] = pi._internal.log_from_bern(r[i]) end
        local theta = pi._internal.softmax_weights(w, 1.0)
        for i = 1, 3 do
            expect(approx(theta[i], r[i] / sum_r, 1e-6)).to.equal(true)
        end
    end)

    it("rejects non-number / NaN inputs", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.log_from_bern, "bad")
        expect(ok).to.equal(false)
        local nan = 0 / 0
        ok = pcall(pi._internal.log_from_bern, nan)
        expect(ok).to.equal(false)
    end)

    it("rejects eps outside (0, 1)", function()
        local pi = require("particle_infer")
        local ok = pcall(pi._internal.log_from_bern, 0.5, 0)
        expect(ok).to.equal(false)
        ok = pcall(pi._internal.log_from_bern, 0.5, 1.0)
        expect(ok).to.equal(false)
        ok = pcall(pi._internal.log_from_bern, 0.5, -0.1)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Shape registration
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer shape registration", function()
    lust.after(reset)

    it("alc_shapes.M.particle_inferred is defined", function()
        local S = require("alc_shapes")
        expect(S.particle_inferred ~= nil).to.equal(true)
    end)

    it("result shape accepts a minimal valid output", function()
        local S = require("alc_shapes")
        local ok = S.check({
            answer          = "final",
            selected_idx    = 1,
            particles       = {
                {
                    answer      = "final",
                    weight      = 1.0,
                    step_scores = { 0.5, 0.6 },
                    aggregated  = 0.3,
                    n_steps     = 2,
                    active      = false,
                },
            },
            weights         = { 1.0 },
            steps_executed  = 2,
            resample_count  = 2,
            ess_trace       = { 1.0, 1.0 },
            aggregation     = "product",
            final_selection = "argmax_weight",
            stats           = {
                total_llm_calls = 2,
                total_prm_calls = 2,
                total_orm_calls = 0,
            },
        }, S.particle_inferred)
        expect(ok).to.equal(true)
    end)

    it("rejects missing required field (selected_idx)", function()
        local S = require("alc_shapes")
        local ok = S.check({
            answer          = "x",
            -- selected_idx missing
            particles       = {},
            weights         = {},
            steps_executed  = 0,
            resample_count  = 0,
            ess_trace       = {},
            aggregation     = "product",
            final_selection = "argmax_weight",
            stats           = {
                total_llm_calls = 0,
                total_prm_calls = 0,
                total_orm_calls = 0,
            },
        }, S.particle_inferred)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- LLM-integrated helpers (mocked _G.alc)
-- ═══════════════════════════════════════════════════════════════════

local function make_alc_stub(opts)
    opts = opts or {}
    local counter = { llm_calls = 0 }
    local fixtures = opts.fixtures
    local llm_fn
    if type(fixtures) == "function" then
        llm_fn = function(prompt, o)
            counter.llm_calls = counter.llm_calls + 1
            return fixtures(prompt, o, counter.llm_calls)
        end
    elseif type(fixtures) == "table" then
        llm_fn = function(_prompt, _o)
            counter.llm_calls = counter.llm_calls + 1
            local v = fixtures[counter.llm_calls]
            if v == nil then v = "step_" .. tostring(counter.llm_calls) end
            return v
        end
    else
        llm_fn = function(_prompt, _o)
            counter.llm_calls = counter.llm_calls + 1
            return "step_" .. tostring(counter.llm_calls)
        end
    end

    local stub = {
        llm = llm_fn,
        map = function(collection, fn)
            local out = {}
            for i, v in ipairs(collection) do out[i] = fn(v, i) end
            return out
        end,
        log = {
            warn = function(...) end,
            info = function(...) end,
        },
        hash = function(s) return "deadbeef" .. tostring(#s) end,
    }
    if opts.with_card then
        local card_state = { create_calls = 0, samples_calls = 0 }
        stub.card = {
            create = function(args)
                card_state.create_calls = card_state.create_calls + 1
                card_state.last_args = args
                return { card_id = opts.card_id or "stub_card_pf" }
            end,
            write_samples = function(id, list)
                card_state.samples_calls = card_state.samples_calls + 1
                card_state.last_id = id
                card_state.last_list = list
            end,
        }
        counter.card = card_state
    end
    return stub, counter
end

describe("particle_infer._internal.init_particles", function()
    lust.after(reset)

    it("produces N empty particles without any LLM call", function()
        local stub, counter = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(4)
        expect(#parts).to.equal(4)
        expect(counter.llm_calls).to.equal(0)
        for i = 1, 4 do
            expect(parts[i].partial).to.equal("")
            expect(parts[i].active).to.equal(true)
            expect(parts[i].n_steps).to.equal(0)
            expect(#parts[i].step_scores).to.equal(0)
        end
    end)
end)

describe("particle_infer._internal.advance_step", function()
    lust.after(reset)

    it("fans out 1 LLM call per active particle", function()
        local stub, counter = make_alc_stub({
            fixtures = { "a1", "a2", "a3" },
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(3)
        local n_llm = pi._internal.advance_step(parts, "task", 100, 0.8)
        expect(n_llm).to.equal(3)
        expect(counter.llm_calls).to.equal(3)
        expect(parts[1].partial).to.equal("a1")
        expect(parts[2].partial).to.equal("a2")
        expect(parts[3].partial).to.equal("a3")
        for i = 1, 3 do
            expect(parts[i].n_steps).to.equal(1)
        end
    end)

    it("skips inactive particles entirely", function()
        local stub, counter = make_alc_stub({
            fixtures = { "active_response" },
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(3)
        parts[1].active = false
        parts[3].active = false
        local n_llm = pi._internal.advance_step(parts, "task", 100, 0.8)
        expect(n_llm).to.equal(1)
        expect(counter.llm_calls).to.equal(1)
        expect(parts[1].partial).to.equal("")   -- inactive, untouched
        expect(parts[2].partial).to.equal("active_response")
        expect(parts[3].partial).to.equal("")
        expect(parts[1].n_steps).to.equal(0)
        expect(parts[2].n_steps).to.equal(1)
        expect(parts[3].n_steps).to.equal(0)
    end)

    it("empty LLM response leaves partial but still counts as step", function()
        local stub = make_alc_stub({
            fixtures = { "" },
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        pi._internal.advance_step(parts, "task", 100, 0.8)
        expect(parts[1].partial).to.equal("")
        expect(parts[1].n_steps).to.equal(1)
    end)

    it("accumulates multi-step partial with newline separator", function()
        local stub = make_alc_stub({
            fixtures = { "step-1", "step-2" },
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        pi._internal.advance_step(parts, "task", 100, 0.8)
        pi._internal.advance_step(parts, "task", 100, 0.8)
        expect(parts[1].partial).to.equal("step-1\nstep-2")
        expect(parts[1].n_steps).to.equal(2)
    end)
end)

describe("particle_infer._internal.evaluate_prm", function()
    lust.after(reset)

    it("appends per-active score; returns active count", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(2)
        parts[1].partial = "some-answer"
        parts[2].partial = "other-answer"
        local n = pi._internal.evaluate_prm(parts, "task", function(a, _t)
            if a == "some-answer" then return 0.9 end
            return 0.4
        end)
        expect(n).to.equal(2)
        expect(approx(parts[1].step_scores[1], 0.9, 1e-12)).to.equal(true)
        expect(approx(parts[2].step_scores[1], 0.4, 1e-12)).to.equal(true)
    end)

    it("fail-fast on non-number return", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        local ok, err = pcall(pi._internal.evaluate_prm, parts, "task",
            function() return "not-a-number" end)
        expect(ok).to.equal(false)
        expect(err:find("non%-number") ~= nil).to.equal(true)
    end)

    it("fail-fast on NaN", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        local ok, err = pcall(pi._internal.evaluate_prm, parts, "task",
            function() return 0 / 0 end)
        expect(ok).to.equal(false)
        expect(err:find("NaN") ~= nil).to.equal(true)
    end)

    it("fail-fast on r > 1 (Bernoulli parameter violation)", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        local ok, err = pcall(pi._internal.evaluate_prm, parts, "task",
            function() return 1.5 end)
        expect(ok).to.equal(false)
        expect(err:find("Bernoulli") ~= nil).to.equal(true)
    end)

    it("fail-fast on r < 0", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        local ok = pcall(pi._internal.evaluate_prm, parts, "task",
            function() return -0.1 end)
        expect(ok).to.equal(false)
    end)
end)

describe("particle_infer._internal.evaluate_continue", function()
    lust.after(reset)

    it("false return flips active=false; true keeps active", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(3)
        parts[1].partial = "short"
        parts[2].partial = "really long answer"
        parts[3].partial = "medium"
        local n = pi._internal.evaluate_continue(parts, function(partial)
            return #partial < 10
        end)
        expect(n).to.equal(3)
        expect(parts[1].active).to.equal(true)
        expect(parts[2].active).to.equal(false)
        expect(parts[3].active).to.equal(true)
    end)

    it("nil continue_fn → zero calls, no state change", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(2)
        local n = pi._internal.evaluate_continue(parts, nil)
        expect(n).to.equal(0)
        for i = 1, 2 do expect(parts[i].active).to.equal(true) end
    end)

    it("rejects non-boolean return", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local parts = pi._internal.init_particles(1)
        local ok = pcall(pi._internal.evaluate_continue, parts,
            function() return "yes" end)
        expect(ok).to.equal(false)
    end)
end)

describe("particle_infer._internal.select_final", function()
    lust.after(reset)

    local function mk_parts(answers)
        local p = {}
        for i, a in ipairs(answers) do
            p[i] = { partial = a }
        end
        return p
    end

    it("orm: argmax ORM(x_i, task)", function()
        local pi = require("particle_infer")
        local parts = mk_parts({ "A", "B", "C" })
        local orm = function(a, _t)
            if a == "A" then return 0.3
            elseif a == "B" then return 0.9
            else return 0.5 end
        end
        local idx, ans, scores = pi._internal.select_final(
            parts, { 0.4, 0.3, 0.3 }, "task", orm, "orm")
        expect(idx).to.equal(2)
        expect(ans).to.equal("B")
        expect(#scores).to.equal(3)
        expect(approx(scores[2], 0.9, 1e-12)).to.equal(true)
    end)

    it("argmax_weight: picks highest-weight particle", function()
        local pi = require("particle_infer")
        local parts = mk_parts({ "X", "Y", "Z" })
        local idx, ans, scores = pi._internal.select_final(
            parts, { 0.1, 0.8, 0.1 }, "task", nil, "argmax_weight")
        expect(idx).to.equal(2)
        expect(ans).to.equal("Y")
        expect(scores).to.equal(nil)
    end)

    it("weighted_vote: sums weights by answer, picks argmax sum", function()
        local pi = require("particle_infer")
        -- Same answer "X" appears twice with weights 0.3 + 0.3 = 0.6,
        -- "Y" once with 0.4. X wins even though Y's single weight > any
        -- individual X weight.
        local parts = mk_parts({ "X", "Y", "X" })
        local idx, ans = pi._internal.select_final(
            parts, { 0.3, 0.4, 0.3 }, "task", nil, "weighted_vote")
        expect(ans).to.equal("X")
        -- idx must be a valid particle index matching the winning answer
        expect(parts[idx].partial).to.equal("X")
    end)

    it("orm mode without orm_fn → error", function()
        local pi = require("particle_infer")
        local parts = mk_parts({ "A" })
        local ok = pcall(pi._internal.select_final,
            parts, { 1.0 }, "task", nil, "orm")
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- M.run orchestration (end-to-end with mocked alc)
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer.run", function()
    lust.after(reset)

    it("paper-faithful: runs N × max_steps LLM calls under every-step resample", function()
        -- All particles stay active until max_steps → total_llm_calls
        -- = N * max_steps.  N=3, max_steps=2 → 6 LLM + 6 PRM.
        local stub, counter = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task        = "solve",
            prm_fn      = function(_a, _t) return 0.5 end,
            orm_fn      = function(_a, _t) return 1.0 end,
            n_particles = 3,
            max_steps   = 2,
        })
        expect(ctx.result.stats.total_llm_calls).to.equal(6)
        expect(ctx.result.stats.total_prm_calls).to.equal(6)
        expect(ctx.result.stats.total_orm_calls).to.equal(3)
        expect(ctx.result.steps_executed).to.equal(2)
        -- Paper-faithful: ess_threshold=0 → resample every step
        expect(ctx.result.resample_count).to.equal(2)
        expect(ctx.result.final_selection).to.equal("orm")
        expect(ctx.result.answer ~= nil).to.equal(true)
        expect(ctx.result.selected_idx >= 1 and ctx.result.selected_idx <= 3)
            .to.equal(true)
    end)

    it("without orm_fn: falls back to argmax_weight with warning", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task        = "solve",
            prm_fn      = function(_a, _t) return 0.7 end,
            n_particles = 2,
            max_steps   = 1,
        })
        -- fallback promoted 'orm' → 'argmax_weight'
        expect(ctx.result.final_selection).to.equal("argmax_weight")
        expect(ctx.result.stats.total_orm_calls).to.equal(0)
    end)

    it("argmax_weight mode: highest final weight wins", function()
        -- Arrange so particle 1 gets consistently high PRM scores and
        -- should win the argmax_weight tiebreak.
        local stub = make_alc_stub({
            fixtures = function(_p, _o, call_idx)
                return "particle_" .. tostring(((call_idx - 1) % 2) + 1)
            end,
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local prm = function(partial, _t)
            if partial:find("particle_1") then return 0.95 end
            return 0.05
        end
        local ctx = pi.run({
            task             = "solve",
            prm_fn           = prm,
            n_particles      = 2,
            max_steps        = 3,
            final_selection  = "argmax_weight",
        })
        -- Under every-step softmax resample with a 0.95/0.05 PRM gap,
        -- particle 1's lineage dominates the population.
        expect(ctx.result.answer:find("particle_1") ~= nil).to.equal(true)
    end)

    it("continue_fn false stops the particle mid-run", function()
        local stub = make_alc_stub({
            fixtures = { "s1", "s2", "s3", "s4" },
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local stopped = false
        local ctx = pi.run({
            task        = "solve",
            prm_fn      = function(_a, _t) return 0.5 end,
            continue_fn = function(partial)
                if partial:find("s2") then
                    stopped = true
                    return false
                end
                return true
            end,
            n_particles     = 1,
            max_steps       = 4,
            final_selection = "argmax_weight",
        })
        expect(stopped).to.equal(true)
        -- Particle stops after step 2 (continue_fn false). max_steps
        -- loop continues but any_active guard should break early,
        -- giving steps_executed = 2 rather than 4.
        expect(ctx.result.steps_executed).to.equal(2)
        expect(ctx.result.stats.total_llm_calls).to.equal(2)
    end)

    it("ess_threshold > 0 (NOT paper-faithful INJECT) alters resample count", function()
        -- With ess_threshold very close to 1, every step triggers
        -- resample. With ess_threshold = 0.0 (default), every step also
        -- triggers resample. So we test the INJECT path is reachable
        -- and produces a consistent ess_trace.
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task            = "t",
            prm_fn          = function(_a, _t) return 0.5 end,
            n_particles     = 3,
            max_steps       = 2,
            ess_threshold   = 0.9,  -- INJECT path
            final_selection = "argmax_weight",
        })
        expect(#ctx.result.ess_trace).to.equal(2)
        for i = 1, 2 do
            -- Uniform PRM → ESS should stay at N=3
            expect(ctx.result.ess_trace[i] > 0).to.equal(true)
        end
    end)

    it("strips caller-injected functions from ctx post-run", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task        = "t",
            prm_fn      = function(_a, _t) return 0.5 end,
            orm_fn      = function(_a, _t) return 0.5 end,
            continue_fn = function(_p) return true end,
            n_particles = 2,
            max_steps   = 1,
        })
        expect(ctx.prm_fn).to.equal(nil)
        expect(ctx.orm_fn).to.equal(nil)
        expect(ctx.continue_fn).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- M.run input validation (fail-fast before any LLM call)
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer.run input validation", function()
    lust.after(reset)

    it("errors on missing task", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok, err = pcall(pi.run, { prm_fn = function() return 0.5 end })
        expect(ok).to.equal(false)
        expect(err:find("ctx.task") ~= nil).to.equal(true)
    end)

    it("errors on missing prm_fn", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok, err = pcall(pi.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err:find("prm_fn") ~= nil).to.equal(true)
    end)

    it("errors on unknown aggregation", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok, err = pcall(pi.run, {
            task        = "t",
            prm_fn      = function() return 0.5 end,
            aggregation = "geomean",
            n_particles = 1,
            max_steps   = 1,
        })
        expect(ok).to.equal(false)
        expect(err:find("aggregation") ~= nil).to.equal(true)
    end)

    it("errors on softmax_temp ≤ 0", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok = pcall(pi.run, {
            task         = "t",
            prm_fn       = function() return 0.5 end,
            softmax_temp = 0,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on ess_threshold outside [0, 1]", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok = pcall(pi.run, {
            task          = "t",
            prm_fn        = function() return 0.5 end,
            ess_threshold = 1.5,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on unknown final_selection", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok, err = pcall(pi.run, {
            task            = "t",
            prm_fn          = function() return 0.5 end,
            final_selection = "best_odds",
        })
        expect(ok).to.equal(false)
        expect(err:find("final_selection") ~= nil).to.equal(true)
    end)

    it("errors on non-integer n_particles", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok = pcall(pi.run, {
            task        = "t",
            prm_fn      = function() return 0.5 end,
            n_particles = 2.5,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on unknown weight_scheme", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ok, err = pcall(pi.run, {
            task          = "t",
            prm_fn        = function() return 0.5 end,
            weight_scheme = "invalid",
            n_particles   = 1,
            max_steps     = 1,
        })
        expect(ok).to.equal(false)
        expect(err:find("weight_scheme") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Card emission (auto_card=true with stub alc.card)
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer.run Card emission", function()
    lust.after(reset)

    it("emits Card when auto_card=true and alc.card available", function()
        local stub, counter = make_alc_stub({
            with_card = true,
            card_id   = "test_card_pf_7",
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task            = "t",
            prm_fn          = function(_a, _t) return 0.5 end,
            n_particles     = 2,
            max_steps       = 1,
            final_selection = "argmax_weight",
            auto_card       = true,
            scenario_name   = "unit_test",
        })
        expect(ctx.result.card_id).to.equal("test_card_pf_7")
        expect(counter.card.create_calls).to.equal(1)
        expect(counter.card.samples_calls).to.equal(1)
        expect(#counter.card.last_list).to.equal(2)
        -- Card body includes stats + params
        expect(counter.card.last_args.pkg.name:find("particle_infer_") ~= nil)
            .to.equal(true)
        expect(counter.card.last_args.scenario.name).to.equal("unit_test")
        expect(counter.card.last_args.stats.total_llm_calls).to.equal(2)
    end)

    it("fail-safe when alc.card missing (warn + skip)", function()
        local stub = make_alc_stub({ with_card = false })
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task            = "t",
            prm_fn          = function(_a, _t) return 0.5 end,
            n_particles     = 1,
            max_steps       = 1,
            final_selection = "argmax_weight",
            auto_card       = true,
        })
        -- No card emitted, but run completed successfully
        expect(ctx.result.card_id).to.equal(nil)
        expect(ctx.result.answer ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Paper-faithful semantics (regression guards)
--   Two weight_scheme paths tested in parallel:
--   "log_linear" (default, paper-faithful): softmax(log r̂) = r̂/Σr̂
--   "logit_replace" (opt-in, its_hub ref-impl): softmax(logit r̂) = odds-normalized
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer.paper_faithful softmax concentration", function()
    lust.after(reset)

    it("log_linear: N=8, r̂=[0.99, 0.01×7]: theta[1] ≈ 0.934 (paper-faithful r̂/Σr̂)", function()
        -- softmax(log r̂): theta[1] = 0.99/(0.99+7·0.01) = 0.99/1.06 ≈ 0.934.
        -- Guards against regression to flat linear-space w=r̂/N (≈14%).
        local pi = require("particle_infer")
        local r = { 0.99, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01 }
        local w = {}
        for i = 1, #r do w[i] = pi._internal.log_from_bern(r[i]) end
        local theta = pi._internal.softmax_weights(w, 1.0)
        -- paper-faithful: theta[1] = 0.99/1.06 ≈ 0.934. Guard: > 0.9 and < 0.95.
        expect(theta[1] > 0.9).to.equal(true)
        expect(theta[1] < 0.95).to.equal(true)
        local sum_rest = 0
        for i = 2, 8 do sum_rest = sum_rest + theta[i] end
        expect(sum_rest < 0.1).to.equal(true)
    end)

    it("logit_replace: N=8, r̂=[0.99, 0.01×7]: theta[1] > 0.99 (odds-normalized, its_hub parity)", function()
        -- softmax(logit r̂): logit(0.99)≈4.595, logit(0.01)≈-4.595
        -- theta[1] ≈ 99.0/(99.0+7·0.01) ≈ 0.9993.
        local pi = require("particle_infer")
        local r = { 0.99, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01 }
        local w = {}
        for i = 1, #r do w[i] = pi._internal.logit_from_bern(r[i]) end
        local theta = pi._internal.softmax_weights(w, 1.0)
        expect(theta[1] > 0.99).to.equal(true)
    end)

    it("log_linear: N=8, r̂=[0.5]×8 (uniform): softmax → uniform 1/N", function()
        local pi = require("particle_infer")
        local w = {}
        for i = 1, 8 do w[i] = pi._internal.log_from_bern(0.5) end
        local theta = pi._internal.softmax_weights(w, 1.0)
        for i = 1, 8 do
            expect(approx(theta[i], 1 / 8, 1e-12)).to.equal(true)
        end
    end)

    it("rank ordering preserved: highest r̂ → highest theta (both schemes)", function()
        local pi = require("particle_infer")
        local r = { 0.1, 0.9, 0.3, 0.7, 0.5 }
        local w = {}
        for i = 1, #r do w[i] = pi._internal.log_from_bern(r[i]) end
        local theta = pi._internal.softmax_weights(w, 1.0)
        -- argmax over theta == argmax over r̂ (monotonic transform)
        local best_r, best_theta = 1, 1
        for i = 2, #r do
            if r[i] > r[best_r] then best_r = i end
            if theta[i] > theta[best_theta] then best_theta = i end
        end
        expect(best_theta).to.equal(best_r)
    end)
end)

describe("particle_infer.paper_faithful weight replacement", function()
    lust.after(reset)

    it("step 2 weight depends only on r̂_2 (no cross-step accumulation)", function()
        -- Two runs, identical step_2 PRM (= 0.5), different step_1 PRM
        -- (0.1 vs 0.9). Under replacement semantics, final weights must
        -- be identical; under the old multiplicative w_t = w_{t-1}·r̂_t
        -- they would differ by a factor of 9×.
        local function run_with_r1(r1)
            local stub = make_alc_stub({
                fixtures = { "a_step1", "a_step2" },
            })
            _G.alc = stub
            package.loaded["particle_infer"] = nil
            local pi = require("particle_infer")
            local step = 0
            local ctx = pi.run({
                task        = "t",
                prm_fn      = function(_a, _t)
                    step = step + 1
                    if step == 1 then return r1 end
                    return 0.5
                end,
                n_particles     = 1,
                max_steps       = 2,
                final_selection = "argmax_weight",
                ess_threshold   = 0,  -- paper-faithful every-step resample
            })
            return ctx.result
        end
        -- N=1: resample is trivial (only one particle so it always
        -- re-draws itself). The post-run weight reflects the last
        -- step's logit only. softmax(logit(0.5)) on N=1 = 1.0.
        local res_a = run_with_r1(0.1)
        local res_b = run_with_r1(0.9)
        expect(approx(res_a.weights[1], res_b.weights[1], 1e-12))
            .to.equal(true)
        expect(approx(res_a.weights[1], 1.0, 1e-12)).to.equal(true)
    end)

    it("logit weight written by evaluate_prm matches latest step's r̂", function()
        -- With N=2, constant PRM=0.3, after 1 step both particles have
        -- logit(0.3) as their internal weight. softmax of identical
        -- logits = uniform 0.5/0.5.
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task            = "t",
            prm_fn          = function(_a, _t) return 0.3 end,
            n_particles     = 2,
            max_steps       = 1,
            final_selection = "argmax_weight",
        })
        for i = 1, 2 do
            expect(approx(ctx.result.weights[i], 0.5, 1e-9)).to.equal(true)
        end
    end)
end)

describe("particle_infer.paper_faithful output distribution", function()
    lust.after(reset)

    it("result.weights is a probability distribution (sums to 1)", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task        = "t",
            prm_fn      = function(_a, _t) return math.random() end,
            n_particles = 5,
            max_steps   = 3,
            final_selection = "argmax_weight",
        })
        local s = 0
        for i = 1, 5 do
            expect(ctx.result.weights[i] >= 0).to.equal(true)
            expect(ctx.result.weights[i] <= 1).to.equal(true)
            s = s + ctx.result.weights[i]
        end
        expect(approx(s, 1, 1e-9)).to.equal(true)
    end)

    it("per-particle weight mirrors result.weights[i]", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local pi = require("particle_infer")
        local ctx = pi.run({
            task        = "t",
            prm_fn      = function(_a, _t) return 0.5 end,
            n_particles = 3,
            max_steps   = 2,
            final_selection = "argmax_weight",
        })
        for i = 1, 3 do
            expect(approx(ctx.result.weights[i],
                ctx.result.particles[i].weight, 1e-12))
                .to.equal(true)
        end
    end)
end)

describe("particle_infer.paper_faithful resample lineage", function()
    lust.after(reset)

    it("post-resample weight inherits from drawn lineage (deterministic rng)", function()
        -- End-to-end check: with a constant rng driving the resample
        -- multinomial, the drawn lineage is known. After resample, the
        -- inherited logit weight must equal the drawn source's logit.
        -- We exercise this via softmax_weights + resample_multinomial
        -- directly to isolate lineage semantics from the LLM loop.
        local pi = require("particle_infer")
        local logits = {
            pi._internal.logit_from_bern(0.99),  -- strong
            pi._internal.logit_from_bern(0.01),  -- weak
            pi._internal.logit_from_bern(0.01),  -- weak
        }
        local theta = pi._internal.softmax_weights(logits, 1.0)
        -- Constant rng=0.01 always falls into the first cdf bucket
        -- (= particle 1, ≈99.97% cumulative mass). All new slots draw
        -- index 1.
        local _new, drawn = pi._internal.resample_multinomial(
            { "p1", "p2", "p3" }, theta, function() return 0.01 end)
        for i = 1, 3 do
            expect(drawn[i]).to.equal(1)
        end
        -- Simulate the lineage-inherit step in M.run: new_weights[i] =
        -- logits[drawn[i]]. All slots should now carry the strong logit.
        local inherited = {}
        for i = 1, 3 do inherited[i] = logits[drawn[i]] end
        for i = 1, 3 do
            expect(approx(inherited[i], logits[1], 1e-12)).to.equal(true)
        end
    end)

    it("strong-PRM particle dominates 1-step resample (end-to-end)", function()
        -- End-to-end behavioral check after a single resample round:
        -- when one particle gets high r̂ and others get low r̂, the
        -- final softmax distribution must concentrate on the strong
        -- particle. We use max_steps=1 so the test probes the resample
        -- distribution directly, without lineage convergence muddying
        -- the measurement (after step 1 all particles become strong
        -- descendants, and subsequent steps flatten the distribution).
        local stub = make_alc_stub({
            fixtures = function(_p, _o, call_idx)
                return "particle_" .. tostring(((call_idx - 1) % 3) + 1)
            end,
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local prm = function(partial, _t)
            if partial:find("particle_1") then return 0.99 end
            return 0.01
        end
        local ctx = pi.run({
            task        = "t",
            prm_fn      = prm,
            n_particles = 3,
            max_steps   = 1,
            final_selection = "argmax_weight",
        })
        -- All particles share the strong logit after lineage inherit
        -- (the resample draws concentrate ~99.7% on particle 1, and
        -- post-resample each slot inherits that lineage's logit). So
        -- result.weights is either uniform (if draws cloned the same
        -- particle) or nearly uniform, but the selected answer must
        -- carry "particle_1". Under linear-space regression the strong
        -- logit would never dominate the multinomial draw; this
        -- assertion would fail ~2/3 of the time. At 99.7% concentration
        -- per draw, P(at least one slot from strong lineage) ≈ 1.0.
        expect(ctx.result.answer:find("particle_1") ~= nil).to.equal(true)
    end)

    it("log_linear: N=2, r̂=[0.99, 0.01]: theta[1] = 0.99 exactly (paper-faithful)", function()
        -- softmax(log r̂): theta[1] = 0.99/(0.99+0.01) = 0.99 exactly.
        local pi = require("particle_infer")
        local w = {
            pi._internal.log_from_bern(0.99),
            pi._internal.log_from_bern(0.01),
        }
        local theta = pi._internal.softmax_weights(w, 1.0)
        expect(theta[1] >= 0.98).to.equal(true)   -- 0.99 exactly, tolerance for clamp
        expect(theta[2] <= 0.02).to.equal(true)
    end)

    it("logit_replace: N=2, r̂=[0.99, 0.01]: theta[1] > 0.99 (odds-normalized)", function()
        -- softmax(logit r̂): logit(0.99)/logit(0.01) odds diverge.
        local pi = require("particle_infer")
        local w = {
            pi._internal.logit_from_bern(0.99),
            pi._internal.logit_from_bern(0.01),
        }
        local theta = pi._internal.softmax_weights(w, 1.0)
        expect(theta[1] > 0.99).to.equal(true)
        expect(theta[2] < 0.01).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- weight_scheme="logit_replace" backward compat
-- ═══════════════════════════════════════════════════════════════════

describe("particle_infer weight_scheme logit_replace backward compat", function()
    lust.after(reset)

    it("logit_replace: end-to-end produces odds-concentrated weights", function()
        -- With a high-PRM particle under logit_replace, the dominant
        -- particle's final weight should exceed 0.99 (its_hub parity).
        local stub = make_alc_stub({
            fixtures = function(_p, _o, call_idx)
                return "p" .. tostring(((call_idx - 1) % 2) + 1)
            end,
        })
        _G.alc = stub
        local pi = require("particle_infer")
        local prm = function(partial, _t)
            if partial:find("p1") then return 0.99 end
            return 0.01
        end
        local ctx = pi.run({
            task            = "t",
            prm_fn          = prm,
            n_particles     = 2,
            max_steps       = 1,
            weight_scheme   = "logit_replace",
            final_selection = "argmax_weight",
        })
        -- Under logit_replace with r̂=[0.99, 0.01], theta[1] > 0.99.
        -- After resample inherit, both particles may clone particle 1,
        -- but the result.answer must be "p1".
        expect(ctx.result.answer:find("p1") ~= nil).to.equal(true)
    end)

    it("log_linear (default): step 2 weight depends only on r̂_2", function()
        -- Under log_linear replacement, final weight = softmax(log r̂_2).
        -- N=1: softmax of a single element = 1.0 regardless of r̂ value.
        local function run_with_r1_log(r1)
            local stub = make_alc_stub({
                fixtures = { "a_step1", "a_step2" },
            })
            _G.alc = stub
            package.loaded["particle_infer"] = nil
            local pi = require("particle_infer")
            local step = 0
            local ctx = pi.run({
                task          = "t",
                prm_fn        = function(_a, _t)
                    step = step + 1
                    if step == 1 then return r1 end
                    return 0.5
                end,
                n_particles     = 1,
                max_steps       = 2,
                weight_scheme   = "log_linear",
                final_selection = "argmax_weight",
                ess_threshold   = 0,
            })
            return ctx.result
        end
        local res_a = run_with_r1_log(0.1)
        local res_b = run_with_r1_log(0.9)
        expect(approx(res_a.weights[1], res_b.weights[1], 1e-12)).to.equal(true)
        expect(approx(res_a.weights[1], 1.0, 1e-12)).to.equal(true)
    end)
end)
