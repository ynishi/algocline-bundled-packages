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
--- likelihood term cancels (paper §4.2-§4.3):
---     w_i ← w_i · exp(α · (r_new - r_prev))
---
--- block-SMC abstraction:
---   * 1 particle = 1 complete answer (`alc.llm` single call)
---   * ψ_t       = exp(α · r(answer))   where r = caller-injected reward_fn
---   * K rounds  = {weight-update, ESS resample, MH rejuvenation} repeated
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
    n_particles   = 16,    -- N (paper §4.1)
    n_iterations  = 4,     -- K SMC rounds
    alpha         = 4.0,   -- tempering strength (ψ = exp(α · r))
    ess_threshold = 0.5,   -- resample when ESS < threshold · N
    rejuv_steps   = 2,     -- S Metropolis-Hastings rejuvenation steps
    gen_tokens    = 600,   -- max tokens per LLM call (code-gen default)
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
--- The returned array contains copies of `particles[k]` entries selected
--- by the multinomial draw. After resampling, caller should reset all
--- weights to 1/N (degeneracy reset per paper §3.4).
---
---@param particles any[]
---@param weights number[]
---@param rng nil|fun():number  -- test injection; default math.random
---@return any[]
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
    end

    -- Internal invariant: multinomial resample must preserve particle
    -- count. Violating this is a bug in the loop above, not a caller
    -- contract issue.
    assert(#out == n, "internal: resample must preserve N")
    return out
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

--- incremental_weight_update — Target I SMC incremental weight (paper §4.3).
---
---     w_i ← w_i · ψ_t / ψ_{t-1}
---     block-SMC: ψ_t = exp(α · r(answer_i))
---       ⇒ w_i ← w_i · exp(α · (r_new - r_prev))
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

    local particles = {}
    for i = 1, n do
        particles[i] = {
            answer  = tostring(answers[i] or ""),
            history = {},  -- 1-slot convention: {prev_answer, prev_reward}
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
--- Returns:
---   new_particles, new_rewards,
---   n_proposal_llm_calls (successful proposals only),
---   n_reward_calls, n_rejected
local function mh_rejuvenate(particles, rewards, alpha, task, gen_tokens, reward_fn)
    local n = #particles

    -- Stage 1: propose (parallel LLM calls). Each entry is either a
    -- string (successful proposal) or nil (failure → reject).
    local proposals = map_or_serial(particles, function(p, _i)
        local ok, resp = pcall(alc.llm,
            build_refine_prompt(p.answer, task),
            { max_tokens = gen_tokens })
        if not ok then return nil end
        if type(resp) ~= "string" or resp == "" then return nil end
        return resp
    end)

    -- Count successful proposal LLM calls. The pcall-failed entries
    -- don't count because they represent failed invocations, not
    -- successful LLM calls.
    local n_proposal_llm_calls = 0
    for i = 1, n do
        if proposals[i] ~= nil then n_proposal_llm_calls = n_proposal_llm_calls + 1 end
    end

    -- Stage 2: reward-evaluate the (non-nil) proposals. We evaluate
    -- every proposal that arrived, even if MH later rejects it — the
    -- reward is needed for the acceptance ratio.
    local prop_particles = {}
    for i = 1, n do
        prop_particles[i] = { answer = proposals[i] or particles[i].answer, history = {} }
    end
    local prop_rewards = evaluate_rewards(prop_particles, task, reward_fn)
    local n_reward_calls = n

    -- Stage 3: acceptance test per particle.
    --
    -- Under v1 symmetric-q assumption (q(x|x') = q(x'|x) = 1.0), the
    -- 4-arg mh_accept collapses to a ratio test on the target density
    -- π, which itself is the tempered potential ψ = exp(α·r). We pass
    -- ψ directly instead of the full (often un-normalizable) Π so the
    -- numerator / denominator cancel their shared base-model factor —
    -- this is precisely the Target I property paper §4.2 exploits.
    local new_particles = {}
    local new_rewards = {}
    local n_rejected = 0
    for i = 1, n do
        if proposals[i] == nil then
            -- Failed proposal → retain current, count as reject.
            new_particles[i] = particles[i]
            new_rewards[i]   = rewards[i]
            n_rejected = n_rejected + 1
        else
            local psi_x      = math.exp(alpha * rewards[i])
            local psi_xprime = math.exp(alpha * prop_rewards[i])
            if mh_accept(psi_x, psi_xprime, 1.0, 1.0) then
                -- Accept: keep a 1-slot history snapshot of the old
                -- particle for diagnostic trace (Risks #5).
                local new_p = {
                    answer  = prop_particles[i].answer,
                    history = { { answer = particles[i].answer, reward = rewards[i] } },
                }
                new_particles[i] = new_p
                new_rewards[i]   = prop_rewards[i]
            else
                new_particles[i] = particles[i]
                new_rewards[i]   = rewards[i]
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

    local ess_trace = result.ess_trace or {}
    local final_ess = ess_trace[#ess_trace]

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
-- M.run — block-SMC orchestration (paper §4, Target I specialization)
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

    -- ─── Resolve hyperparameters from ctx + M._defaults ───
    local N          = ctx.n_particles or M._defaults.n_particles
    local K          = ctx.n_iterations or M._defaults.n_iterations
    local alpha      = ctx.alpha or M._defaults.alpha
    local thr        = ctx.ess_threshold or M._defaults.ess_threshold
    local S_steps    = ctx.rejuv_steps or M._defaults.rejuv_steps
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens

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

    -- v1: proposal_fn caller injection not yet supported (issue §13.5).
    -- Warn (not error) so callers who pre-configure for v2 aren't hard-
    -- rejected — their proposal_fn is simply ignored in v1.
    if ctx.proposal_fn ~= nil then
        if type(alc) == "table" and type(alc.log) == "table"
                and type(alc.log.warn) == "function" then
            alc.log.warn(
                "smc_sample.run: ctx.proposal_fn is ignored in v1 "
                .. "(LLM-refine proposal is fixed). v2 will opt in.")
        end
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

    -- ─── K-iteration SMC main loop ───
    for _k = 1, K do
        local ess = compute_ess(weights)
        ess_trace[#ess_trace + 1] = ess

        -- Resample trigger: ESS < thr · N. On fire, reset weights to
        -- 1/N (paper §3.4 degeneracy reset). Rewards are re-indexed to
        -- the resampled particles so incremental_weight_update has a
        -- valid "prev" baseline on the next weight update.
        if ess < thr * N then
            -- Resample both particles and their rewards in lockstep
            -- using the same multinomial indices. We do this via a
            -- paired array so mix-indexed sampling is impossible.
            local paired = {}
            for i = 1, N do paired[i] = { particle = particles[i], reward = rewards[i] } end
            local new_paired = resample_multinomial(paired, weights)
            local new_particles = {}
            local new_rewards   = {}
            for i = 1, N do
                new_particles[i] = new_paired[i].particle
                new_rewards[i]   = new_paired[i].reward
            end
            particles = new_particles
            rewards   = new_rewards
            local uniform = {}
            for i = 1, N do uniform[i] = 1 / N end
            weights = uniform
            resample_count = resample_count + 1
        end

        -- MH rejuvenation: S steps, each step proposes + accepts/rejects
        -- every particle. Rewards returned by mh_rejuvenate already
        -- account for the accept/reject outcome (accepted proposals
        -- get the proposal's reward, rejected particles keep theirs).
        local rewards_prev = rewards
        for _s = 1, S_steps do
            local new_parts, new_rews, n_llm, n_rew, n_rej = mh_rejuvenate(
                particles, rewards, alpha, task, gen_tokens, reward_fn)
            particles          = new_parts
            rewards            = new_rews
            total_llm_calls    = total_llm_calls + n_llm
            total_reward_calls = total_reward_calls + n_rew
            mh_rejected        = mh_rejected + n_rej
        end

        -- Incremental Target I weight update (paper §4.3):
        -- w_i ← w_i · exp(α · (r_new - r_prev)), then renormalize.
        local unnorm = {}
        local sum = 0
        for i = 1, N do
            unnorm[i] = incremental_weight_update(weights[i], rewards[i], rewards_prev[i], alpha)
            sum = sum + unnorm[i]
        end
        if sum > 0 then
            for i = 1, N do weights[i] = unnorm[i] / sum end
        else
            -- Total-underflow fallback: if every unnormalized weight
            -- underflowed, reset to uniform. Same reasoning as the
            -- numerical guard in compute_weights.
            for i = 1, N do weights[i] = 1 / N end
        end
    end

    -- ─── argmax selection ───
    local argmax_i = 1
    local argmax_w = weights[1]
    for i = 2, N do
        if weights[i] > argmax_w then
            argmax_w = weights[i]
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

    -- Strip caller-injected Lua closures before returning so that MCP
    -- boundaries (alc_run JSON encoding) can serialize ctx. `reward_fn` /
    -- `proposal_fn` are input contracts, not part of the strategy output —
    -- leaving them in `ctx` causes "function cannot be JSON-serialized"
    -- errors at the algocline MCP response boundary (observed in E2E
    -- 2026-04-22 run_id 122845). ctx.result is unaffected.
    ctx.reward_fn = nil
    ctx.proposal_fn = nil

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
