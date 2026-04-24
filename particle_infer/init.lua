--- particle_infer — Particle-Filter inference-time scaling for LLMs.
---
--- Based on: Puri, Sudalairaj, Xu, Xu, Srivastava
---   "A Probabilistic Inference Approach to Inference-Time Scaling
---    of LLMs using Particle-Based Monte Carlo Methods"
---   (aka Rollout Roulette, arXiv:2502.01618v5, 2025-08).
---
--- Implements the paper's §3.1 Algorithm 1 single-chain Particle
--- Filter under a State-Space-Model formulation of LLM generation.
--- N rollouts (= particles) are advanced one step at a time; a
--- caller-injected Process Reward Model (PRM) scores each step; the
--- particles are resampled at every step via softmax(w); an optional
--- Outcome Reward Model (ORM) picks the final answer.
---
--- ── Paper-faithful core formulas (§2 + §3.1 Alg.1 + Theorem 1) ──
---
---   SSM posterior (§2):
---     p̂_M(x_{1:T}, o_{1:T} | c)
---       ∝ ∏_t p_M(x_t | c, x_{<t}) · ∏_t p̂(o_t | c, x_{<t})
---   Emission (Bernoulli, r̂ = PRM, §2):
---     p̂(o_t | c, x_{<t}) = Bern(o_t; r̂(c, x_{<t}))
---   Weight (paper §3.1 Alg.1 — raw r̂, NOT logit):
---     w = [r̂(x_{1:t}^(1)), …, r̂(x_{1:t}^(N))]
---   Softmax (paper §3.1 Alg.1):
---     θ_t = softmax(w)  =  r̂_i / Σ_j r̂_j   (w = log r̂ equivalent)
---   Resample (paper §3.1 Alg.1, every step):
---     {j_t⁽ⁱ⁾} ~ Multinomial(θ_t); particles ← {x_{1:t}⁽ʲₜ⁽ⁱ⁾⁾}
---   Accumulated weight (paper §4.2 prose):
---     w_t⁽ⁱ⁾ ∝ w_{t−1}⁽ⁱ⁾ · r̂(c, x_{<t}⁽ⁱ⁾)   (linear, not logit)
---   Theorem 1 target (§3):
---     p̂_M(x_{1:T}|c, o_{1:T}=1) ∝ ∏_t p_M(x_t|…) · ∏_t r̂_t
---   Final selection (§3 end):
---     î = argmax_i ORM(x_{1:T}⁽ⁱ⁾, c);  answer = x⁽î⁾
---
--- ── Reference-impl (opt-in) formulas — NOT paper-faithful ────────
---
---   The reference implementation (its_hub, particle_gibbs.py) uses:
---     w_t⁽ⁱ⁾ = logit(r̂_t⁽ⁱ⁾) = log(r̂ / (1 − r̂))      (_inv_sigmoid)
---     θ = softmax(logit(r̂)) = [r̂_i/(1-r̂_i)] / Σ_j [r̂_j/(1-r̂_j)]
---   This is the odds-normalized distribution, NOT r̂/Σr̂. It is a
---   different target distribution from Theorem 1's ∝ ∏_t r̂_t.
---   Exposed as opt-in `weight_scheme = "logit_replace"`.
---
--- Note on the weight space choice. Paper §3.1 Alg.1 pseudo defines
--- w = [r̂(...)] with θ = softmax(w), and §4.2 prose specifies
---   w_t ∝ w_{t-1} · r̂_t
--- (linear multiplicative accumulation). Under every-step resampling,
--- weights are reset to uniform, reducing the accumulated form to
--- w_t ∝ r̂_t — which under softmax(log r̂_t) gives θ_i = r̂_i / Σ_j r̂_j,
--- matching Theorem 1's target p̂_M(x_{1:T}|c, o_{1:T}=1) ∝ ∏_t r̂_t.
--- This is the default (`weight_scheme = "log_linear"`).
---
--- The reference implementation
---   github.com/Red-Hat-AI-Innovation-Team/its_hub
---   (particle_gibbs.py: `_inv_sigmoid` + `partial_log_weights.append`
---    + `_softmax(log_weights[current_step - 1])`)
--- uses logit(r̂) = log(r̂/(1-r̂)) as the weight, giving softmax(logit(r̂)) =
--- r̂/(1-r̂) / Σ — the odds-normalized distribution, NOT r̂/Σ. This is
--- a different target distribution, and Theorem 1's unbiasedness
--- proof does not cover it. The sharp "kill-the-runt" concentration
--- that paper Figure 4 demonstrates at N=4..128 arises from the odds
--- divergence (r̂ → 1 ⇒ logit → ∞), not from the SSM posterior.
--- Exposed as opt-in `weight_scheme = "logit_replace"` for callers
--- who want to match the reference-impl numerics exactly.
---
--- ═══ PAPER FIDELITY & INJECTION POINTS ════════════════════════════
---
--- Paper-faithful defaults (paper §3.1 Alg.1 direct):
---   * Weight scheme: "log_linear" — w_t = log r̂_t, θ ∝ r̂_t (§3.1 Alg.1
---     + Theorem 1). `softmax(log r̂)` = r̂/Σr̂ exactly.
---   * Resampling: every step (paper §3.1 Alg.1; ess_threshold=0.0).
---   * Softmax temperature: T=1 (paper §3.1 Alg.1).
---   * LLM temperature: 0.8 (paper §4.5 ablation default).
---   * Aggregation: "product" — ∏_t r̂_t (paper §3.2 default).
---   * Final selection: "orm" when orm_fn provided (paper §3 end).
---
--- REQUIRED injection points:
---   * prm_fn        — Process Reward Model. Signature
---                      fn(partial_answer, task) → r ∈ [0, 1]
---                      (Bernoulli parameter, paper §2 emission).
---                      Called N × steps times. Non-number / NaN /
---                      out-of-range returns are fail-fast errors.
---
--- OPTIONAL paper-faithful injection points:
---   * orm_fn        — Outcome Reward Model for final selection
---                      (paper §3 end). fn(final_answer, task) → ℝ.
---                      Absent: falls back to argmax-weight selection.
---   * continue_fn   — Per-particle stop predicate.
---                      fn(partial_answer) → boolean. Default: stop
---                      when max_steps reached.
---   * aggregation   — {"product","min","last","model"} (paper §3.2).
---                      Affects the REPORTED `aggregated` scalar per
---                      particle. Does NOT change resampling. "model"
---                      requires a full-prefix-capable PRM.
---   * llm_temperature / gen_tokens_step / n_particles /
---     max_steps — budget / stochasticity knobs (paper §4 setups).
---
--- OPTIONAL NOT paper-faithful injection points:
---   * weight_scheme = "logit_replace" — its_hub ref-impl compatibility.
---                      w_t = logit(r̂_t); softmax gives odds-normalized
---                      distribution. Theorem 1 unbiasedness proof does
---                      not cover this path. Produces "kill-the-runt"
---                      concentration via odds divergence at r̂→1.
---   * ess_threshold > 0 — Switch from every-step resample to ESS-
---                      triggered resample. NOT in paper Alg.1 (ref
---                      impl default 0.5 is an annealing opt-in).
---                      Default 0.0 = paper-faithful every-step path.
---   * final_selection = "weighted_vote" — Paper uses ORM-argmax; this
---                      path aggregates weights by answer, useful when
---                      orm_fn is absent and a softer tiebreak is wanted.
---   * softmax_temp ≠ 1 — Alg.1 uses T=1; other values are heuristic.
---
--- NOT IN v1 (documented shortfalls):
---   * Algorithm 2 (Particle Gibbs) — outer iterations with a pinned
---     reference particle.
---   * Algorithm 3 (Particle Gibbs + Parallel Tempering) — M chains.
---   * Full-prefix PRM auto-detection — delegated to caller's prm_fn.
---
--- Migration note (v0.1.0 breaking change): default weight_scheme
---   changed from effective "logit_replace" (implicit) to "log_linear"
---   (paper-faithful). Callers relying on its_hub reference-impl
---   numerics must add `weight_scheme = "logit_replace"` explicitly.
--- ═══════════════════════════════════════════════════════════════════
---
--- Usage:
---   local pi = require("particle_infer")
---   return pi.run({
---       task     = "Solve: ...",
---       prm_fn   = function(partial, task)
---           return my_prm(partial, task)  -- Bernoulli prob of "on track"
---       end,
---       orm_fn   = function(final, task)
---           return my_orm(final, task)    -- final-answer quality scalar
---       end,
---       -- weight_scheme = "logit_replace"  -- opt-in for its_hub compat
---   })
---
--- Category: selection (alongside sc / smc_sample / gumbel_search /
--- mbr_select / ab_select). Complements smc_sample (whole-answer
--- block-SMC) by occupying the step-wise trajectory tier.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "particle_infer",
    version = "0.1.0",
    description = "Particle-Filter inference-time scaling (Puri et al. "
        .. "2025, arXiv:2502.01618). State-Space formulation of LLM "
        .. "generation with PRM-guided every-step softmax resampling "
        .. "and ORM-based final selection. Default weight_scheme "
        .. "'log_linear' (w_t = log r̂_t) matches paper §3.1 Algorithm 1 "
        .. "+ Theorem 1 target ∝ ∏_t r̂_t. Opt-in 'logit_replace' mirrors "
        .. "the its_hub reference implementation (NOT paper-faithful: "
        .. "samples from odds-normalized distribution). Qwen2.5-Math-1.5B "
        .. "+ 4 particles > GPT-4o (paper §4.2). Default (N=8, max_steps=8) "
        .. "issues up to N·max_steps LLM calls and N·max_steps PRM calls.",
    category = "selection",
}

-- Centralized defaults. Keep magic numbers here; paper citations
-- annotated inline. "paper not numerically fixed" marks knobs the
-- paper leaves to the implementer (caller override recommended).
M._defaults = {
    n_particles     = 8,      -- N (paper §4.4 ablates 4/8/32/64/128)
    max_steps       = 8,      -- T upper bound. Paper uses "while not
                              -- all particles stop" (unbounded) with
                              -- continue_fn; we cap for safety. Paper
                              -- not numerically fixed — caller should
                              -- raise this for long-CoT domains.
    gen_tokens_step = 200,    -- Tokens per LLM call per step. Paper
                              -- §4.1 uses "complete generation step"
                              -- without fixing a byte length; 200 is
                              -- a neutral default for CoT-style steps.
                              -- Paper not numerically fixed.
    aggregation     = "product", -- paper §3.1 Alg.1 default (§3.2)
    softmax_temp    = 1.0,    -- paper §3.1 Alg.1 uses T=1
    ess_threshold   = 0.0,    -- 0.0 = every-step resample (paper-
                              -- faithful). Set > 0 to enable ESS-
                              -- triggered resample (NOT paper-faithful
                              -- per paper §3.1 Alg.1).
    llm_temperature = 0.8,    -- paper §4.5 ablation default
    final_selection = "orm",  -- paper §3 end. Falls back to
                              -- "argmax_weight" when orm_fn is nil.
    weight_scheme   = "log_linear",
                              -- paper-faithful default. softmax(log r̂)
                              -- gives θ ∝ r̂_t, matching paper §3.1
                              -- Alg.1 (`w = [r̂(...)]`, θ = softmax(w))
                              -- and Theorem 1 target ∝ ∏_t r̂_t under
                              -- every-step resample weight reset.
                              -- Set to "logit_replace" for its_hub
                              -- reference-impl compatibility (NOT
                              -- paper-faithful; samples from odds-
                              -- normalized distribution).
}

-- ═══════════════════════════════════════════════════════════════════
-- Pure helpers (testable, LLM-independent)
-- ═══════════════════════════════════════════════════════════════════

--- aggregate_prm_scores — Reduce a per-step PRM score sequence to a
--- single scalar per particle. Paper §3.2 defines four aggregation
--- strategies; all four are paper-faithful.
---
---   product  — ∏_t r̂_t (§3.2 default, matches factorized likelihood)
---   min      — min_t r̂_t (§3.2 bottleneck view)
---   last     — r̂_T (§3.2 efficiency view)
---   model    — r̂_T under the contract that the PRM scored the
---               whole prefix in a single call at step T (§4.5 best
---               aggregation; requires a full-prefix-capable PRM).
---
--- For "model" we use the last-step score because under the caller
--- contract, that call already scored the entire prefix. Callers
--- whose PRM is NOT full-prefix-capable must NOT use this mode; pick
--- "product" instead.
---
---@param step_scores number[][]   -- step_scores[i][t] = r̂_t for particle i
---@param mode string              -- "product" | "min" | "last" | "model"
---@return number[]                -- per-particle aggregated scalar
local function aggregate_prm_scores(step_scores, mode)
    if type(step_scores) ~= "table" then
        error("particle_infer.aggregate_prm_scores: step_scores must be "
            .. "table, got " .. type(step_scores), 2)
    end
    if mode ~= "product" and mode ~= "min"
            and mode ~= "last" and mode ~= "model" then
        error("particle_infer.aggregate_prm_scores: unknown mode '"
            .. tostring(mode) .. "' (expected product / min / last / model)", 2)
    end

    local n = #step_scores
    local out = {}
    for i = 1, n do
        local seq = step_scores[i]
        if type(seq) ~= "table" then
            error("particle_infer.aggregate_prm_scores: step_scores[" .. i
                .. "] must be table, got " .. type(seq), 2)
        end
        local L = #seq
        if L == 0 then
            -- No steps scored — return the mode-specific neutral element:
            --   product → 1.0  (multiplicative identity: ∏ over empty = 1)
            --   min     → +∞   (min over empty set = +∞ by convention)
            --   last / model → error (last element of empty sequence is
            --                  undefined; caller contract violation)
            if mode == "product" then
                out[i] = 1.0
            elseif mode == "min" then
                out[i] = math.huge
            else  -- "last" or "model"
                error("particle_infer.aggregate_prm_scores: step_scores["
                    .. i .. "] is empty; mode '" .. mode
                    .. "' requires at least one scored step", 2)
            end
        elseif mode == "product" then
            local p = 1.0
            for t = 1, L do
                local r = seq[t]
                if type(r) ~= "number" then
                    error("particle_infer.aggregate_prm_scores: step_scores["
                        .. i .. "][" .. t .. "] must be number, got "
                        .. type(r), 2)
                end
                p = p * r
            end
            out[i] = p
        elseif mode == "min" then
            local m = math.huge
            for t = 1, L do
                local r = seq[t]
                if type(r) ~= "number" then
                    error("particle_infer.aggregate_prm_scores: step_scores["
                        .. i .. "][" .. t .. "] must be number, got "
                        .. type(r), 2)
                end
                if r < m then m = r end
            end
            out[i] = m
        else  -- "last" or "model" (same scalar reduction rule, different contract on r̂_T)
            local r = seq[L]
            if type(r) ~= "number" then
                error("particle_infer.aggregate_prm_scores: step_scores["
                    .. i .. "][" .. L .. "] must be number, got "
                    .. type(r), 2)
            end
            out[i] = r
        end
    end
    return out
end

--- softmax_weights — Temperature-scaled softmax with max-shift for
--- numerical stability (paper §3.1 Alg.1 softmax(w)).
---
---   θ_i = exp(w_i / T - m) / Σ_j exp(w_j / T - m),  m = max_j(w_j/T)
---
--- Edge cases:
---   * T → ∞: flatten to uniform 1/N
---   * all-zero or all-equal w: uniform 1/N
---   * sum underflow (every exp(·) = 0): uniform 1/N fallback so the
---     downstream multinomial resample has a valid distribution
---
---@param w number[]
---@param temperature number        -- T, must be > 0
---@return number[]                 -- normalized weights, Σ ≈ 1
local function softmax_weights(w, temperature)
    if type(w) ~= "table" then
        error("particle_infer.softmax_weights: w must be table, got "
            .. type(w), 2)
    end
    if type(temperature) ~= "number" then
        error("particle_infer.softmax_weights: temperature must be number, got "
            .. type(temperature), 2)
    end
    local n = #w
    if n == 0 then
        error("particle_infer.softmax_weights: w must be non-empty", 2)
    end

    -- Temperature ≤ 0 is undefined under softmax. Caller error, fail-fast.
    if temperature <= 0 then
        error("particle_infer.softmax_weights: temperature must be > 0, got "
            .. tostring(temperature), 2)
    end

    -- Infinite temperature → uniform (the limit of softmax(w/T) as T→∞).
    -- Guarded explicitly because math.huge arithmetic is fragile.
    if temperature == math.huge then
        local out = {}
        for i = 1, n do out[i] = 1 / n end
        return out
    end

    local scaled = {}
    local m = -math.huge
    for i = 1, n do
        local v = w[i]
        if type(v) ~= "number" then
            error("particle_infer.softmax_weights: w[" .. i .. "] must be number, got "
                .. type(v), 2)
        end
        if v ~= v then
            error("particle_infer.softmax_weights: w[" .. i .. "] is NaN", 2)
        end
        v = v / temperature
        scaled[i] = v
        if v > m then m = v end
    end

    local sum = 0
    local raw = {}
    for i = 1, n do
        local e = math.exp(scaled[i] - m)
        raw[i] = e
        sum = sum + e
    end

    if sum <= 0 then
        -- Every exp(·) underflowed (all scaled[i] - m ≪ -700). Fall
        -- back to uniform so multinomial resample stays well-defined.
        local out = {}
        for i = 1, n do out[i] = 1 / n end
        return out
    end

    local out = {}
    for i = 1, n do out[i] = raw[i] / sum end
    return out
end

--- compute_ess — Effective Sample Size.
---   ESS = (Σ w_i)² / Σ (w_i²)
---
--- Not on paper §3.1 Alg.1's paper-faithful path (which resamples
--- every step unconditionally) but exposed so callers using the
--- non-paper ess_threshold > 0 INJECT can instrument the trace.
---
---@param weights number[]
---@return number
local function compute_ess(weights)
    if type(weights) ~= "table" then
        error("particle_infer.compute_ess: weights must be table, got "
            .. type(weights), 2)
    end
    local n = #weights
    if n == 0 then
        error("particle_infer.compute_ess: weights must be non-empty", 2)
    end
    local s1, s2 = 0, 0
    for i = 1, n do
        local w = weights[i]
        if type(w) ~= "number" then
            error("particle_infer.compute_ess: weights[" .. i .. "] must be number, got "
                .. type(w), 2)
        end
        s1 = s1 + w
        s2 = s2 + w * w
    end
    if s2 <= 0 then return 0 end
    return (s1 * s1) / s2
end

--- resample_multinomial — CDF-based multinomial draw with replacement.
---
--- Returns `new_particles, drawn_indices`. `drawn_indices[i] = j`
--- means `new_particles[i] == particles[j]`. Equivalent to
--- smc_sample's resampler; kept local so particle_infer doesn't
--- dependency-import smc_sample at runtime (both pkg have the same
--- multinomial contract).
---
---@param particles any[]
---@param weights number[]
---@param rng nil|fun():number      -- test injection; default math.random
---@return any[], integer[]
local function resample_multinomial(particles, weights, rng)
    if type(particles) ~= "table" then
        error("particle_infer.resample_multinomial: particles must be table, got "
            .. type(particles), 2)
    end
    if type(weights) ~= "table" then
        error("particle_infer.resample_multinomial: weights must be table, got "
            .. type(weights), 2)
    end
    local n = #particles
    if n == 0 then
        error("particle_infer.resample_multinomial: particles must be non-empty", 2)
    end
    if #weights ~= n then
        error("particle_infer.resample_multinomial: #weights (" .. #weights
            .. ") != #particles (" .. n .. ")", 2)
    end
    local draw = rng or math.random

    local sum = 0
    for i = 1, n do sum = sum + weights[i] end
    if sum <= 0 then
        error("particle_infer.resample_multinomial: Σweights must be > 0", 2)
    end

    local cdf = {}
    local acc = 0
    for i = 1, n do
        acc = acc + weights[i] / sum
        cdf[i] = acc
    end
    cdf[n] = 1.0  -- guard against floating drift on the last bucket

    local out = {}
    local drawn = {}
    for i = 1, n do
        local u = draw()
        local idx = n
        for j = 1, n do
            if u < cdf[j] then idx = j; break end
        end
        out[i] = particles[idx]
        drawn[i] = idx
    end
    return out, drawn
end

--- logit_from_bern — Convert a Bernoulli probability r̂ ∈ [0,1] to its
--- log-odds (logit) scalar. Mirrors the reference implementation's
--- `_inv_sigmoid` (its_hub/algorithms/particle_gibbs.py) used as the
--- per-step particle weight. Clamps r̂ to (eps, 1-eps) to avoid ±∞
--- when the PRM saturates; ref impl default clip is 1e-7.
---
---   logit(r̂) = log(r̂ / (1 − r̂))
---
--- Reference-impl (its_hub) compatibility weight. **NOT paper-faithful**:
--- maps r̂ to odds ratio r̂/(1-r̂), which under softmax gives a
--- distribution proportional to odds, not to r̂. Use
--- `weight_scheme='logit_replace'` to select this path. Paper-faithful
--- path uses `log_from_bern` instead.
---
---@param r    number   -- PRM Bernoulli parameter ∈ [0, 1]
---@param eps  nil|number -- clamp floor / ceiling (default 1e-7)
---@return number         -- logit(clamp(r, eps, 1-eps))
local function logit_from_bern(r, eps)
    if type(r) ~= "number" then
        error("particle_infer.logit_from_bern: r must be number, got "
            .. type(r), 2)
    end
    if r ~= r then
        error("particle_infer.logit_from_bern: r is NaN", 2)
    end
    eps = eps or 1e-7
    if type(eps) ~= "number" or eps <= 0 or eps >= 0.5 then
        error("particle_infer.logit_from_bern: eps must be in (0, 0.5), got "
            .. tostring(eps), 2)
    end
    local rc
    if r < eps then
        rc = eps
    elseif r > 1 - eps then
        rc = 1 - eps
    else
        rc = r
    end
    return math.log(rc / (1 - rc))
end

--- log_from_bern — Convert a Bernoulli probability r̂ ∈ [0,1] to its
--- natural log. This is the paper-faithful per-step particle weight:
--- softmax(log r̂) gives θ_i = r̂_i / Σ_j r̂_j, matching paper §3.1
--- Algorithm 1 (`w = [r̂(...)]`, θ = softmax(w)) and Theorem 1's
--- target p̂_M(x_{1:T}|c, o_{1:T}=1) ∝ ∏_t r̂_t.
---
---   log(r̂) = ln(clamp(r̂, eps, 1))
---
--- Only the lower bound is clamped: log(1) = 0 is finite, so no upper
--- clamp is needed. eps must be in (0, 1).
---
---@param r    number    -- PRM Bernoulli parameter ∈ [0, 1]
---@param eps  nil|number -- lower clamp (default 1e-7); must be in (0, 1)
---@return number          -- log(clamp(r, eps, 1))
local function log_from_bern(r, eps)
    if type(r) ~= "number" then
        error("particle_infer.log_from_bern: r must be number, got "
            .. type(r), 2)
    end
    if r ~= r then
        error("particle_infer.log_from_bern: r is NaN", 2)
    end
    eps = eps or 1e-7
    if type(eps) ~= "number" or eps <= 0 or eps >= 1 then
        error("particle_infer.log_from_bern: eps must be in (0, 1), got "
            .. tostring(eps), 2)
    end
    local rc = (r < eps) and eps or r
    return math.log(rc)
end

-- ═══════════════════════════════════════════════════════════════════
-- Shape definition for M.spec.entries.run.input
-- ═══════════════════════════════════════════════════════════════════

-- prm_fn / orm_fn / continue_fn are T.any because alc_shapes has no
-- function combinator (closures can't cross the Schema-as-Data
-- persistence boundary). The run entry type-checks them manually on
-- the first body lines (fail-fast).
local run_input_shape = T.shape({
    task            = T.string:describe("Problem statement fed to LLM + prm_fn + orm_fn"),
    prm_fn          = T.any:describe(
        "REQUIRED. Process Reward Model. fn(partial_answer, task) → "
            .. "r ∈ [0, 1]. Called N × max_steps times. Runtime "
            .. "type-checked."),
    orm_fn          = T.any:is_optional():describe(
        "OPTIONAL. Outcome Reward Model for final selection (paper §3 "
            .. "end). fn(final_answer, task) → ℝ. Falls back to "
            .. "argmax-weight selection when nil."),
    continue_fn     = T.any:is_optional():describe(
        "OPTIONAL. Per-particle stop predicate. fn(partial_answer) → "
            .. "boolean. Default: max_steps-only termination."),
    n_particles     = T.number:is_optional():describe("N (default 8, paper §4.4)"),
    max_steps       = T.number:is_optional():describe("T cap (default 8)"),
    gen_tokens_step = T.number:is_optional():describe("Tokens per step LLM call (default 200)"),
    aggregation     = T.one_of({ "product", "min", "last", "model" }):is_optional()
        :describe("PRM step→scalar reduction (§3.2). Default 'product'."),
    softmax_temp    = T.number:is_optional():describe(
        "Softmax temperature T in softmax(w/T). Paper Alg.1 default 1.0."),
    ess_threshold   = T.number:is_optional():describe(
        "0.0 (default) = every-step resample (paper-faithful). "
            .. "> 0 switches to ESS-triggered resample (NOT paper-faithful)."),
    llm_temperature = T.number:is_optional():describe("LLM sampling temperature (default 0.8)"),
    final_selection = T.one_of({ "orm", "argmax_weight", "weighted_vote" }):is_optional()
        :describe("Paper uses 'orm'. 'weighted_vote' is NOT paper-faithful."),
    weight_scheme   = T.one_of({ "log_linear", "logit_replace" }):is_optional()
        :describe("Per-step weight formula. 'log_linear' (default, paper-faithful): "
            .. "w_t = log(r̂_t), θ ∝ r̂_t (paper §3.1 Alg.1 + Theorem 1). "
            .. "'logit_replace' (NOT paper-faithful, its_hub ref-impl compat): "
            .. "w_t = logit(r̂_t), θ ∝ r̂_t/(1-r̂_t)."),
    -- Card IF
    auto_card       = T.boolean:is_optional():describe("Emit a Card on completion (default false)"),
    card_pkg        = T.string:is_optional():describe(
        "Card pkg.name override (default 'particle_infer_<task_hash>')"),
    scenario_name   = T.string:is_optional():describe("Explicit scenario name for emitted Card"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input  = run_input_shape,
            result = "particle_inferred",
        },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- LLM integration helpers (testable with alc stub)
-- ═══════════════════════════════════════════════════════════════════

--- map_or_serial — alc.map when available, serial for-loop otherwise.
--- Same fallback convention as sc / smc_sample / mbr_select.
local function map_or_serial(collection, fn)
    if type(alc) == "table" and type(alc.map) == "function" then
        return alc.map(collection, fn)
    end
    local out = {}
    for i, v in ipairs(collection) do out[i] = fn(v, i) end
    return out
end

--- build_step_prompt — Prompt asking the LLM to produce the NEXT
--- reasoning step given the partial answer so far.
---
--- v1 uses a fixed template; callers wanting a different granularity
--- ("token" / "sentence" / "CoT step") currently adjust gen_tokens_step
--- and shape their task prompt. A per-step prompt INJECT is a
--- v2 candidate.
local function build_step_prompt(task, partial)
    if partial == nil or partial == "" then
        -- Step 1: no prior reasoning — ask for the first reasoning step.
        return string.format(
            "Task:\n%s\n\nProduce the next reasoning step only. "
                .. "If the task is solvable in one step, produce the "
                .. "final answer. Keep your output concise.",
            tostring(task))
    end
    return string.format(
        "Task:\n%s\n\nReasoning so far:\n%s\n\nContinue with the next "
            .. "reasoning step only. If the reasoning is complete, "
            .. "produce the final answer.",
        tostring(task), tostring(partial))
end

--- init_particles — Create N empty-partial particles.
--- No LLM calls are made here; the first LLM round is step 1 of the
--- main loop (so total_llm_calls counters stay consistent with "one
--- LLM call per particle per active step").
local function init_particles(n)
    local parts = {}
    for i = 1, n do
        parts[i] = {
            partial     = "",       -- accumulated reasoning / answer text
            active      = true,     -- false once continue_fn returns false
            n_steps     = 0,        -- total generated steps
            step_scores = {},       -- r̂_t history (length n_steps)
        }
    end
    return parts
end

--- advance_step — Generate one reasoning step for each ACTIVE particle
--- in parallel. Updates `partial`, `n_steps`. Returns the count of LLM
--- calls actually issued (= number of active particles at call time).
---
--- Inactive particles (already stopped via continue_fn) are left
--- untouched. LLM failures / empty responses mark the particle active
--- but append nothing — the particle's partial stays the same, giving
--- the PRM a stable score target at the next step.
local function advance_step(particles, task, gen_tokens, llm_temperature)
    local active_idx = {}
    for i = 1, #particles do
        if particles[i].active then active_idx[#active_idx + 1] = i end
    end
    if #active_idx == 0 then return 0 end

    local prompts = {}
    for j, i in ipairs(active_idx) do
        prompts[j] = build_step_prompt(task, particles[i].partial)
    end

    local responses = map_or_serial(prompts, function(prompt, _j)
        local ok, resp = pcall(alc.llm, prompt, {
            max_tokens  = gen_tokens,
            temperature = llm_temperature,
        })
        if not ok then return "" end
        if type(resp) ~= "string" then return "" end
        return resp
    end)

    for j, i in ipairs(active_idx) do
        local resp = responses[j]
        if type(resp) == "string" and resp ~= "" then
            if particles[i].partial == "" then
                particles[i].partial = resp
            else
                particles[i].partial = particles[i].partial .. "\n" .. resp
            end
        end
        particles[i].n_steps = particles[i].n_steps + 1
    end

    return #active_idx
end

--- evaluate_prm — Score each ACTIVE particle's current partial answer
--- under the caller's PRM and append to its step_scores. Fail-fast on
--- non-number / NaN / out-of-range (Bernoulli parameter ∉ [0, 1])
--- returns — the paper contract treats r̂ as a Bernoulli parameter,
--- silent coercion would corrupt the weight product invariant.
---
--- Returns `n_calls` (number of prm_fn invocations).
local function evaluate_prm(particles, task, prm_fn)
    local active_idx = {}
    for i = 1, #particles do
        if particles[i].active then active_idx[#active_idx + 1] = i end
    end
    if #active_idx == 0 then return 0 end

    local active_particles = {}
    for j, i in ipairs(active_idx) do active_particles[j] = particles[i] end

    local results = map_or_serial(active_particles, function(p, _j)
        local ok, r = pcall(prm_fn, p.partial, task)
        return { ok = ok, val = r }
    end)

    for j, res in ipairs(results) do
        local i = active_idx[j]
        if not res.ok then
            error(string.format(
                "particle_infer.run: prm_fn failed for particle %d: %s",
                i, tostring(res.val)), 2)
        end
        local r = res.val
        if type(r) ~= "number" then
            error(string.format(
                "particle_infer.run: prm_fn returned non-number for particle %d: "
                    .. "%s (type %s)",
                i, tostring(r), type(r)), 2)
        end
        if r ~= r then
            error(string.format(
                "particle_infer.run: prm_fn returned NaN for particle %d", i), 2)
        end
        if r < 0 or r > 1 then
            error(string.format(
                "particle_infer.run: prm_fn returned %.6g for particle %d "
                    .. "(contract: Bernoulli parameter r ∈ [0, 1])", r, i), 2)
        end
        local p = particles[i]
        p.step_scores[#p.step_scores + 1] = r
    end

    return #active_idx
end

--- evaluate_continue — Apply caller's continue_fn to each active
--- particle; flip `active = false` on any particle whose continue_fn
--- returns false. Errors are fail-fast (masked errors would let a
--- particle run past its stop condition silently).
---
--- Returns number of continue_fn calls (= active particle count).
local function evaluate_continue(particles, continue_fn)
    if continue_fn == nil then return 0 end
    local n_calls = 0
    for i = 1, #particles do
        if particles[i].active then
            local ok, cont = pcall(continue_fn, particles[i].partial)
            n_calls = n_calls + 1
            if not ok then
                error(string.format(
                    "particle_infer.run: continue_fn failed for particle %d: %s",
                    i, tostring(cont)), 2)
            end
            if cont ~= true and cont ~= false then
                error(string.format(
                    "particle_infer.run: continue_fn must return boolean for "
                        .. "particle %d, got %s (type %s)",
                    i, tostring(cont), type(cont)), 2)
            end
            if cont == false then particles[i].active = false end
        end
    end
    return n_calls
end

--- select_final — Pick the final answer from the population.
---
---   mode = "orm"           — argmax_i ORM(x_i, task). REQUIRES orm_fn.
---   mode = "argmax_weight" — argmax_i weight_i (fallback).
---   mode = "weighted_vote" — for each unique answer, sum the weights
---                             of particles with that answer; pick the
---                             argmax. NOT paper-faithful. Useful when
---                             no orm_fn is available and the caller
---                             prefers a softer tiebreak.
---
--- Returns `selected_idx, answer, orm_scores`. orm_scores is nil for
--- non-orm modes.
local function select_final(particles, weights, task, orm_fn, mode)
    local n = #particles
    if n == 0 then
        error("particle_infer.select_final: empty particle set", 2)
    end

    if mode == "orm" then
        if type(orm_fn) ~= "function" then
            -- Caller contract violation: mode says 'orm' but no ORM.
            error("particle_infer.select_final: final_selection='orm' "
                .. "requires ctx.orm_fn (function)", 2)
        end
        local scores = {}
        for i = 1, n do
            local ok, s = pcall(orm_fn, particles[i].partial, task)
            if not ok then
                error(string.format(
                    "particle_infer.run: orm_fn failed for particle %d: %s",
                    i, tostring(s)), 2)
            end
            if type(s) ~= "number" then
                error(string.format(
                    "particle_infer.run: orm_fn returned non-number for "
                        .. "particle %d: %s (type %s)",
                    i, tostring(s), type(s)), 2)
            end
            if s ~= s then
                error(string.format(
                    "particle_infer.run: orm_fn returned NaN for particle %d", i), 2)
            end
            scores[i] = s
        end
        local best = 1
        for i = 2, n do
            if scores[i] > scores[best] then best = i end
        end
        return best, particles[best].partial, scores
    elseif mode == "argmax_weight" then
        local best = 1
        local best_w = weights[1]
        for i = 2, n do
            if weights[i] > best_w then
                best_w = weights[i]
                best = i
            end
        end
        return best, particles[best].partial, nil
    elseif mode == "weighted_vote" then
        -- NOT paper-faithful: bucket weights by answer text.
        local buckets = {}
        local order   = {}  -- first-seen order for deterministic tiebreak
        for i = 1, n do
            local a = particles[i].partial
            if buckets[a] == nil then
                buckets[a] = 0
                order[#order + 1] = a
            end
            buckets[a] = buckets[a] + weights[i]
        end
        local best_a, best_score = order[1], buckets[order[1]]
        for k = 2, #order do
            local a = order[k]
            if buckets[a] > best_score then
                best_score = buckets[a]
                best_a = a
            end
        end
        -- Return the first particle whose answer matches best_a (so
        -- the returned selected_idx is a valid index into particles[]).
        for i = 1, n do
            if particles[i].partial == best_a then
                return i, best_a, nil
            end
        end
        -- Unreachable: best_a came from a particle so at least one must match.
        return 1, particles[1].partial, nil
    end
    error("particle_infer.select_final: unknown mode '" .. tostring(mode) .. "'", 2)
end

-- ═══════════════════════════════════════════════════════════════════
-- Card IF — emit_card (Two-Tier, smc_sample / conformal_vote pattern)
-- ═══════════════════════════════════════════════════════════════════

local function emit_card(ctx, result, per_particle_list)
    if type(alc) ~= "table" or type(alc.card) ~= "table"
            or type(alc.card.create) ~= "function" then
        if type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.warn) == "function" then
            alc.log.warn("particle_infer: alc.card unavailable — skipping Card emission")
        end
        return nil
    end

    local hash_source
    if type(alc.hash) == "function" then
        hash_source = tostring(alc.hash(ctx.task or ""))
    else
        hash_source = tostring(os.time())
    end
    local pkg_name = ctx.card_pkg or ("particle_infer_" .. string.sub(hash_source, 1, 8))

    local card = alc.card.create({
        pkg = { name = pkg_name },
        scenario = { name = ctx.scenario_name or "unknown" },
        params = {
            n_particles     = #per_particle_list,
            max_steps       = ctx.max_steps or M._defaults.max_steps,
            aggregation     = ctx.aggregation or M._defaults.aggregation,
            softmax_temp    = ctx.softmax_temp or M._defaults.softmax_temp,
            ess_threshold   = ctx.ess_threshold or M._defaults.ess_threshold,
            llm_temperature = ctx.llm_temperature or M._defaults.llm_temperature,
            final_selection = ctx.final_selection or M._defaults.final_selection,
        },
        stats = {
            total_llm_calls = result.stats.total_llm_calls,
            total_prm_calls = result.stats.total_prm_calls,
            total_orm_calls = result.stats.total_orm_calls,
            steps_executed  = result.steps_executed,
            resample_count  = result.resample_count,
        },
        particle_infer = {
            answer          = result.answer,
            n_particles     = #per_particle_list,
            steps_executed  = result.steps_executed,
            resample_count  = result.resample_count,
            aggregation     = result.aggregation,
            final_selection = result.final_selection,
            ess_trace       = result.ess_trace,
        },
    })

    if type(card) == "table" and type(card.card_id) == "string"
            and #per_particle_list > 0
            and type(alc.card.write_samples) == "function" then
        alc.card.write_samples(card.card_id, per_particle_list)
    end

    if type(card) == "table" and type(card.card_id) == "string" then
        return card.card_id
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- M.run — State-Space Particle Filter (paper §3.1 Algorithm 1)
-- ═══════════════════════════════════════════════════════════════════

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    -- ─── ctx validation (fail-fast) ───
    if type(ctx) ~= "table" then
        error("particle_infer.run: ctx must be table, got " .. type(ctx), 2)
    end
    local task = ctx.task
    if type(task) ~= "string" or task == "" then
        error("particle_infer.run: ctx.task is required (non-empty string)", 2)
    end
    local prm_fn = ctx.prm_fn
    if type(prm_fn) ~= "function" then
        error("particle_infer.run: ctx.prm_fn is required "
            .. "(function fn(partial, task) → number ∈ [0, 1])", 2)
    end

    local orm_fn = ctx.orm_fn
    if orm_fn ~= nil and type(orm_fn) ~= "function" then
        error("particle_infer.run: ctx.orm_fn must be function or nil, got "
            .. type(orm_fn), 2)
    end

    local continue_fn = ctx.continue_fn
    if continue_fn ~= nil and type(continue_fn) ~= "function" then
        error("particle_infer.run: ctx.continue_fn must be function or nil, got "
            .. type(continue_fn), 2)
    end

    -- ─── Strip caller-injected closures from ctx (smc_sample pattern) ───
    -- Keep the local captures usable; clear ctx keys before any error
    -- path so that post-hoc MCP-boundary logging sees JSON-serializable
    -- ctx only.
    for k, v in pairs(ctx) do
        if type(v) == "function" then ctx[k] = nil end
    end

    -- ─── Resolve hyperparameters ───
    local N           = ctx.n_particles     or M._defaults.n_particles
    local T_max       = ctx.max_steps       or M._defaults.max_steps
    local gen_tokens  = ctx.gen_tokens_step or M._defaults.gen_tokens_step
    local aggregation = ctx.aggregation     or M._defaults.aggregation
    local soft_temp   = ctx.softmax_temp    or M._defaults.softmax_temp
    local ess_thr     = ctx.ess_threshold   or M._defaults.ess_threshold
    local llm_temp    = ctx.llm_temperature or M._defaults.llm_temperature
    local fs_mode     = ctx.final_selection or M._defaults.final_selection
    local ws          = ctx.weight_scheme   or M._defaults.weight_scheme

    if type(N) ~= "number" or N < 1 or N ~= math.floor(N) then
        error("particle_infer.run: n_particles must be positive integer, got "
            .. tostring(N), 2)
    end
    if type(T_max) ~= "number" or T_max < 0 or T_max ~= math.floor(T_max) then
        error("particle_infer.run: max_steps must be non-negative integer, got "
            .. tostring(T_max), 2)
    end
    if type(gen_tokens) ~= "number" or gen_tokens <= 0 then
        error("particle_infer.run: gen_tokens_step must be positive number, got "
            .. tostring(gen_tokens), 2)
    end
    if aggregation ~= "product" and aggregation ~= "min"
            and aggregation ~= "last" and aggregation ~= "model" then
        error("particle_infer.run: aggregation must be one of "
            .. "'product'/'min'/'last'/'model', got '"
            .. tostring(aggregation) .. "'", 2)
    end
    if type(soft_temp) ~= "number" or soft_temp <= 0 then
        error("particle_infer.run: softmax_temp must be > 0, got "
            .. tostring(soft_temp), 2)
    end
    if type(ess_thr) ~= "number" or ess_thr < 0 or ess_thr > 1 then
        error("particle_infer.run: ess_threshold must be in [0, 1], got "
            .. tostring(ess_thr), 2)
    end
    if type(llm_temp) ~= "number" or llm_temp < 0 then
        error("particle_infer.run: llm_temperature must be ≥ 0, got "
            .. tostring(llm_temp), 2)
    end
    if fs_mode ~= "orm" and fs_mode ~= "argmax_weight"
            and fs_mode ~= "weighted_vote" then
        error("particle_infer.run: final_selection must be 'orm' / "
            .. "'argmax_weight' / 'weighted_vote', got '"
            .. tostring(fs_mode) .. "'", 2)
    end
    if ws ~= "log_linear" and ws ~= "logit_replace" then
        error("particle_infer.run: weight_scheme must be 'log_linear' / "
            .. "'logit_replace', got '" .. tostring(ws) .. "'", 2)
    end
    -- Silent-downgrade: mode='orm' without orm_fn → fall back to
    -- argmax_weight with a warn. Paper §3 end recommends ORM; but
    -- callers may legitimately omit orm_fn and rely on PRM weights
    -- as the proxy signal. Hard-failing here would punish a common
    -- usage pattern (ORM not yet wired up, PRM only).
    if fs_mode == "orm" and orm_fn == nil then
        if type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.warn) == "function" then
            alc.log.warn("particle_infer.run: final_selection='orm' but "
                .. "ctx.orm_fn is nil; falling back to 'argmax_weight'")
        end
        fs_mode = "argmax_weight"
    end

    -- ─── PF initialization ───
    local total_llm_calls = 0
    local total_prm_calls = 0
    local total_orm_calls = 0
    local resample_count  = 0
    local ess_trace       = {}

    local particles = init_particles(N)
    local weights = {}
    -- Initialize weights at 0. Under log_linear: log(1) = 0 is a
    -- neutral constant; softmax over identical constants = uniform 1/N.
    -- Under logit_replace: logit(0.5) = 0, same uniform result.
    -- The first evaluate_prm call overwrites these before any resample,
    -- so the initial value is arbitrary (softmax-cancelled by uniformity).
    for i = 1, N do weights[i] = 0 end

    -- ─── Main loop (paper §3.1 Algorithm 1) ───
    -- Per step t = 1..T_max:
    --   1. advance_step: 1 LLM call per active particle (block of tokens)
    --   2. evaluate_prm: PRM scores each active particle's new partial
    --   3. weight update: w_t = weight_fn(r̂_t), replacement semantics.
    --      weight_fn = log_from_bern  (default, paper-faithful log_linear)
    --               or logit_from_bern (opt-in logit_replace, ref-impl compat)
    --   4. softmax → multinomial resample (every step unless ess_thr > 0);
    --      drawn particles inherit their lineage's weight for the output
    --      distribution
    --   5. evaluate_continue: flip stop flags for particles that finished
    local steps_executed = 0
    for _t = 1, T_max do
        -- Check whether any particle is still active; break early if all
        -- stopped. Paper's "while not all stop" is handled by this guard.
        local any_active = false
        for i = 1, N do
            if particles[i].active then any_active = true; break end
        end
        if not any_active then break end

        -- 1. Advance 1 step on active particles.
        local n_llm = advance_step(particles, task, gen_tokens, llm_temp)
        total_llm_calls = total_llm_calls + n_llm

        -- 2. PRM scoring.
        local n_prm = evaluate_prm(particles, task, prm_fn)
        total_prm_calls = total_prm_calls + n_prm

        -- 3. Per-step weight update — replace, not accumulate. Only the
        --    latest step's score drives resampling (replacement semantics).
        --    Inactive particles keep their prior weight unchanged (no new
        --    step scored → no information to overwrite with).
        --    weight_fn dispatch:
        --      "log_linear"    (default, paper-faithful): w_t = log(r̂_t)
        --        softmax(log r̂) = r̂/Σr̂, matching paper §3.1 Alg.1 +
        --        Theorem 1 target ∝ ∏_t r̂_t.
        --      "logit_replace" (NOT paper-faithful, its_hub ref-impl):
        --        w_t = logit(r̂_t) = log(r̂/(1-r̂))
        --        softmax(logit r̂) = odds-normalized, NOT r̂/Σr̂.
        local weight_fn = (ws == "logit_replace")
            and logit_from_bern or log_from_bern
        for i = 1, N do
            if particles[i].active then
                local last_r = particles[i].step_scores[#particles[i].step_scores]
                weights[i] = weight_fn(last_r)
            end
        end

        -- 4. softmax(w / T) → multinomial resample.
        --    Paper-faithful: resample EVERY step (ess_thr = 0.0 default).
        --    ESS-triggered path: resample iff ESS < ess_thr · N.
        --    ESS trace (diagnostic): computed on the same theta so we
        --    call softmax_weights once and reuse the result for both.
        local theta = softmax_weights(weights, soft_temp)
        ess_trace[#ess_trace + 1] = compute_ess(theta)
        local do_resample
        if ess_thr <= 0 then
            do_resample = true
        else
            do_resample = (ess_trace[#ess_trace] < ess_thr * N)
        end
        if do_resample then
            local new_parts, drawn = resample_multinomial(particles, theta)
            -- Deep-copy each resampled particle so future advance_step /
            -- evaluate_prm mutations on one slot don't alias into another.
            -- The multinomial draw is with replacement, so two slots can
            -- point to the same original table; that's the aliasing bug
            -- vector. smc_sample's mh_rejuvenate avoids it by always
            -- building a fresh table on Accept, but here we ALWAYS mutate
            -- in place (advance_step appends to partial, evaluate_prm
            -- appends to step_scores), so a deep-copy on resample is the
            -- only safe baseline.
            local fresh = {}
            local fresh_weights = {}
            for i = 1, N do
                local src = new_parts[i]
                local scopy = {}
                for k = 1, #src.step_scores do scopy[k] = src.step_scores[k] end
                fresh[i] = {
                    partial     = src.partial,
                    active      = src.active,
                    n_steps     = src.n_steps,
                    step_scores = scopy,
                }
                -- Inherit the drawn lineage's current logit weight. Next
                -- step's evaluate_prm will overwrite it with logit(r̂_new)
                -- for active particles. Reference impl equivalent:
                -- `resampled_particles = [p.deepcopy() for ...]` carries
                -- each particle's `partial_log_weights` list, and
                -- `log_weight` returns the last appended element.
                fresh_weights[i] = weights[drawn[i]]
            end
            particles = fresh
            for i = 1, N do weights[i] = fresh_weights[i] end
            resample_count = resample_count + 1
        end
        -- No-resample branch: weights stay as current logits. Next step's
        -- evaluate_prm overwrites with the fresh logit (no compounding).

        -- 5. continue_fn per active particle.
        if continue_fn ~= nil then
            evaluate_continue(particles, continue_fn)
        end

        steps_executed = _t
    end

    -- ─── Aggregate PRM scores per particle for shape output ───
    local step_matrix = {}
    for i = 1, N do step_matrix[i] = particles[i].step_scores end
    local aggregated = aggregate_prm_scores(step_matrix, aggregation)

    -- ─── Final softmax-normalized probability distribution ───
    -- Internal `weights[]` are logits (ℝ). Expose normalized
    -- probabilities in the result so callers reading `result.weights`
    -- and `result.particles[i].weight` see a proper distribution that
    -- sums to 1 — matches the old linear-weight contract and is what
    -- E2E graders / Cards expect.
    local final_theta = softmax_weights(weights, soft_temp)

    -- ─── Final selection ───
    -- select_final receives the probability distribution (not raw
    -- logits) so argmax_weight / weighted_vote operate on a normalized
    -- [0,1] summing-to-1 distribution, matching prior semantics. argmax
    -- over final_theta equals argmax over logits since softmax is a
    -- monotonic transform.
    local selected_idx, answer, orm_scores = select_final(
        particles, final_theta, task, orm_fn, fs_mode)
    if orm_scores ~= nil then total_orm_calls = N end

    -- ─── Assemble result ───
    local final_particles = {}
    for i = 1, N do
        final_particles[i] = {
            answer      = particles[i].partial,
            weight      = final_theta[i],
            step_scores = particles[i].step_scores,
            aggregated  = aggregated[i],
            orm_score   = (orm_scores ~= nil) and orm_scores[i] or nil,
            n_steps     = particles[i].n_steps,
            active      = particles[i].active,
        }
    end

    ctx.result = {
        answer          = answer,
        selected_idx    = selected_idx,
        particles       = final_particles,
        weights         = final_theta,
        steps_executed  = steps_executed,
        resample_count  = resample_count,
        ess_trace       = ess_trace,
        aggregation     = aggregation,
        final_selection = fs_mode,
        stats           = {
            total_llm_calls = total_llm_calls,
            total_prm_calls = total_prm_calls,
            total_orm_calls = total_orm_calls,
        },
    }

    -- ─── Card emission (optional, fail-safe) ───
    if ctx.auto_card then
        local per_particle_list = {}
        for i = 1, N do
            per_particle_list[i] = {
                particle_idx  = i,
                answer        = final_particles[i].answer,
                final_weight  = final_particles[i].weight,
                step_scores   = final_particles[i].step_scores,
                aggregated    = final_particles[i].aggregated,
                orm_score     = final_particles[i].orm_score,
                n_steps       = final_particles[i].n_steps,
            }
        end
        local card_id = emit_card(ctx, ctx.result, per_particle_list)
        ctx.result.card_id = card_id
        if card_id ~= nil and type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.info) == "function" then
            alc.log.info("particle_infer: card emitted — " .. tostring(card_id))
        end
    end

    return ctx
end

-- ─── Test hooks ───
M._internal = {
    aggregate_prm_scores = aggregate_prm_scores,
    softmax_weights      = softmax_weights,
    compute_ess          = compute_ess,
    resample_multinomial = resample_multinomial,
    logit_from_bern      = logit_from_bern,
    log_from_bern        = log_from_bern,
    -- LLM-integrated helpers (mockable via _G.alc stub)
    init_particles       = init_particles,
    advance_step         = advance_step,
    evaluate_prm         = evaluate_prm,
    evaluate_continue    = evaluate_continue,
    select_final         = select_final,
    build_step_prompt    = build_step_prompt,
    emit_card            = emit_card,
}

-- Malli-style self-decoration: wrapper asserts ctx.result against
-- M.spec.entries.run.result ("particle_inferred") when ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
