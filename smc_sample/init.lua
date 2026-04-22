--- smc_sample — Sequential Monte Carlo (block-SMC) sampling for LLM quality.
---
--- Based on: Markovic-Voronov et al., "Sampling for Quality: Training-Free
--- Reward-Guided LLM Decoding via Sequential Monte Carlo"
--- (arXiv:2604.16453v1, 2026-04-07).
---
--- Implements the paper's Target I (prefix-only variant) of the reward-
--- augmented target distribution
---     Π(x_{1:T} | q) ∝ ∏_t m_t(x_t | q, x_{<t}) · ∏_t ψ_t(x_{1:t}, q)
--- abstracted to the BLOCK level so it is implementable on top of
--- algocline's block-granular `alc.llm` API (token logprobs are not
--- exposed). Under this Target I specialization the incremental weights
--- depend only on the reward potentials ψ_t and the base-model
--- likelihood term cancels (paper §3.3 / Appendix A.4 Lemma 4, Eq. 40):
---     w_k = Ψ_k / Ψ_{k-1} = exp(α · (r_new - r_prev))
---
--- block-SMC abstraction:
---   * 1 particle = 1 complete answer (`alc.llm` single call)
---   * ψ_t       = exp(α · r(answer))   where r = caller-injected reward_fn
---   * K rounds  = {ESS resample, MH rejuvenation, weight-update} repeated
---
--- ═══ COST WARNING ═══════════════════════════════════════════════════
--- With default hyperparameters (N=16, K=4, S=2) this pkg issues
--- **208 LLM calls per run** (initial N + K · N · (1 + S)). This
--- matches the paper's HumanEval 87.8% setting (§4.1) but is heavier
--- than any existing selection pkg (e.g. `recipe_deep_panel` ~52 calls).
--- Lightweight callers should override `n_particles` / `n_iterations` /
--- `rejuv_steps` (e.g. N=4, K=2, S=1 → 20 calls).
--- ═══════════════════════════════════════════════════════════════════
---
--- ═══ PAPER FIDELITY & INJECTION POINTS ════════════════════════════
--- Implementation follows paper §3.4 Algorithm 1 under the block-SMC
--- specialization of §A.4 (1 block = 1 complete answer). All
--- deviations from the paper default are opt-in via explicit ctx
--- knobs — the default path is paper-faithful. This prioritizes
--- correctness over efficiency and keeps optimizations discoverable.
---
--- Paper-faithful defaults:
---   * Weight update (paper Alg. 1 Line 8-9) runs only at init
---     (compute_weights) and on ESS-triggered resample-reset to 1/N.
---     Between iterations, under fixed α the Target I incremental
---     ratio is identically 1, so no between-iter reweight is applied.
---   * MH rejuvenation is SELECTIVE per paper Alg. 1 Lines 15-17:
---     a slot receives an MH proposal iff it is a duplicate from the
---     most recent resample AND its reward is below τ_R.
---   * α is fixed globally (paper §4.1 Setup).
---
--- Injection points (stable, documented caller overrides):
---   * `reward_fn`          — REQUIRED. `(answer, task) → ℝ⁺ ∪ {0}`.
---                             Caller's verifier (unit-test / LLM
---                             judge / scoring rule).
---   * `proposal_fn`        — v2 opt-in, will replace the fixed LLM-
---                             refine proposal inside mh_rejuvenate
---                             (currently warning-then-ignore in v1).
---   * `mh_filter_fn`       — OPTIONAL. `(idx, reward, was_duplicated,
---                             τ_R) → boolean`. Overrides the paper
---                             selective predicate. Use
---                             `function() return true end` to get
---                             the legacy "MH every particle" variant
---                             (higher cost, correctness-preserving).
---   * `mh_reward_threshold` — OPTIONAL. τ_R cutoff for the default
---                             selective filter. Default 0.5 (neutral
---                             for rewards ∈ [0,1]); binary graders
---                             (0/1) should set 1.0.
---   * `post_mh_reweight`   — OPTIONAL. `true` to apply a legacy
---                             exp(α·Δr) reweight after each
---                             iteration's MH. NOT paper-faithful —
---                             injects reward-gain bias. Kept only
---                             for reproducing pre-0.2.0 runs.
---
--- Section references were corrected on 2026-04-22 after a Target I
--- paper-verify round-trip (workspace/tasks/smc_sample-s_steps-verify/
--- paper-verify.md). Earlier drafts cited "paper §4.2-§4.3" which
--- does not exist in the arXiv v1 PDF — §4 contains only §4.1 Setup;
--- the Target I formalism lives in §3.3 and Appendix A.4 Lemma 4.
---
--- Cost note: paper-faithful selective MH (default) typically runs
--- MH only on iterations where ESS-resample fires, so total_llm_calls
--- is input-dependent and often ≪ the "N + K·N·(1+S)" worst-case.
--- Callers that need the predictable worst-case cost (e.g. budget
--- planning) should set `mh_filter_fn = function() return true end`.
--- ═══════════════════════════════════════════════════════════════════
---
--- Usage:
---   local smc = require("smc_sample")
---   return smc.run({
---       task      = "Write a Python function sum_list(xs).",
---       reward_fn = function(answer, task)
---           -- caller-injected verifier: unit-test / LLM judge / scoring_rule
---           return score_in_unit_interval
---       end,
---       -- all hyperparameters optional (M._defaults applies)
---   })
---
--- Category: selection (alongside sc / usc / mbr_select / diverse /
--- ab_select / gumbel_search). Encompasses sc (α=0 equal-weight) and
--- mbr_select (similarity reward, 1 iteration) as special cases of the
--- same probabilistic framework.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "smc_sample",
    version = "0.1.0",
    description = "Block-level Sequential Monte Carlo sampling for LLM "
        .. "quality (Markovic-Voronov et al. 2026, arXiv:2604.16453). "
        .. "Reward-weighted importance sampling with ESS-triggered "
        .. "multinomial resampling and Metropolis-Hastings rejuvenation. "
        .. "Caller-injected reward_fn (unit-test / LLM judge / scoring "
        .. "rule) drives the Target I tempered potential ψ=exp(α·r). "
        .. "Default (N=16,K=4,S=2) issues 208 LLM calls per run.",
    category = "selection",
}

-- Centralized defaults. Paper §4.1 HumanEval 87.8% setting. Keep
-- magic numbers here so no entry hard-codes its own copy — callers
-- override individual knobs at runtime.
M._defaults = {
    n_particles         = 16,    -- N (paper §4.1)
    n_iterations        = 4,     -- K SMC rounds
    alpha               = 4.0,   -- tempering strength (ψ = exp(α · r))
    ess_threshold       = 0.5,   -- resample when ESS < threshold · N
    rejuv_steps         = 2,     -- S Metropolis-Hastings rejuvenation steps
    gen_tokens          = 600,   -- max tokens per LLM call (code-gen default)
    -- Paper §3.4 Line 17: MH targets duplicated + low-reward particles.
    -- τ_R value is not numerically fixed in §4.1 Setup; 0.5 is a
    -- neutral default for rewards normalized to [0, 1]. Callers with
    -- unit-test graders (0/1) likely want τ_R = 1.0 (always eligible);
    -- callers with continuous graders can tune.
    mh_reward_threshold = 0.5,
    -- Paper Algorithm 1 does NOT apply a post-MH reweight (weight
    -- update is at Line 8-9, before resample + MH). Set true to opt
    -- into the legacy exp(α·Δr) post-MH reweight — that path is NOT
    -- paper-faithful and injects reward-gain bias; kept only as an
    -- escape hatch for callers reproducing pre-0.2.0 smc_sample runs.
    post_mh_reweight    = false,
}

-- ═══════════════════════════════════════════════════════════════════
-- Pure helpers (testable, LLM-independent)
-- ═══════════════════════════════════════════════════════════════════

--- compute_weights — Tempered, max-shifted, normalized initial weights.
---
--- Returns `w_i ∝ exp(α · r_i)` normalized to Σw = 1. Uses max-shift
--- (`exp(α · r_i - m)` where `m = max(α · r_i)`) for numerical stability:
--- without it, α=4 with reward=10 would already overflow double precision.
---
--- Edge cases (issue §13.3 limits):
---   * α = 0: all particles equal-weighted (1/N) regardless of rewards
---   * α → ∞: only argmax-reward particle retains non-zero weight
---
---@param rewards number[]
---@param alpha number
---@return number[], number  -- weights, log_z (for diagnostics / downstream)
local function compute_weights(rewards, alpha)
    if type(rewards) ~= "table" then
        error("smc_sample.compute_weights: rewards must be table, got " .. type(rewards), 2)
    end
    if type(alpha) ~= "number" then
        error("smc_sample.compute_weights: alpha must be number, got " .. type(alpha), 2)
    end
    local n = #rewards
    if n == 0 then
        error("smc_sample.compute_weights: rewards must be non-empty", 2)
    end

    -- Find max(α · r_i) for shift
    local scaled = {}
    local m = -math.huge
    for i = 1, n do
        local v = alpha * rewards[i]
        scaled[i] = v
        if v > m then m = v end
    end

    -- exp(α · r_i - m) then normalize
    local raw = {}
    local sum = 0
    for i = 1, n do
        local e = math.exp(scaled[i] - m)
        raw[i] = e
        sum = sum + e
    end

    -- Numerical guard: sum can be 0 only if every exp underflowed
    -- below double-precision. Fall back to uniform so the pipeline
    -- doesn't divide by zero (internal invariant; surfaces only in
    -- pathological α · (r_i - m) ≪ -700 regimes).
    if sum <= 0 then
        local w = {}
        for i = 1, n do w[i] = 1 / n end
        return w, 0
    end

    local w = {}
    for i = 1, n do w[i] = raw[i] / sum end

    -- log Z = m + log(sum)  (diagnostic return value)
    return w, m + math.log(sum)
end

--- compute_ess — Effective Sample Size (paper §3.4 / Eq (ESS)).
---
---     ESS = (Σ w_i)² / Σ (w_i²)
---
--- Invariants:
---   * Equal weights (w_i = 1/N): ESS = N
---   * Single-particle domination (w_1 = 1, rest 0): ESS = 1
---
---@param weights number[]
---@return number
local function compute_ess(weights)
    if type(weights) ~= "table" then
        error("smc_sample.compute_ess: weights must be table, got " .. type(weights), 2)
    end
    local n = #weights
    if n == 0 then
        error("smc_sample.compute_ess: weights must be non-empty", 2)
    end

    local s1 = 0
    local s2 = 0
    for i = 1, n do
        local w = weights[i]
        if type(w) ~= "number" then
            error("smc_sample.compute_ess: weights[" .. i .. "] must be number, got " .. type(w), 2)
        end
        s1 = s1 + w
        s2 = s2 + w * w
    end

    if s2 <= 0 then
        -- All weights zero (degenerate) — return 0 rather than NaN so
        -- the resample trigger handles it cleanly.
        return 0
    end
    return (s1 * s1) / s2
end

--- resample_multinomial — Draw N particles with replacement proportional
--- to `weights` via CDF (prefix-sum) sampling.
---
--- Returns both the resampled particle list AND the list of original
--- indices that each new slot was drawn from. `drawn_indices[i] = j`
--- means `new_particles[i] == particles[j]`; when `j` appears more
--- than once across slots the corresponding new slots are duplicates
--- of each other (paper §3.4 D_k membership — used by selective MH).
--- Back-compat: callers that only destructure the first return keep
--- working; the second return is additive.
---
--- After resampling, caller should reset all weights to 1/N (degeneracy
--- reset per paper §3.4).
---
---@param particles any[]
---@param weights number[]
---@param rng nil|fun():number  -- test injection; default math.random
---@return any[], integer[]  -- resampled particles, drawn_indices
local function resample_multinomial(particles, weights, rng)
    if type(particles) ~= "table" then
        error("smc_sample.resample_multinomial: particles must be table, got " .. type(particles), 2)
    end
    if type(weights) ~= "table" then
        error("smc_sample.resample_multinomial: weights must be table, got " .. type(weights), 2)
    end
    local n = #particles
    if n == 0 then
        error("smc_sample.resample_multinomial: particles must be non-empty", 2)
    end
    if #weights ~= n then
        error("smc_sample.resample_multinomial: #weights (" .. #weights
            .. ") != #particles (" .. n .. ")", 2)
    end
    local draw = rng or math.random

    -- Build CDF (normalized). Σw must be > 0 or sampling is undefined.
    local sum = 0
    for i = 1, n do sum = sum + weights[i] end
    if sum <= 0 then
        error("smc_sample.resample_multinomial: Σweights must be > 0", 2)
    end

    local cdf = {}
    local acc = 0
    for i = 1, n do
        acc = acc + weights[i] / sum
        cdf[i] = acc
    end
    -- Guard final bucket against floating drift so u=1-ε always lands
    -- in the last particle rather than falling off the end of the CDF.
    cdf[n] = 1.0

    local out = {}
    local drawn = {}
    for i = 1, n do
        local u = draw()
        -- Linear scan is fine for typical N ∈ [4, 64]; binary search
        -- would be a premature optimization given the surrounding
        -- K · N LLM calls dominating wall-clock.
        local idx = n
        for j = 1, n do
            if u <= cdf[j] then idx = j; break end
        end
        out[i] = particles[idx]
        drawn[i] = idx
    end

    -- Internal invariant: multinomial resample must preserve particle
    -- count. Violating this is a bug in the loop above, not a caller
    -- contract issue.
    assert(#out == n, "internal: resample must preserve N")
    assert(#drawn == n, "internal: drawn_indices must have length N")
    return out, drawn
end

--- mh_accept — Metropolis-Hastings acceptance test (general 4-arg form).
---
--- Decides whether to accept proposal x' over current x given target
--- densities π and proposal densities q:
---     α(x → x') = min(1, [π(x') · q(x | x')] / [π(x) · q(x' | x)])
---
--- v1 block-SMC note: the built-in LLM-refine proposal is treated as
--- symmetric (q(x|x') ≈ q(x'|x) = 1.0). Callers in v1 pass 1.0 for both
--- `q_*` arguments, which collapses the ratio to π(x')/π(x) = exp(α·Δr).
--- The general 4-arg form is preserved so v2's `proposal_fn` caller
--- injection can supply non-symmetric proposal densities without an
--- API break (issue §13.3 / §13.5).
---
---@param pi_x number               -- target density at current particle
---@param pi_xprime number          -- target density at proposed particle
---@param q_x_given_xprime number   -- proposal density x | x'
---@param q_xprime_given_x number   -- proposal density x' | x
---@return boolean
local function mh_accept(pi_x, pi_xprime, q_x_given_xprime, q_xprime_given_x)
    if type(pi_x) ~= "number" then
        error("smc_sample.mh_accept: pi_x must be number, got " .. type(pi_x), 2)
    end
    if type(pi_xprime) ~= "number" then
        error("smc_sample.mh_accept: pi_xprime must be number, got " .. type(pi_xprime), 2)
    end
    if type(q_x_given_xprime) ~= "number" then
        error("smc_sample.mh_accept: q_x_given_xprime must be number, got "
            .. type(q_x_given_xprime), 2)
    end
    if type(q_xprime_given_x) ~= "number" then
        error("smc_sample.mh_accept: q_xprime_given_x must be number, got "
            .. type(q_xprime_given_x), 2)
    end

    -- pi_x == 0 would make the ratio divide by zero. Treat as reject
    -- (a zero-density current particle cannot be the base of a valid
    -- ratio test; the proposal has no baseline to compare against).
    if pi_x == 0 then return false end
    -- q_xprime_given_x == 0 would also divide by zero. Paper §3.5
    -- implicitly assumes proposal density is strictly positive on the
    -- support of π; defensively reject if caller passes 0.
    if q_xprime_given_x == 0 then return false end

    local ratio = (pi_xprime * q_x_given_xprime) / (pi_x * q_xprime_given_x)
    local alpha = math.min(1.0, ratio)
    -- Negative ratio (only possible if caller passes negative density)
    -- should never accept.
    if alpha <= 0 then return false end
    return math.random() < alpha
end

--- incremental_weight_update — Target I SMC incremental weight
--- (paper §3.3 / Appendix A.4 Lemma 4, Eq. 40).
---
---     W_k = W_{k-1} · w_k
---     w_k = Ψ_k / Ψ_{k-1} = exp(α · r_new) / exp(α · r_prev)
---         = exp(α · (r_new - r_prev))
---
--- Under Target I the base-model likelihood factor m_t cancels, so the
--- update depends only on the reward potentials — this is exactly why
--- block-SMC is implementable without logprob access.
---
---@param w_prev number
---@param r_new number
---@param r_prev number
---@param alpha number
---@return number
local function incremental_weight_update(w_prev, r_new, r_prev, alpha)
    if type(w_prev) ~= "number" then
        error("smc_sample.incremental_weight_update: w_prev must be number, got " .. type(w_prev), 2)
    end
    if type(r_new) ~= "number" then
        error("smc_sample.incremental_weight_update: r_new must be number, got " .. type(r_new), 2)
    end
    if type(r_prev) ~= "number" then
        error("smc_sample.incremental_weight_update: r_prev must be number, got " .. type(r_prev), 2)
    end
    if type(alpha) ~= "number" then
        error("smc_sample.incremental_weight_update: alpha must be number, got " .. type(alpha), 2)
    end
    return w_prev * math.exp(alpha * (r_new - r_prev))
end

-- ═══════════════════════════════════════════════════════════════════
-- Shape definition (local) for M.spec.entries.run.input
-- ═══════════════════════════════════════════════════════════════════

-- reward_fn is `T.any` because alc_shapes has no function combinator
-- (closures can't cross the Schema-as-Data persistence boundary). The
-- run entry point type-checks `ctx.reward_fn` manually on the first
-- line (fail-fast, per issue §13.5).
local run_input_shape = T.shape({
    task          = T.string:describe("Problem statement fed to the base LLM + reward_fn"),
    reward_fn     = T.any:describe(
        "Caller-injected fn(answer, task) → number ∈ [0, +∞). "
            .. "unit-test / LLM judge / scoring_rule. Runtime type-checked."),
    n_particles   = T.number:is_optional():describe("N particles (default: 16, paper §4.1)"),
    n_iterations  = T.number:is_optional():describe("K SMC iterations (default: 4)"),
    alpha         = T.number:is_optional():describe("Tempering strength (default: 4.0)"),
    ess_threshold = T.number:is_optional():describe("ESS trigger ratio (default: 0.5)"),
    rejuv_steps   = T.number:is_optional():describe("S MH rejuvenation steps (default: 2)"),
    gen_tokens    = T.number:is_optional():describe("Max tokens per LLM call (default: 600)"),
    -- Card IF (optimize / conformal_vote pattern)
    auto_card     = T.boolean:is_optional():describe("Emit a Card on completion (default: false)"),
    card_pkg      = T.string:is_optional():describe(
        "Card pkg.name override (default: 'smc_sample_<task_hash>')"),
    scenario_name = T.string:is_optional():describe("Explicit scenario name for the emitted Card"),
    -- Injection points for paper-deviation overrides (see header
    -- KNOWN LIMITATIONS / PAPER FIDELITY block).
    mh_filter_fn        = T.any:is_optional():describe(
        "Caller override for paper §3.4 Line 17 selective-MH "
        .. "predicate. Signature: (idx, reward, was_duplicated, "
        .. "τ_R) → boolean. Default: duplicated AND reward < τ_R. "
        .. "Use `function() return true end` for the legacy "
        .. "apply-MH-to-all variant (higher LLM cost)."),
    mh_reward_threshold = T.number:is_optional():describe(
        "τ_R cutoff for the default selective-MH predicate "
        .. "(paper §3.4 Line 17). Default: 0.5."),
    post_mh_reweight    = T.boolean:is_optional():describe(
        "Opt into the legacy exp(α·Δr) post-MH reweight "
        .. "(NOT paper-faithful — reward-gain bias). Default: "
        .. "false. Kept only for pre-0.2.0 run reproduction."),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input  = run_input_shape,
            result = "smc_sampled",
        },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- LLM integration helpers (testable with alc stub)
-- ═══════════════════════════════════════════════════════════════════

--- map_or_serial — alc.map when available, serial for-loop otherwise.
--- Same fallback convention as sc / mbr_select.
local function map_or_serial(collection, fn)
    if type(alc) == "table" and type(alc.map) == "function" then
        return alc.map(collection, fn)
    end
    local out = {}
    for i, v in ipairs(collection) do out[i] = fn(v, i) end
    return out
end

--- build_refine_prompt — v1 LLM-refine proposal prompt.
---
--- The MH proposal q(x'|x) is treated as symmetric in v1 (see mh_accept
--- commentary). This prompt intentionally asks for preservation of
--- intent so the refine is a "mild local move" in answer space; wide
--- rewrites would destabilize the symmetric-q approximation.
local function build_refine_prompt(prev_answer, task)
    return string.format(
        "Refine the following answer to the task while preserving intent. "
            .. "Return ONLY the refined answer, no preamble or commentary.\n\n"
            .. "Task:\n%s\n\nCurrent answer:\n%s",
        tostring(task), tostring(prev_answer))
end

--- init_particles — Parallel draw of N independent answers.
---
--- Each particle is a table `{ answer, history = {} }`. reward / weight
--- are filled in later. `alc.map` is used when available to fan out the
--- N LLM calls in parallel; serial fallback is semantically identical.
---
--- Returns the particles list. LLM call count = N (all draws are
--- mandatory; there is no early termination).
local function init_particles(task, n, gen_tokens)
    local indices = {}
    for i = 1, n do indices[i] = i end

    local answers = map_or_serial(indices, function(_i)
        return alc.llm(task, { max_tokens = gen_tokens })
    end)

    -- history = 1-slot convention, diagnostic only:
    --   * empty {}                               — never accepted a proposal
    --   * { { answer, reward } }                 — last Accept's pre-swap state
    -- Reject paths preserve the previous history unchanged, so a particle
    -- that accepted on iteration k=2 and then rejected on k=3..K retains
    -- the k=2 pre-swap state (not the k-1 particle state). This matches
    -- the "last accept snapshot" semantics expected by diagnostic trace
    -- consumers; callers needing a full accept/reject trace should use
    -- Card samples (Tier 2 sidecar) instead.
    local particles = {}
    for i = 1, n do
        particles[i] = {
            answer  = tostring(answers[i] or ""),
            history = {},
        }
    end
    return particles
end

--- evaluate_rewards — Apply caller's reward_fn to each particle.
---
--- Fail-fast policy (issue §13.5, Human decision): reward_fn failure /
--- non-number / NaN / negative / +Inf return → immediate error re-raise.
--- Silent weight=0 substitution is explicitly forbidden: a degenerate
--- reward_fn should surface at the caller, not be masked inside the
--- particle filter.
---
--- Returns `rewards` (parallel to particles) and `n_calls` (number of
--- reward_fn invocations actually made, for total_reward_calls book-
--- keeping).
local function evaluate_rewards(particles, task, reward_fn)
    -- alc.map cannot abort partway through, so we use the map helper
    -- for parallelism benefit only when every reward_fn succeeds; any
    -- failure is re-raised outside the map via the first entry with
    -- ok=false. We record per-particle ok/value pairs and surface the
    -- first failure.
    local results = map_or_serial(particles, function(p, _i)
        local ok, r = pcall(reward_fn, p.answer, task)
        return { ok = ok, val = r }
    end)

    local rewards = {}
    for i = 1, #particles do
        local res = results[i]
        if not res.ok then
            error(string.format(
                "smc_sample.run: reward_fn failed for particle %d: %s",
                i, tostring(res.val)), 2)
        end
        local r = res.val
        if type(r) ~= "number" then
            error(string.format(
                "smc_sample.run: reward_fn returned non-number for particle %d: %s (type %s)",
                i, tostring(r), type(r)), 2)
        end
        if r ~= r then  -- NaN check (NaN != NaN in IEEE 754)
            error(string.format(
                "smc_sample.run: reward_fn returned NaN for particle %d", i), 2)
        end
        if r < 0 then
            error(string.format(
                "smc_sample.run: reward_fn returned negative value %.6g for particle %d "
                    .. "(contract: r ∈ [0, +∞))", r, i), 2)
        end
        if r == math.huge then
            error(string.format(
                "smc_sample.run: reward_fn returned +Inf for particle %d "
                    .. "(finite reward required)", i), 2)
        end
        rewards[i] = r
    end
    return rewards, #particles
end

--- mh_rejuvenate — One MH step across all particles.
---
--- For each particle: LLM-refine-proposes a new answer, computes its
--- reward (charging reward_fn calls to the caller), then accepts /
--- rejects via `mh_accept` under the symmetric-q v1 assumption. Failed
--- proposals (LLM error / empty string) are treated as rejects and do
--- NOT increment the LLM call counter (they didn't consume a successful
--- generation).
---
--- PAPER §3.4 Algorithm 1 Lines 15-17 (selective MH) compliance:
---   Optional `filter` boolean array selects which particles get a MH
---   proposal this call. Slots with `filter[i] == false` skip the LLM
---   propose / reward-eval / accept-reject entirely — cost savings scale
---   linearly with the filter-out count. When `filter == nil` MH is
---   applied unconditionally (back-compat for callers that want the
---   every-particle variant).
---
--- The selective predicate itself lives in M.run (default: duplicated
--- via resample AND reward < τ_R, matching paper). Callers can
--- override the predicate via `ctx.mh_filter_fn`.
---
--- Returns:
---   new_particles, new_rewards,
---   n_proposal_llm_calls (successful proposals only),
---   n_reward_calls, n_rejected
---@param particles any[]
---@param rewards number[]
---@param alpha number
---@param task string
---@param gen_tokens integer
---@param reward_fn fun(answer: string, task: string): number
---@param filter boolean[]|nil   -- filter[i]=true → apply MH to slot i
local function mh_rejuvenate(particles, rewards, alpha, task, gen_tokens, reward_fn, filter)
    local n = #particles

    -- Active slot index list: slots where MH proposes/evaluates/accepts.
    -- nil filter means "all active" (back-compat).
    local active = {}
    for i = 1, n do
        if filter == nil or filter[i] then
            active[#active + 1] = i
        end
    end

    local new_particles = {}
    local new_rewards = {}
    for i = 1, n do
        new_particles[i] = particles[i]
        new_rewards[i]   = rewards[i]
    end

    -- Fast exit: nothing selected → zero LLM/reward cost.
    if #active == 0 then
        return new_particles, new_rewards, 0, 0, 0
    end

    -- Stage 1: propose (parallel LLM calls) on active slots only.
    local active_particles = {}
    for j, i in ipairs(active) do active_particles[j] = particles[i] end
    local proposals_active = map_or_serial(active_particles, function(p, _j)
        local ok, resp = pcall(alc.llm,
            build_refine_prompt(p.answer, task),
            { max_tokens = gen_tokens })
        if not ok then return nil end
        if type(resp) ~= "string" or resp == "" then return nil end
        return resp
    end)

    -- Count successful proposal LLM calls over active slots only.
    local n_proposal_llm_calls = 0
    for j = 1, #active do
        if proposals_active[j] ~= nil then
            n_proposal_llm_calls = n_proposal_llm_calls + 1
        end
    end

    -- Stage 2: reward-evaluate active slots. We evaluate every active
    -- proposal that arrived (or the fallback current answer for failed
    -- proposals), since reward is needed for the acceptance ratio.
    local prop_particles_active = {}
    for j, i in ipairs(active) do
        prop_particles_active[j] = {
            answer  = proposals_active[j] or particles[i].answer,
            history = {},
        }
    end
    local prop_rewards_active = evaluate_rewards(prop_particles_active, task, reward_fn)
    local n_reward_calls = #active

    -- Stage 3: acceptance test per ACTIVE slot.
    --
    -- Under v1 symmetric-q assumption (q(x|x') = q(x'|x) = 1.0), the
    -- 4-arg mh_accept collapses to a ratio test on the target density
    -- π = ψ = exp(α·r). Target I property paper §3.3 / §A.4.
    --
    -- ⚠ ALIASING: new_particles[i] = particles[i] on inactive / reject
    -- copies a reference. Upstream resample may already alias particles
    -- across slots; Accept builds a fresh table so safe today, any
    -- future in-place mutation must deep-copy first.
    local n_rejected = 0
    for j, i in ipairs(active) do
        if proposals_active[j] == nil then
            -- Failed proposal → retain current, count as reject.
            -- (new_particles[i] / new_rewards[i] already hold the
            -- previous values from the init loop above.)
            n_rejected = n_rejected + 1
        else
            local psi_x      = math.exp(alpha * rewards[i])
            local psi_xprime = math.exp(alpha * prop_rewards_active[j])
            if mh_accept(psi_x, psi_xprime, 1.0, 1.0) then
                -- Accept: keep a 1-slot history snapshot of the old
                -- particle for diagnostic trace (Risks #5).
                new_particles[i] = {
                    answer  = prop_particles_active[j].answer,
                    history = { { answer = particles[i].answer, reward = rewards[i] } },
                }
                new_rewards[i] = prop_rewards_active[j]
            else
                -- Reject: new_particles[i] / new_rewards[i] already
                -- hold prev values, just count the reject.
                n_rejected = n_rejected + 1
            end
        end
    end

    return new_particles, new_rewards, n_proposal_llm_calls, n_reward_calls, n_rejected
end

-- ═══════════════════════════════════════════════════════════════════
-- Card IF — emit_card (Two-Tier, optimize/conformal_vote pattern)
-- ═══════════════════════════════════════════════════════════════════

--- emit_card — Emit a Card capturing the SMC run's decision surface.
---
--- Tier 1 (Card body): nested { pkg, scenario, params, stats, smc_sample }.
--- Tier 2 (samples.jsonl): per-particle final state via write_samples.
---
--- fail-safe: `alc.card` absent → alc.log.warn + return nil (caller's
--- auto_card=true is honored best-effort, not fatal).
local function emit_card(ctx, result, per_particle_list)
    if type(alc) ~= "table" or type(alc.card) ~= "table"
            or type(alc.card.create) ~= "function" then
        if type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.warn) == "function" then
            alc.log.warn("smc_sample: alc.card unavailable — skipping Card emission")
        end
        return nil
    end

    -- Stable-ish pkg_name default. alc.hash is the preferred hasher
    -- (cheap, available in recent runtimes); fall back to os.time()
    -- string truncated so we don't pollute Card names with a full
    -- unix timestamp.
    local hash_source
    if type(alc.hash) == "function" then
        hash_source = tostring(alc.hash(ctx.task or ""))
    else
        hash_source = tostring(os.time())
    end
    local pkg_name = ctx.card_pkg or ("smc_sample_" .. string.sub(hash_source, 1, 8))

    -- Mean reward over final particles (Tier 1 summary stat).
    local sum_r = 0
    for i = 1, #per_particle_list do
        sum_r = sum_r + (per_particle_list[i].final_reward or 0)
    end
    local mean_reward = (#per_particle_list > 0) and (sum_r / #per_particle_list) or 0

    -- ESS trace → final_ess. K=0 path leaves ess_trace empty (the main
    -- loop never runs), so we fall back to computing ESS directly from
    -- the final weights; if that is also unavailable, use 0 as a
    -- "not-measured" sentinel. This keeps Card payloads shape-valid
    -- regardless of the K value the caller supplied.
    local ess_trace = result.ess_trace or {}
    local final_ess = ess_trace[#ess_trace]
    if final_ess == nil and type(result.weights) == "table" and #result.weights > 0 then
        final_ess = compute_ess(result.weights)
    end
    final_ess = final_ess or 0

    local card = alc.card.create({
        pkg = { name = pkg_name },
        scenario = { name = ctx.scenario_name or "unknown" },
        params = {
            n_particles   = #per_particle_list,
            n_iterations  = result.iterations,
            alpha         = ctx.alpha or M._defaults.alpha,
            ess_threshold = ctx.ess_threshold or M._defaults.ess_threshold,
            rejuv_steps   = ctx.rejuv_steps or M._defaults.rejuv_steps,
            gen_tokens    = ctx.gen_tokens or M._defaults.gen_tokens,
        },
        stats = {
            total_llm_calls    = result.stats.total_llm_calls,
            total_reward_calls = result.stats.total_reward_calls,
            resample_count     = result.resample_count,
            final_ess          = final_ess,
            mean_reward        = mean_reward,
        },
        smc_sample = {
            answer         = result.answer,
            n_particles    = #per_particle_list,
            n_iterations   = result.iterations,
            resample_count = result.resample_count,
            final_ess      = final_ess,
            mean_reward    = mean_reward,
            alpha          = ctx.alpha or M._defaults.alpha,
            ess_trace      = ess_trace,
        },
    })

    -- Tier 2 sidecar: per-particle finals. Skip when card.create
    -- returned something we can't address (e.g. stub returned nil).
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
-- M.run — block-SMC orchestration (paper §3.3 / §3.4 Algorithm 1,
-- Target I specialization)
-- ═══════════════════════════════════════════════════════════════════

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    -- ─── ctx validation (fail-fast) ───
    if type(ctx) ~= "table" then
        error("smc_sample.run: ctx must be table, got " .. type(ctx), 2)
    end
    local task = ctx.task
    if type(task) ~= "string" or task == "" then
        error("smc_sample.run: ctx.task is required (non-empty string)", 2)
    end
    local reward_fn = ctx.reward_fn
    if type(reward_fn) ~= "function" then
        error("smc_sample.run: ctx.reward_fn is required (function fn(answer, task) → number)", 2)
    end

    -- Capture INJECTABLE function-typed overrides BEFORE the strip block
    -- below nils them out. mh_filter_fn is optional; when absent the
    -- default paper §3.4 Line 17 predicate (duplicated AND R<τ_R) is
    -- constructed inside the main loop below.
    local mh_filter_fn = ctx.mh_filter_fn
    if mh_filter_fn ~= nil and type(mh_filter_fn) ~= "function" then
        error("smc_sample.run: ctx.mh_filter_fn must be function, got " .. type(mh_filter_fn), 2)
    end

    -- v1: proposal_fn caller injection not yet supported (issue §13.5).
    -- Warn (not error) so callers who pre-configure for v2 aren't hard-
    -- rejected — their proposal_fn is simply ignored in v1. Fire the
    -- warning BEFORE the strip below so we don't need a saved flag.
    if ctx.proposal_fn ~= nil then
        if type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.warn) == "function" then
            alc.log.warn(
                "smc_sample.run: ctx.proposal_fn is ignored in v1 "
                .. "(LLM-refine proposal is fixed). v2 will opt in.")
        end
    end

    -- ─── Strip caller-injected Lua closures from ctx ───
    -- Done BEFORE the rest of the body runs so that even if a later
    -- validation or SMC step errors, the caller's ctx is still JSON-
    -- serializable (e.g. for post-hoc debug logging at the MCP boundary).
    -- All function-typed top-level fields are input contracts (reward_fn /
    -- proposal_fn / future callbacks), never part of the strategy output.
    -- The reward_fn local above keeps the captured closure usable for the
    -- SMC loop. Regression: E2E 2026-04-22 run_id 122845.
    --
    -- Clearing during iteration is explicitly allowed by Lua 5.4 Reference
    -- Manual §3.3.5 ("you may however modify existing fields ... in
    -- particular, you may clear existing fields").
    for k, v in pairs(ctx) do
        if type(v) == "function" then ctx[k] = nil end
    end

    -- ─── Resolve hyperparameters from ctx + M._defaults ───
    local N          = ctx.n_particles or M._defaults.n_particles
    local K          = ctx.n_iterations or M._defaults.n_iterations
    local alpha      = ctx.alpha or M._defaults.alpha
    local thr        = ctx.ess_threshold or M._defaults.ess_threshold
    local S_steps    = ctx.rejuv_steps or M._defaults.rejuv_steps
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens

    -- Selective MH knobs (paper §3.4 Lines 15-17).
    local mh_reward_threshold = ctx.mh_reward_threshold
        or M._defaults.mh_reward_threshold
    -- Legacy non-paper post-MH reweight (default off, paper-faithful).
    local post_mh_reweight = ctx.post_mh_reweight
    if post_mh_reweight == nil then
        post_mh_reweight = M._defaults.post_mh_reweight
    end
    -- Default filter: paper §3.4 Line 17 — slot i must be a duplicate
    -- from resample AND have reward < τ_R to receive an MH proposal.
    if mh_filter_fn == nil then
        mh_filter_fn = function(_idx, r, was_dup, _tau_R)
            return was_dup and r < mh_reward_threshold
        end
    end

    if type(N) ~= "number" or N < 1 then
        error("smc_sample.run: n_particles must be positive number, got " .. tostring(N), 2)
    end
    if type(K) ~= "number" or K < 0 then
        error("smc_sample.run: n_iterations must be non-negative number, got " .. tostring(K), 2)
    end
    if type(alpha) ~= "number" then
        error("smc_sample.run: alpha must be number, got " .. type(alpha), 2)
    end
    if type(thr) ~= "number" or thr < 0 or thr > 1 then
        error("smc_sample.run: ess_threshold must be in [0,1], got " .. tostring(thr), 2)
    end
    if type(S_steps) ~= "number" or S_steps < 0 then
        error("smc_sample.run: rejuv_steps must be non-negative number, got " .. tostring(S_steps), 2)
    end

    -- ─── SMC initialization ───
    local total_llm_calls    = 0
    local total_reward_calls = 0
    local mh_rejected        = 0
    local resample_count     = 0
    local ess_trace          = {}

    local particles = init_particles(task, N, gen_tokens)
    total_llm_calls = total_llm_calls + N

    local rewards
    rewards, _ = evaluate_rewards(particles, task, reward_fn)
    total_reward_calls = total_reward_calls + N

    local weights = compute_weights(rewards, alpha)

    -- ─── K-iteration SMC main loop (paper §3.4 Algorithm 1) ──────────
    -- Order per paper Algorithm 1:
    --   1. (block-SMC w/ 1-block-=-1-answer: block was generated at
    --      init_particles; there is no per-iteration base-model block
    --      regeneration at this scale — LLM cost would be prohibitive)
    --   2. ESS check → resample if degenerate (Lines 12-14)
    --   3. Selective MH rejuvenation on duplicated + low-reward
    --      particles (Lines 15-26)
    --   4. Weight update is NOT applied between iterations — under a
    --      fixed-α target and π-invariant MH, π_k = π_{k-1}, so the
    --      Target I incremental weight ratio is identically 1. All
    --      weight changes come from (a) initial compute_weights above
    --      and (b) ESS-triggered resample-reset to 1/N.
    --   Legacy exp(α·Δr) post-MH reweight is available via
    --   `ctx.post_mh_reweight = true` (NOT paper-faithful; injects
    --   reward-gain bias; kept only for backward-compat).
    for _k = 1, K do
        local ess = compute_ess(weights)
        ess_trace[#ess_trace + 1] = ess

        -- Resample trigger: ESS < thr · N. On fire, reset weights to
        -- 1/N (paper §3.4 degeneracy reset). Rewards are re-indexed to
        -- the resampled particles in lockstep.
        --
        -- ⚠ ALIASING: resample_multinomial copies particle table
        -- references by design (multinomial with replacement). After
        -- this block, new_particles[i] and new_particles[j] may point
        -- to the same table when i and j drew the same index. Safe
        -- today because mh_rejuvenate's Accept branch builds a fresh
        -- { answer, history } table and replaces the slot atomically
        -- rather than mutating in place, and the Reject branch is
        -- read-only. Any future code that mutates particle fields
        -- (e.g. appending to history) MUST deep-copy first or this
        -- will corrupt every aliased slot.
        local duplicated = {}
        for i = 1, N do duplicated[i] = false end

        if ess < thr * N then
            -- Resample both particles and their rewards in lockstep
            -- using the same multinomial indices. We do this via a
            -- paired array so mix-indexed sampling is impossible.
            local paired = {}
            for i = 1, N do paired[i] = { particle = particles[i], reward = rewards[i] } end
            local new_paired, drawn_indices = resample_multinomial(paired, weights)

            -- D_k membership (paper §3.4 Line 15): a slot i is a
            -- duplicate iff multiple new slots were drawn from the
            -- same original particle index. Count draws per original
            -- index, then mark any slot whose source was drawn >1 time.
            local draw_count = {}
            for _, idx in ipairs(drawn_indices) do
                draw_count[idx] = (draw_count[idx] or 0) + 1
            end

            local new_particles = {}
            local new_rewards   = {}
            for i = 1, N do
                new_particles[i] = new_paired[i].particle
                new_rewards[i]   = new_paired[i].reward
                duplicated[i]    = (draw_count[drawn_indices[i]] > 1)
            end
            particles = new_particles
            rewards   = new_rewards
            local uniform = {}
            for i = 1, N do uniform[i] = 1 / N end
            weights = uniform
            resample_count = resample_count + 1
        end

        -- Build selective MH filter (paper §3.4 Line 17 default:
        -- duplicated AND R < τ_R). Caller can replace via
        -- ctx.mh_filter_fn. Predicate errors are fatal — the filter
        -- decides cost, silent failure would mask bugs.
        local filter = {}
        for i = 1, N do
            local ok, active = pcall(mh_filter_fn, i, rewards[i], duplicated[i], mh_reward_threshold)
            if not ok then
                error("smc_sample.run: ctx.mh_filter_fn raised: " .. tostring(active), 2)
            end
            filter[i] = (active == true)
        end

        -- MH rejuvenation: S steps, selectively applied per filter.
        local rewards_prev = rewards  -- snapshot for optional post_mh_reweight
        for _s = 1, S_steps do
            local new_parts, new_rews, n_llm, n_rew, n_rej = mh_rejuvenate(
                particles, rewards, alpha, task, gen_tokens, reward_fn, filter)
            particles          = new_parts
            rewards            = new_rews
            total_llm_calls    = total_llm_calls + n_llm
            total_reward_calls = total_reward_calls + n_rew
            mh_rejected        = mh_rejected + n_rej
        end

        -- Optional INJECTABLE: legacy post-MH reweight (NOT paper-
        -- faithful; paper Algorithm 1 has no Line between 26 and the
        -- next iteration that rescales W). Enabled only when caller
        -- explicitly sets ctx.post_mh_reweight = true; when set, apply
        -- W_k ← W_{k-1} · exp(α · (r_post_S - r_pre_S)) and normalize.
        if post_mh_reweight then
            local unnorm = {}
            local sum = 0
            for i = 1, N do
                unnorm[i] = incremental_weight_update(weights[i], rewards[i], rewards_prev[i], alpha)
                sum = sum + unnorm[i]
            end
            if sum > 0 then
                for i = 1, N do weights[i] = unnorm[i] / sum end
            else
                -- Total-underflow fallback: reset to uniform.
                for i = 1, N do weights[i] = 1 / N end
            end
        end
    end

    -- ─── argmax selection ───
    -- Primary key: weight (Target I dominance selection — paper §3.3
    -- describes the reward-tilted posterior; argmax-weight on the
    -- block-SMC output is the standard MAP-style reduction).
    -- Tiebreak: higher reward wins (semantically preferred — equal-weight
    -- particles are observationally indistinguishable under the tempered
    -- potential ψ=exp(α·r), so we fall back to the raw reward signal
    -- rather than the arbitrary particle-index ordering).
    local argmax_i = 1
    local argmax_w = weights[1]
    local argmax_r = rewards[1]
    for i = 2, N do
        local wi = weights[i]
        if wi > argmax_w or (wi == argmax_w and rewards[i] > argmax_r) then
            argmax_w = wi
            argmax_r = rewards[i]
            argmax_i = i
        end
    end

    -- ─── Attach final reward / weight onto each particle for the shape ───
    local final_particles = {}
    for i = 1, N do
        final_particles[i] = {
            answer  = particles[i].answer,
            weight  = weights[i],
            reward  = rewards[i],
            history = particles[i].history or {},
        }
    end

    ctx.result = {
        answer         = particles[argmax_i].answer,
        particles      = final_particles,
        weights        = weights,
        iterations     = K,
        resample_count = resample_count,
        ess_trace      = ess_trace,
        stats          = {
            total_llm_calls    = total_llm_calls,
            total_reward_calls = total_reward_calls,
            mh_rejected        = mh_rejected,
        },
    }

    -- ─── Card emission (optional, fail-safe) ───
    if ctx.auto_card then
        local per_particle_list = {}
        for i = 1, N do
            per_particle_list[i] = {
                particle_idx = i,
                answer       = final_particles[i].answer,
                final_weight = final_particles[i].weight,
                final_reward = final_particles[i].reward,
                history      = final_particles[i].history,
            }
        end
        local card_id = emit_card(ctx, ctx.result, per_particle_list)
        ctx.result.card_id = card_id
        if card_id ~= nil and type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.info) == "function" then
            alc.log.info("smc_sample: card emitted — " .. tostring(card_id))
        end
    end

    -- ctx 中の関数は M.run 冒頭で strip 済み (error 経路でも clean を保証)。
    -- ctx.result は auto_card 分岐を含めて pure data のみで組み立てるため
    -- ここでの追加 strip は不要。
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    compute_weights           = compute_weights,
    compute_ess               = compute_ess,
    resample_multinomial      = resample_multinomial,
    mh_accept                 = mh_accept,
    incremental_weight_update = incremental_weight_update,
    -- LLM-integrated helpers (mockable via _G.alc stub)
    init_particles            = init_particles,
    evaluate_rewards          = evaluate_rewards,
    mh_rejuvenate             = mh_rejuvenate,
    build_refine_prompt       = build_refine_prompt,
    emit_card                 = emit_card,
}

-- Malli-style self-decoration: wrapper asserts ctx.result against
-- M.spec.entries.run.result ("smc_sampled") when ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
