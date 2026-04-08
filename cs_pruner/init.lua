--- cs_pruner — Confidence-Sequence Partial-Data Pruner
---
--- Given N candidate answers and a D-dimensional rubric, this package
--- evaluates (candidate × dimension) pairs incrementally and KILLS
--- candidates whose anytime-valid upper confidence bound drops below
--- the best surviving candidate's lower confidence bound.
---
--- ### Operating regime — READ FIRST
---
--- Empirical-Bernstein Confidence Sequences are designed for sample
--- sizes in the **hundreds to thousands** (Howard et al. 2021 tune their
--- experiments at t=500). At small N×D scale (N≈6, D≈20) the closed-form
--- variants here CANNOT separate even strong candidates due to a
--- variance-independent floor term in the radius:
---
---   radius_floor(t) ≈ c·k₂·log(ζ/(α·log^s η)) / t
---                   ≈ 0.43 at t=20 with N=6, δ=0.05
---
--- This means a mean-gap of < 0.86 (on a [0,1] scale) is mathematically
--- impossible to detect at t=20 with the polynomial-stitched variant.
--- See workspace/cs_pruner_root_cause.md for the full derivation and
--- workspace/cs_pruner_firing_run{1,2}.md for empirical confirmation.
---
--- Practical guidance:
---   * **Small scale (N×D ≤ 200, D ≤ 30):** Set layer2_halving=true and
---     rely on Successive Halving as the primary kill mechanism. CS acts
---     only as a safety net that almost never fires.
---   * **Medium scale (N≤10, D∈[30,100]):** Try cs_variant="betting" —
---     the predictable plug-in EB CS (Waudby-Smith & Ramdas 2024) is
---     measurably tighter than the stitched variant in this region.
---   * **Large scale (D≥100):** polynomial_stitched is appropriate;
---     CS-driven kills become realistic.
---
--- ### Theoretical foundations
---
--- Three CS variants are bundled:
---
---   "polynomial_stitched"  Howard, Ramdas, McAuliffe, Sekhon 2021,
---                          Theorem 1 eq.(10). Closed-form, robust,
---                          requires t in the hundreds to fire.
---   "hoeffding"            Canonical sub-Gaussian stitched form
---                          (Howard 2021 eq.(10) with c=0), using
---                          worst-case variance σ²=c²/4. Strictly
---                          looser baseline.
---   "betting"              Predictable plug-in empirical-Bernstein CS
---                          from Waudby-Smith & Ramdas (JRSSB 2024,
---                          arXiv:2010.09686, Theorem 2 eq.(13)-(15)).
---                          Uses regularized predictable mean
---                          μ̂_t = (1/2+ΣX)/(t+1) and α = δ/N (the
---                          Thm2 bound is already two-sided).
---   "kl"                   Kaufmann-Cappé style KL-LUCB bounds.
---
--- Why confidence sequences rather than fixed-n CIs:
---   The pruner judges "kill or keep" on-the-fly while rubric scores
---   arrive one dimension at a time. A confidence sequence is
---   time-uniform — it remains valid at every stopping time without
---   pre-committing to a horizon — so early-stop without corrupting
---   the error guarantee.
---
--- Why closed-form variants only: zero external dependencies. The full
--- hedged-capital betting CS (W-S&R Algorithm 1) is tighter still but
--- requires 1D root finding to invert the wealth process; the
--- predictable plug-in form sacrifices ~10-20% width for closed form.
---
--- Key difference from ab_select / gumbel_search / listwise_rank:
---   ab_select      — NO mid-flight kill. Thompson sampling starves
---                    low-posterior candidates implicitly. Explicitly
---                    avoids kill because fixed credible-bound thresholds
---                    are depth-dependent.
---   gumbel_search  — Sequential Halving: "kill bottom half at fixed
---                    checkpoints". Batch, not anytime.
---   listwise_rank  — post-hoc full ranking, no early stop.
---   cs_pruner      — anytime-valid per-candidate kill via empirical
---                    Bernstein CS. Respects statistical guarantees on
---                    the kill probability uniformly over time.
---
--- Algorithm:
---   1. Generate N candidates.
---   2. Round-robin over D rubric dimensions. For each dimension k:
---      for each alive candidate i, ask the judge to evaluate
---      candidate i on dimension k and receive score x ∈ [0, 1].
---      Update candidate i's CS. After each update, recompute
---      best_lcb and kill any candidate whose ucb < best_lcb.
---   3. Return ranking of alive candidates by empirical mean.
---
--- Usage:
---   local cs_pruner = require("cs_pruner")
---   return cs_pruner.run(ctx)
---
--- Parameters (all Strategic / Injectable):
---   ctx.task (required)              Problem statement
---   ctx.n_candidates (default 6)     Number of candidates
---   ctx.rubric (default 20-dim)      List of {name, criterion} dimensions
---   ctx.delta (default 0.05)         Overall error probability upper bound
---   ctx.cs_variant                   "polynomial_stitched" | "hoeffding"
---                                    | "betting" | "kl"
---                                    (default "polynomial_stitched")
---                                    See "Operating regime" above.
---   ctx.betting_lambda_max           Betting λ truncation (default 0.5,
---                                    WSR 2024 §B "reasonable default 1/2 or 3/4").
---   ctx.betting_prior_var            Betting σ̂² prior (default 0.25 = 1/4,
---                                    worst-case variance on [0,1]).
---   ctx.score_domain                 { min, max } (default { 0, 1 })
---   ctx.stitching_s (default 1.4)    Howard 2021 eq.(10) exponent
---   ctx.stitching_eta (default 2.0)  Howard 2021 eq.(10) epoch ratio
---   ctx.bootstrap_m (default 1.0)    Howard 2021 eq.(10) bootstrap time
---   ctx.aggregation (default         Only "scalarize" is supported.
---                   "scalarize")     Any other value is rejected at run time.
---   ctx.weights (default nil)        Per-dimension weights, nil = uniform
---   ctx.eval_order                   "round_robin" | "sequential" |
---                                    function(state) -> (cand_i, dim_k)
---                                    (default "round_robin")
---   ctx.layer2_halving               true | false (default false)
---   ctx.halving_checkpoints          list of n values (default {5, 10, 15})
---   ctx.halving_keep_ratio (0.5)     Fraction kept at each halving
---   ctx.halving_min_gap (0)          Gap guard. A candidate in the bottom
---                                    slice is PROTECTED (not killed) if its
---                                    mean is within min_gap of the median
---                                    of alive candidates. Mitigates the
---                                    noise-driven false-kill failure mode at
---                                    low n. Recommended: 0.1-0.2 on a [0,1]
---                                    scale. See workspace/cs_pruner_firing_run2.md.
---   ctx.on_kill                      function(candidate_index, state)
---   ctx.on_survive                   function(candidate_index, state)
---   ctx.gen_tokens (default 400)     Max tokens per candidate generation
---   ctx.min_n_before_kill            Warmup minimum (default 3 for
---                                    stitched/hoeffding/betting, 5 for
---                                    cs_variant="kl"). KL bounds can
---                                    fire spuriously at n≤4 with binary
---                                    PASS/FAIL scores.
---
--- Based on:
---   Howard, Ramdas, McAuliffe, Sekhon (2021)
---     "Time-uniform, nonparametric, nonasymptotic confidence sequences"
---     Annals of Statistics 49(2):1055-1080. arXiv:1810.08240
---   Waudby-Smith & Ramdas (2024)
---     "Estimating means of bounded random variables by betting"
---     JRSS-B 86(1):1-27. arXiv:2010.09686 (Theorem 2, predictable
---     plug-in empirical-Bernstein CS)

local M = {}

---@type AlcMeta
M.meta = {
    name = "cs_pruner",
    version = "0.1.0",
    description = "Confidence-sequence partial-data pruner. Anytime-valid "
        .. "per-candidate kill using empirical-Bernstein CS "
        .. "(Howard et al. 2021). Evaluates candidates across a "
        .. "multi-dimensional rubric and kills each one as soon as its "
        .. "upper confidence bound drops below the best survivor's "
        .. "lower bound. Strategic/Injectable — every parameter is "
        .. "overridable.",
    category = "selection",
}

-- Riemann zeta(1.4) ≈ 3.10555 — used as default in Howard 2021 eq.(10)
-- with s = 1.4. Pre-computed since 1.4 is the paper's Figure 7 recommendation.
-- For other s values the user must override stitching_s and accept that the
-- radius constant is approximate.
local ZETA_S14 = 3.10555

-- ─── Default 20-dimension rubric ─────────────────────────────────────────
-- Binary PASS/FAIL criteria. Users will typically override this with a
-- task-specific rubric, but the default is sufficient to evaluate generic
-- quality on any open-ended task.

local DEFAULT_RUBRIC = {
    { name = "factual_accuracy",  criterion = "The answer contains no factual errors." },
    { name = "completeness",      criterion = "The answer addresses all parts of the task." },
    { name = "relevance",         criterion = "The answer is directly relevant to the task." },
    { name = "clarity",           criterion = "The answer is clearly and unambiguously expressed." },
    { name = "coherence",         criterion = "The answer is logically coherent and well-structured." },
    { name = "specificity",       criterion = "The answer is specific rather than vague." },
    { name = "reasoning_depth",   criterion = "The answer shows adequate depth of reasoning." },
    { name = "no_hallucination",  criterion = "The answer does not fabricate information." },
    { name = "appropriate_length",criterion = "The answer is neither too short nor padded." },
    { name = "grammar",           criterion = "The answer is grammatically correct." },
    { name = "terminology",       criterion = "Technical terminology is used correctly." },
    { name = "organization",      criterion = "The answer is well organized." },
    { name = "all_parts",         criterion = "No part of the task is ignored." },
    { name = "concrete_examples", criterion = "Concrete examples or details support the answer." },
    { name = "no_redundancy",     criterion = "The answer avoids unnecessary repetition." },
    { name = "tone",              criterion = "The tone is appropriate for the task." },
    { name = "no_contradictions", criterion = "The answer contains no internal contradictions." },
    { name = "qualified_claims",  criterion = "Claims are appropriately qualified." },
    { name = "actionable",        criterion = "The answer provides actionable insight where relevant." },
    { name = "edge_cases",        criterion = "The answer considers relevant edge cases." },
}

local RUBRIC_PROMPT = "Task: %s\n\nCandidate answer:\n%s\n\n"
    .. "Evaluate ONE specific criterion:\nCriterion: %s\n\n"
    .. "Reply with ONLY 'PASS' if the criterion is satisfied, "
    .. "or 'FAIL' if not."

--- Parse a PASS/FAIL rubric response. Falls back to numeric score if the
--- judge emits a number. Errors on total failure to avoid silent zero
--- (which would systematically starve the candidate's CS update).
local function parse_rubric_score(raw)
    local upper = tostring(raw):upper()
    if upper:match("PASS") then return 1.0 end
    if upper:match("FAIL") then return 0.0 end
    local n = alc.parse_score(raw)
    if n then return n end
    error("cs_pruner: cannot parse rubric response: " .. tostring(raw):sub(1, 200), 2)
end

-- ─── Empirical-Bernstein Confidence Sequence ─────────────────────────────
-- Howard, Ramdas, McAuliffe, Sekhon (2021) Theorem 1 eq.(10),
-- polynomial-stitched variant.
--
-- Given observations X_1, ..., X_t ∈ [a, b] with predictable predictor
-- X̂_i = (i-1)^{-1} Σ_{j<i} X_j (running past mean; X̂_1 = (a+b)/2),
-- and empirical variance V̂_t = Σ (X_i - X̂_i)²,
--
--     radius(t, V̂_t) = (1/t) [ k1 · √((V̂_t ∨ m) · ℓ) + c · k2 · ℓ ]
--     ℓ = s · loglog(η · (V̂_t ∨ m) / m) + log(ζ(s) / (α · log^s η))
--     k1 = (η^(1/4) + η^(-1/4)) / √2
--     k2 = (√η + 1) / 2
--     c  = b - a
--
-- Coverage: P(∀t ≥ 1: |X̄_t - μ| < radius) ≥ 1 - 2α.
-- For one-sided use in kill decisions we apply Bonferroni 2N over
-- candidates × sides: α = δ / (2N).
--
-- Numerical care:
-- * The loglog term can be non-positive when η·v/m < e. In that regime
--   the log argument is ≤ 1, so loglog becomes ≤ 0. We clip it to 0 —
--   the second term log(ζ(s)/(α log^s η)) dominates at small t and
--   keeps ℓ > 0. This does not break the bound; it only adds slack.
-- * When V̂_t = 0 (e.g., all rubric scores identical so far),
--   (V̂_t ∨ m) = m > 0 so sqrt is well-defined.

local function compute_zeta(s)
    if math.abs(s - 1.4) < 1e-9 then return ZETA_S14 end
    local zeta_s = 0
    for k = 1, 200 do zeta_s = zeta_s + 1 / (k ^ s) end
    return zeta_s
end

local function poly_stitched_radius(t, v_hat, c, alpha, s, eta, m, zeta_s)
    local v = v_hat > m and v_hat or m
    local k1 = (eta ^ 0.25 + eta ^ -0.25) / math.sqrt(2)
    local k2 = (math.sqrt(eta) + 1) / 2
    local inner = eta * v / m
    local log_inner = math.log(inner)
    local loglog_term
    if log_inner > 1 then
        loglog_term = math.log(log_inner)
    else
        loglog_term = 0
    end
    local log_eta_s = math.log(eta) ^ s
    local ell = s * loglog_term + math.log(zeta_s / (alpha * log_eta_s))
    if ell < 0 then ell = 0 end
    return (k1 * math.sqrt(v * ell) + c * k2 * ell) / t
end

--- Hoeffding anytime-valid CS — canonical sub-Gaussian polynomial-stitched
--- form from Howard et al. 2021, i.e. eq.(10) specialized to c = 0.
---
--- For X_i ∈ [a, b], (X_i − μ) is (c/2)-sub-Gaussian with c = b − a
--- (Hoeffding's lemma). The associated variance process is the
--- deterministic V_t = t·(c/2)² = t·c²/4 and the sub-Gaussian stitched
--- boundary drops the linear `c·k₂·ℓ` correction (Howard 2021 p.7,
--- footnote: "the second term is neglected in the sub-Gaussian case since
--- c = 0"). The resulting radius on the mean is
---
---     radius(t) = k1 · √( (V_t ∨ m) · ℓ(V_t ∨ m) ) / t
---
--- with the same ℓ, k1 constants as poly_stitched_radius. The `_v_hat`
--- argument is accepted to keep a uniform radius_fn signature with
--- poly_stitched_radius; the Hoeffding variant deliberately ignores the
--- empirical variance because it uses the worst-case deterministic
--- variance proxy.
local function hoeffding_radius(t, _v_hat, c, alpha, s, eta, m, zeta_s)
    local v = (c * c / 4) * t
    if v < m then v = m end
    local k1 = (eta ^ 0.25 + eta ^ -0.25) / math.sqrt(2)
    local inner = eta * v / m
    local log_inner = math.log(inner)
    local loglog_term = log_inner > 1 and math.log(log_inner) or 0
    local log_eta_s = math.log(eta) ^ s
    local ell = s * loglog_term + math.log(zeta_s / (alpha * log_eta_s))
    if ell < 0 then ell = 0 end
    return k1 * math.sqrt(v * ell) / t
end

-- ─── Predictable Plug-in Empirical-Bernstein CS (betting) ───────────────
-- Waudby-Smith & Ramdas (2024) "Estimating means of bounded random
-- variables by betting", JRSS-B 86(1):1-27, arXiv:2010.09686 (v7), Theorem 2
-- together with the predictable plug-in λ of eq.(15).
--
-- Verbatim from the paper (p.10):
--
--   v_i      := 4·(X_i − μ̂_{i−1})²                            -- eq.(13)
--   ψ_E(λ)   := (−log(1 − λ) − λ) / 4      for λ ∈ [0, 1)      -- eq.(14)
--
-- The (1 − α)-CS is then (Theorem 2):
--
--   C_t^{PrPl-EB} =  Σ λ_i X_i / Σ λ_i  ±  (log(2/α) + Σ v_i·ψ_E(λ_i)) / Σ λ_i
--
-- Note that v_i·ψ_E(λ_i) = (X_i − μ̂_{i−1})² · (−log(1 − λ_i) − λ_i)
-- because the factor 4 in v_i and the divisor 4 in ψ_E cancel. We inline
-- this cancellation in the aggregates below so that `betting_psi` returns
-- the un-normalized `−log(1 − λ) − λ` and the squared-diff aggregate is
-- the raw (X_i − μ̂_{i−1})² with no extra factor.
--
-- Predictable plug-in λ (eq.(15)), verbatim:
--
--   λ_t  = √( 2 · log(2/α) / ( σ̂²_{t−1} · t · log(1 + t) ) ) ∧ c
--   σ̂²_t = ( 1/4 + Σ_{i=1}^t (X_i − μ̂_i)² ) / ( t + 1 )
--   μ̂_t  = ( 1/2 + Σ_{i=1}^t X_i ) / ( t + 1 )
--
-- with c ∈ (0, 1) (paper states "a reasonable default being 1/2 or 3/4").
-- We default to c = 1/2 which gives ψ_E(1/2) = log(2) − 1/2 ≈ 0.193, and
-- we also default the 1/4 variance prior from eq.(15) literally. Both
-- constants are overridable via ctx.betting_lambda_max /
-- ctx.betting_prior_var in M.run to allow experimentation per paper
-- §3.3 guidance.
--
-- Two subtly different regularized means appear in eq.(15):
--   * μ̂_{i−1} used inside v_i is the *predictable* (1/2 + Σ_{j<i} X_j)/i
--     — F_{i−1}-measurable, does NOT include X_i. Used to compute the
--     radius aggregate s_psi_v.
--   * μ̂_i used inside σ̂²_t is the *current* (1/2 + Σ_{j≤i} X_j)/(i+1)
--     — includes X_i. Used only to feed λ's predictable plug-in on the
--     NEXT step, so σ̂²_{t−1} aggregates (X_j − μ̂_j)² for j < t.
--
-- We track these two sums separately (sigma_sum vs s_psi_v) so the code
-- matches eq.(15) exactly rather than reusing the stitched variant's
-- v_hat.
--
-- Domain: this implementation assumes c = 1 (score_domain = {0,1}).
-- For general [a, b] the inputs would need to be normalized; that
-- generalization is left to v0.2.

local BETTING_LAMBDA_MAX_DEFAULT = 0.5   -- c in eq.(15); paper: 1/2 or 3/4
local BETTING_PRIOR_VAR_DEFAULT  = 0.25  -- 1/4 variance prior in eq.(15)

local function betting_lambda(prev_sigma_sum, i, log_2_alpha, lambda_max, prior_var)
    -- σ̂²_{t−1} = (prior_var + Σ_{j<t}(X_j − μ̂_j)²) / t  where t = i
    local sigma2_hat = (prior_var + prev_sigma_sum) / i
    local denom = sigma2_hat * i * math.log(i + 1)
    if denom <= 0 then return lambda_max end
    local lam = math.sqrt(2 * log_2_alpha / denom)
    if lam > lambda_max then lam = lambda_max end
    if lam <= 0 then lam = 1e-6 end
    return lam
end

local function betting_psi(lam)
    -- Un-normalized ψ_E·4 = −log(1−λ) − λ. The /4 of paper eq.(14) is
    -- cancelled by the factor 4 inside v_i := 4·(X − μ̂_{i−1})² when
    -- computing v_i·ψ_E(λ). See the doc block above.
    return -math.log(1 - lam) - lam
end

-- ─── KL-LUCB bounds (Kaufmann & Kalyanakrishnan 2013) ──────────────────
-- For bounded observations X ∈ [0, 1], the KL confidence bounds are
--
--   upper(n, μ̂) = max{ q ∈ [μ̂, 1] : n · d(μ̂, q) ≤ ℓ }
--   lower(n, μ̂) = min{ q ∈ [0, μ̂] : n · d(μ̂, q) ≤ ℓ }
--
-- where d(p, q) = p log(p/q) + (1 - p) log((1 - p)/(1 - q)) is the
-- Bernoulli KL divergence (valid as an upper bound on the KL of any
-- [0,1]-bounded distribution via Pinsker-type dominance, per Garivier &
-- Cappé 2011 Lemma 3).
--
-- Exploration rate: we use the Kaufmann-Cappé 2013 ("On the Complexity
-- of Best-Arm Identification in Multi-Armed Bandit Models", JMLR 17)
-- kl-UCB+ style anytime form, rewritten in per-δ (rather than per-t)
-- parameterization:
--   ℓ(n) = log(1/α) + 3 · log(max(1, log(n)))
-- where α = δ/(2N) is the per-side Bonferroni-corrected confidence
-- (inherited from the rest of cs_pruner). The 3·log log term is the
-- standard LIL-type inflation required for time-uniform validity of
-- KL confidence bounds (Kaufmann-Cappé 2013 Theorem 10; the constant
-- 3 is the smallest integer for which their proof goes through).
--
-- The bounds are solved by bisection (40 iterations → < 1e-12 precision
-- on the KL level set, which is monotone in q on either side of μ̂).
--
-- Why KL-LUCB for small t, 0/1-near regimes:
--   For rubric scores that live near 0 or 1 (PASS/FAIL), d(μ̂, q) is
--   much larger than 2·(μ̂-q)² (the Pinsker lower bound), so the KL
--   bound is strictly tighter than the Hoeffding/Howard stitched form.
--   At μ̂=1, n=20, α=0.0083:
--     radius_KL  ≈ 0.087      (this implementation)
--     radius_H21 ≈ 0.43       (poly-stitched floor)
--   → KL is ~5× tighter in the regime where cs_pruner is normally
--   operated with PASS/FAIL rubrics.
--
-- Domain: this implementation assumes score_domain = {0, 1}. General
-- [a, b] is left to v0.2 (would require pre-normalization plus a KL
-- dominance adjustment).

local KL_EPS = 1e-12

local function kl_bern(p, q)
    -- Clip to avoid log(0). The bisection never targets the clipped
    -- endpoints exactly because we saturate at q = 1 - KL_EPS / KL_EPS.
    if p < KL_EPS then p = KL_EPS end
    if p > 1 - KL_EPS then p = 1 - KL_EPS end
    if q < KL_EPS then q = KL_EPS end
    if q > 1 - KL_EPS then q = 1 - KL_EPS end
    return p * math.log(p / q) + (1 - p) * math.log((1 - p) / (1 - q))
end

local function kl_upper_bound(p_hat, n, ell)
    if n == 0 then return 1 end
    local target = ell / n
    -- If even q → 1 does not exceed target, the upper bound is the
    -- domain maximum.
    if kl_bern(p_hat, 1 - KL_EPS) <= target then return 1 end
    local lo, hi = p_hat, 1 - KL_EPS
    for _ = 1, 40 do
        local mid = (lo + hi) * 0.5
        if kl_bern(p_hat, mid) <= target then lo = mid else hi = mid end
    end
    return lo
end

local function kl_lower_bound(p_hat, n, ell)
    if n == 0 then return 0 end
    local target = ell / n
    if kl_bern(p_hat, KL_EPS) <= target then return 0 end
    local lo, hi = KL_EPS, p_hat
    for _ = 1, 40 do
        local mid = (lo + hi) * 0.5
        if kl_bern(p_hat, mid) <= target then hi = mid else lo = mid end
    end
    return hi
end

local CS_VARIANTS = {
    polynomial_stitched = poly_stitched_radius,
    hoeffding = hoeffding_radius,
    betting = "BETTING_SENTINEL", -- dispatched specially in compute_bounds
    kl      = "KL_SENTINEL",      -- dispatched specially in compute_bounds
}

-- ─── Per-candidate CS state ──────────────────────────────────────────────

local function new_state(a)
    return {
        n = 0,
        sum = 0,
        v_hat = 0,
        last_x_hat = (a + 0.5), -- initialized below; see init_state
        alive = true,
        scores = {},
        -- Betting variant aggregates (only used when cs_variant=="betting")
        s_lambda = 0,
        s_lambda_x = 0,
        s_psi_v = 0,
        -- Σ_{j≤n}(X_j − μ̂_j)² with μ̂_j = (1/2 + Σ_{k≤j} X_k)/(j+1)
        -- — the "regularized current mean" squared-error sum used by
        -- paper eq.(15)'s σ̂²_t. Distinct from v_hat which tracks the
        -- predictable-past-mean squared errors used by the stitched
        -- variants. Betting-only.
        sigma_sum = 0,
    }
end

--- Standard update (used by polynomial_stitched and hoeffding variants).
local function update_state(st, x, a, b)
    local x_hat
    if st.n == 0 then
        x_hat = (a + b) / 2
    else
        x_hat = st.sum / st.n
    end
    local diff = x - x_hat
    st.v_hat = st.v_hat + diff * diff
    st.sum = st.sum + x
    st.n = st.n + 1
    st.scores[#st.scores + 1] = x
end

--- Betting update: computes a predictable λ_t from σ̂²_{t−1} (paper
--- eq.(15)), then updates the four running aggregates needed for the
--- Theorem 2 CS:
---   s_lambda    = Σ λ_i
---   s_lambda_x  = Σ λ_i X_i
---   s_psi_v     = Σ (−log(1−λ_i) − λ_i)·(X_i − μ̂_{i−1})²
---                = Σ v_i·ψ_E(λ_i)   (with factor-4 cancellation inlined)
--- where μ̂_{i−1} = (1/2 + Σ_{j<i} X_j)/i is the *predictable* regularized
--- mean from eq.(15).
--- It also accumulates sigma_sum = Σ_{j≤t}(X_j − μ̂_j)² where μ̂_j is the
--- *current* regularized mean (1/2 + Σ_{k≤j} X_k)/(j+1). This feeds
--- λ_{t+1}'s σ̂²_t via eq.(15).
--- Assumes c = 1 (score_domain = {0, 1}).
local function update_state_betting(st, x, alpha, lambda_max, prior_var)
    local i = st.n + 1  -- step index t
    -- Paper eq.(15): μ̂_{t-1} = (1/2 + Σ_{j<t} X_j) / t   (predictable)
    local mu_prev = (0.5 + st.sum) / i
    -- Paper eq.(15): σ̂²_{t-1} = (1/4 + Σ_{j<t}(X_j − μ̂_j)²) / t
    --                          = (prior_var + sigma_sum_so_far) / t
    local prev_sigma_sum = st.sigma_sum
    local log_2_alpha = math.log(2 / alpha)
    local lam = betting_lambda(prev_sigma_sum, i, log_2_alpha, lambda_max, prior_var)
    local psi = betting_psi(lam)
    local diff_pred = x - mu_prev                 -- predictable diff for v_i
    st.s_lambda   = st.s_lambda   + lam
    st.s_lambda_x = st.s_lambda_x + lam * x
    st.s_psi_v    = st.s_psi_v    + psi * diff_pred * diff_pred
    -- Commit the observation
    st.sum = st.sum + x
    st.n   = i
    -- Paper eq.(15): μ̂_t = (1/2 + Σ_{j≤t} X_j) / (t+1)   (current)
    local mu_curr = (0.5 + st.sum) / (i + 1)
    local diff_curr = x - mu_curr
    st.sigma_sum = st.sigma_sum + diff_curr * diff_curr
    -- Keep v_hat consistent with predictable-diff accounting so that any
    -- reporting path (e.g. stitched-style ranking) stays well-defined.
    st.v_hat = st.v_hat + diff_pred * diff_pred
    st.scores[#st.scores + 1] = x
end

local function mean(st)
    if st.n == 0 then return 0.5 end
    return st.sum / st.n
end

-- ─── Run ─────────────────────────────────────────────────────────────────

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_cand = ctx.n_candidates or 6
    local rubric = ctx.rubric or DEFAULT_RUBRIC
    local delta = ctx.delta or 0.05
    local cs_variant = ctx.cs_variant or "polynomial_stitched"
    local score_domain = ctx.score_domain or { min = 0, max = 1 }
    local a, b = score_domain.min, score_domain.max
    local c = b - a
    local s_param = ctx.stitching_s or 1.4
    local eta_param = ctx.stitching_eta or 2.0
    local m_param = ctx.bootstrap_m or 1.0
    local aggregation = ctx.aggregation or "scalarize"
    local eval_order = ctx.eval_order or "round_robin"
    local layer2 = ctx.layer2_halving or false
    local checkpoints = ctx.halving_checkpoints or { 5, 10, 15 }
    local keep_ratio = ctx.halving_keep_ratio or 0.5
    local min_gap = ctx.halving_min_gap or 0
    local on_kill = ctx.on_kill
    local on_survive = ctx.on_survive
    local gen_tokens = ctx.gen_tokens or 400
    -- Default warmup: 3 for stitched/hoeffding/betting, 5 for KL.
    -- KL bounds degenerate at small n with binary PASS/FAIL scores
    -- (μ̂ ∈ {0, 1}) and can fire spuriously.
    local default_min_n = (ctx.cs_variant == "kl") and 5 or 3
    local min_n = ctx.min_n_before_kill or default_min_n
    -- Betting variant Injectable constants. Paper (WSR 2024 eq.(15))
    -- suggests c ∈ {1/2, 3/4} as defaults and uses a literal 1/4 prior
    -- on the variance. Both are overridable.
    local betting_lambda_max = ctx.betting_lambda_max or BETTING_LAMBDA_MAX_DEFAULT
    local betting_prior_var  = ctx.betting_prior_var  or BETTING_PRIOR_VAR_DEFAULT

    if n_cand < 2 then error("cs_pruner: ctx.n_candidates must be >= 2", 2) end
    if delta <= 0 or delta >= 1 then error("cs_pruner: ctx.delta must be in (0,1)", 2) end
    if type(min_gap) ~= "number" or min_gap < 0 then
        error("cs_pruner: ctx.halving_min_gap must be a non-negative number", 2)
    end
    if c <= 0 then error("cs_pruner: score_domain.max must exceed .min", 2) end
    if aggregation ~= "scalarize" then
        error("cs_pruner: only aggregation=\"scalarize\" is supported", 2)
    end
    local radius_fn = CS_VARIANTS[cs_variant]
    if radius_fn == nil then
        error("cs_pruner: unknown cs_variant: " .. tostring(cs_variant), 2)
    end
    local is_betting = (cs_variant == "betting")
    if is_betting and (a ~= 0 or b ~= 1) then
        error(
            "cs_pruner: cs_variant=\"betting\" requires score_domain={min=0,max=1} in v0.1",
            2
        )
    end
    local is_kl = (cs_variant == "kl")
    if is_kl and (a ~= 0 or b ~= 1) then
        error(
            "cs_pruner: cs_variant=\"kl\" requires score_domain={min=0,max=1} in v0.1",
            2
        )
    end
    if eval_order ~= "round_robin"
        and eval_order ~= "sequential"
        and type(eval_order) ~= "function" then
        error("cs_pruner: unknown eval_order: " .. tostring(eval_order), 2)
    end
    if type(betting_lambda_max) ~= "number"
        or betting_lambda_max <= 0 or betting_lambda_max >= 1 then
        error("cs_pruner: ctx.betting_lambda_max must be in (0, 1)", 2)
    end
    if type(betting_prior_var) ~= "number" or betting_prior_var <= 0 then
        error("cs_pruner: ctx.betting_prior_var must be a positive number", 2)
    end

    -- Per-candidate CS miscoverage budget α. Two regimes:
    --
    -- * polynomial_stitched / hoeffding / kl: Howard 2021 Thm.1 gives a
    --   one-sided crossing probability α, and we take a union bound over
    --   both sides AND the N candidates, so α = δ / (2N). The kl variant
    --   reuses this because it solves two one-sided KL level sets at
    --   level α each.
    --
    -- * betting: WSR 2024 Thm.2 already delivers a two-sided
    --   (1 − α)-CS via the ±radius form. A union bound over N
    --   candidates therefore only needs α = δ / N. Using δ / (2N) here
    --   would be a gratuitous factor-of-2 over-conservatism.
    local alpha = delta / (2 * n_cand)
    local alpha_betting = delta / n_cand
    local zeta_s = compute_zeta(s_param)

    local D = #rubric

    -- ── Phase 1: Generate candidates (true parallel via alc.parallel) ──
    local cand_indices = {}
    for i = 1, n_cand do cand_indices[i] = i end
    local candidates = alc.parallel(cand_indices, function(i)
        return {
            prompt = string.format(
                "Task: %s\n\nProvide your best answer. Be specific and complete.",
                task
            ),
            system = string.format(
                "You are expert #%d. Give a thorough answer that may "
                    .. "differ in approach from others.", i
            ),
            max_tokens = gen_tokens,
        }
    end)

    alc.log("info", string.format("cs_pruner: generated %d candidates", n_cand))

    -- ── Phase 2: Per-candidate state ──
    local states = {}
    for i = 1, n_cand do
        states[i] = new_state(a)
    end

    local rounds = {}
    local kill_events = {}
    local protect_events = {}
    local evals_done = 0

    local function compute_bounds(st)
        if is_betting then
            if st.n == 0 or st.s_lambda <= 0 then
                return -math.huge, math.huge, 0.5, math.huge
            end
            local center = st.s_lambda_x / st.s_lambda
            local log_2_alpha = math.log(2 / alpha_betting)
            local r = (log_2_alpha + st.s_psi_v) / st.s_lambda
            return center - r, center + r, center, r
        end
        if is_kl then
            if st.n == 0 then
                return -math.huge, math.huge, 0.5, math.huge
            end
            local mu_hat = mean(st)
            -- Kaufmann-Cappé 2013 Thm.10: ℓ = log(1/α) + 3·log(max(1,log n))
            local log_n = math.log(st.n)
            if log_n < 1 then log_n = 1 end
            local ell = math.log(1 / alpha) + 3 * math.log(log_n)
            local upper = kl_upper_bound(mu_hat, st.n, ell)
            local lower = kl_lower_bound(mu_hat, st.n, ell)
            return lower, upper, mu_hat, (upper - lower) * 0.5
        end
        local mu = mean(st)
        local r = radius_fn(st.n, st.v_hat, c, alpha, s_param, eta_param, m_param, zeta_s)
        return mu - r, mu + r, mu, r
    end

    local function kill_check(trigger_iter)
        local cache = {}
        local best_lcb = -math.huge
        for i = 1, n_cand do
            local st = states[i]
            if st.alive and st.n >= min_n then
                local lcb, ucb, mu, r = compute_bounds(st)
                cache[i] = { lcb = lcb, ucb = ucb, mu = mu, r = r }
                if lcb > best_lcb then best_lcb = lcb end
            end
        end
        for i = 1, n_cand do
            local st = states[i]
            local c_ = cache[i]
            if st.alive and c_ then
                if c_.ucb < best_lcb then
                    st.alive = false
                    local lcb2, ucb2, mu2, r2 = c_.lcb, c_.ucb, c_.mu, c_.r
                    kill_events[#kill_events + 1] = {
                        candidate = i,
                        iteration = trigger_iter,
                        n = st.n,
                        mean = mu2,
                        lcb = lcb2,
                        ucb = ucb2,
                        radius = r2,
                        best_lcb = best_lcb,
                    }
                    alc.log("info", string.format(
                        "cs_pruner: kill cand #%d at n=%d (ucb=%.3f < best_lcb=%.3f)",
                        i, st.n, ucb2, best_lcb
                    ))
                    if on_kill then on_kill(i, states[i]) end
                end
            end
        end
    end

    -- ─── Layer-2 Successive Halving (with optional gap guard) ───
    -- At each configured checkpoint, sort alive candidates by mean and
    -- mark the bottom (1 - keep_ratio) fraction as kill candidates. The
    -- optional `min_gap` guard then PROTECTS any candidate whose mean is
    -- within `min_gap` of the median: such candidates are NOT killed even
    -- though they are in the bottom slice. This trades a slower kill rate
    -- for protection against the noise-driven false-kill failure mode
    -- (see workspace/cs_pruner_firing_run2.md — C6 case).
    --
    -- Recommended usage for small N×D regimes:
    --   layer2_halving = true,
    --   halving_checkpoints = { 5, 10, 15 },   -- staged, not one-shot
    --   halving_keep_ratio  = 0.66,             -- gentle: drop bottom 33%
    --   halving_min_gap     = 0.15,             -- protect borderline cands
    --
    -- The "recovery" effect comes from staging: a candidate that survives
    -- a noisy early checkpoint by virtue of the gap guard accumulates
    -- more observations before the next checkpoint, and only loses if
    -- its disadvantage actually persists at the larger sample size.

    -- Track which checkpoints have fired so we never re-trigger a
    -- checkpoint in non-round_robin eval_orders where `current_n` may
    -- advance past a checkpoint without landing on it exactly.
    local halving_hit = {}

    local function do_halving(current_n)
        local alive_list = {}
        for i = 1, n_cand do
            if states[i].alive then
                alive_list[#alive_list + 1] = { i = i, mu = mean(states[i]) }
            end
        end
        if #alive_list <= 1 then return end
        table.sort(alive_list, function(x, y) return x.mu > y.mu end)

        -- Median of alive candidates (used by gap guard).
        local median_mu
        local mid = #alive_list / 2
        if mid == math.floor(mid) then
            median_mu = (alive_list[mid].mu + alive_list[mid + 1].mu) / 2
        else
            median_mu = alive_list[math.ceil(mid)].mu
        end

        local keep = math.ceil(#alive_list * keep_ratio)
        if keep < 1 then keep = 1 end
        for k = keep + 1, #alive_list do
            local idx = alive_list[k].i
            local mu_k = alive_list[k].mu
            -- Gap guard: protect candidates close to the median.
            if min_gap > 0 and (median_mu - mu_k) < min_gap then
                protect_events[#protect_events + 1] = {
                    candidate = idx,
                    reason = "layer2_halving_protected",
                    n = states[idx].n,
                    mean = mu_k,
                    median = median_mu,
                    gap = median_mu - mu_k,
                    min_gap = min_gap,
                    checkpoint = current_n,
                }
                alc.log("info", string.format(
                    "cs_pruner: layer2 protect cand #%d at checkpoint n=%d "
                        .. "(gap=%.3f < min_gap=%.3f)",
                    idx, current_n, median_mu - mu_k, min_gap
                ))
            else
                states[idx].alive = false
                kill_events[#kill_events + 1] = {
                    candidate = idx,
                    iteration = -1,
                    reason = "layer2_halving",
                    n = states[idx].n,
                    mean = mu_k,
                    median = median_mu,
                    gap = median_mu - mu_k,
                    checkpoint = current_n,
                }
                alc.log("info", string.format(
                    "cs_pruner: layer2 halving drop cand #%d at checkpoint n=%d",
                    idx, current_n
                ))
                if on_kill then on_kill(idx, states[idx]) end
            end
        end
    end

    --- Fire any unhit halving checkpoints that the slowest alive
    --- candidate has now reached. Used by every eval_order branch so
    --- that layer-2 halving is not silently disabled in `sequential`
    --- and function-generator modes.
    local function halving_check()
        if not layer2 then return end
        local min_n_alive = math.huge
        for i = 1, n_cand do
            if states[i].alive and states[i].n < min_n_alive then
                min_n_alive = states[i].n
            end
        end
        if min_n_alive == math.huge then return end
        for _, cp in ipairs(checkpoints) do
            if (not halving_hit[cp]) and min_n_alive >= cp then
                halving_hit[cp] = true
                do_halving(cp)
            end
        end
    end

    -- ── Phase 3: Evaluation loop ──
    -- eval_order = "round_robin": outer loop dimensions, inner loop alive candidates.
    -- eval_order = "sequential": outer loop candidates, inner loop dimensions.
    -- eval_order = function: user supplies (cand_i, dim_k) generator.

    local iter = 0

    local function count_alive()
        local c_ = 0
        for i = 1, n_cand do if states[i].alive then c_ = c_ + 1 end end
        return c_
    end

    local function llm_eval(i, k)
        local dim = rubric[k]
        return alc.llm(
            string.format(RUBRIC_PROMPT, task, candidates[i], dim.criterion),
            {
                system = "You are a rigorous evaluator. Reply with only PASS or FAIL.",
                max_tokens = 10,
            }
        )
    end

    local function apply_eval(i, k, raw)
        iter = iter + 1
        local dim = rubric[k]
        local x_raw = parse_rubric_score(raw)
        -- Normalize to [a, b]. parse_rubric_score returns {0, 1} for PASS/FAIL
        -- or an LLM number which we assume is already in [a, b].
        local x
        if x_raw == 0 or x_raw == 1 then
            x = a + x_raw * c
        else
            x = x_raw
            if x < a then x = a end
            if x > b then x = b end
        end
        if is_betting then
            update_state_betting(states[i], x, alpha_betting,
                betting_lambda_max, betting_prior_var)
        else
            update_state(states[i], x, a, b)
        end
        evals_done = evals_done + 1
        rounds[#rounds + 1] = {
            iteration = iter,
            candidate = i,
            dimension = k,
            dimension_name = dim.name,
            score = x,
            n_after = states[i].n,
            v_hat_after = states[i].v_hat,
            mean_after = mean(states[i]),
        }
    end

    local function eval_one(i, k)
        local raw = llm_eval(i, k)
        apply_eval(i, k, raw)
    end

    if eval_order == "round_robin" then
        for k = 1, D do
            -- Parallel: collect alive candidates for this dim, eval together
            local alive_now = {}
            for i = 1, n_cand do
                if states[i].alive then
                    alive_now[#alive_now + 1] = i
                end
            end
            if #alive_now > 0 then
                local dim = rubric[k]
                local raws = alc.parallel(alive_now, function(i)
                    return {
                        prompt = string.format(RUBRIC_PROMPT, task, candidates[i], dim.criterion),
                        system = "You are a rigorous evaluator. Reply with only PASS or FAIL.",
                        max_tokens = 10,
                    }
                end)
                for idx, i in ipairs(alive_now) do
                    apply_eval(i, k, raws[idx])
                end
                kill_check(iter)
            end
            halving_check()
            if count_alive() <= 1 then break end
        end
    elseif eval_order == "sequential" then
        for i = 1, n_cand do
            if count_alive() <= 1 then break end
            if states[i].alive then
                for k = 1, D do
                    eval_one(i, k)
                    kill_check(iter)
                    halving_check()
                    if not states[i].alive then break end
                    if count_alive() <= 1 then break end
                end
            end
        end
    else
        -- User-supplied generator: function(state) -> (i, k) or nil to stop
        local gen_state = { rubric_size = D, n_candidates = n_cand, states = states }
        while true do
            if count_alive() <= 1 then break end
            local i, k = eval_order(gen_state)
            if i == nil then break end
            if states[i].alive then
                eval_one(i, k)
                kill_check(iter)
                halving_check()
            end
        end
    end

    -- ── Phase 4: Rank survivors ──
    local ranking = {}
    for i = 1, n_cand do
        local st = states[i]
        local lcb, ucb, mu, r = 0, 0, 0, 0
        if st.n > 0 then
            lcb, ucb, mu, r = compute_bounds(st)
        end
        ranking[#ranking + 1] = {
            index = i,
            alive = st.alive,
            n = st.n,
            mean = mu,
            lcb = lcb,
            ucb = ucb,
            radius = r,
            v_hat = st.v_hat,
        }
        if st.alive and on_survive then on_survive(i, st) end
    end
    table.sort(ranking, function(x, y)
        if x.alive ~= y.alive then return x.alive end
        return x.mean > y.mean
    end)

    local best = ranking[1]
    local alive_count = 0
    for _, r in ipairs(ranking) do if r.alive then alive_count = alive_count + 1 end end

    alc.log("info", string.format(
        "cs_pruner: winner=#%d (mean=%.3f, n=%d), %d alive of %d, %d evals, %d kills",
        best.index, best.mean, best.n, alive_count, n_cand,
        evals_done, #kill_events
    ))

    ctx.result = {
        best = candidates[best.index],
        best_index = best.index,
        best_score = best.mean,
        ranking = ranking,
        candidates = candidates,
        rounds = rounds,
        kill_events = kill_events,
        protect_events = protect_events,
        alive_count = alive_count,
        n_candidates = n_cand,
        n_dimensions = D,
        evaluations = evals_done,
        total_llm_calls = n_cand + evals_done,
        delta = delta,
        alpha_per_side = is_betting and alpha_betting or alpha,
        cs_variant = cs_variant,
    }
    return ctx
end

return M
