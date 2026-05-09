---
name: smc_sample
version: 0.1.0
category: selection
result_shape: smc_sampled
description: "Block-level Sequential Monte Carlo sampling for LLM quality (Markovic-Voronov et al. 2026, arXiv:2604.16453). Reward-weighted importance sampling with ESS-triggered multinomial resampling and Metropolis-Hastings rejuvenation. Caller-injected reward_fn (unit-test / LLM judge / scoring rule) drives the Target I tempered potential ψ=exp(α·r). Default (N=16,K=4,S=2) issues 208 LLM calls per run."
source: smc_sample/init.lua
generated: gen_docs (V0)
---

# smc_sample(SMCSample) — Sequential Monte Carlo (block-SMC) sampling for LLM quality

> Implements the paper's Target I (prefix-only variant) of the reward-augmented target distribution abstracted to the BLOCK level so it runs on top of algocline's block-granular `alc.llm` API (token logprobs are not exposed). Under the Target I specialization the incremental weights depend only on the reward potentials and the base-model likelihood term cancels (paper §3.3 / Appendix A.4 Lemma 4).

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Injection points](#injection-points)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local smc = require("smc_sample")
return smc.run({
    task      = "Write a Python function sum_list(xs).",
    reward_fn = function(answer, task)
        -- caller-injected verifier: unit-test / LLM judge / scoring_rule
        return score_in_unit_interval
    end,
    -- all hyperparameters optional (M._defaults applies)
})
```

## Theoretical foundations {#theoretical-foundations}

```math
Π(x_{1:T} | q) ∝ ∏_t m_t(x_t | q, x_{<t}) · ∏_t ψ_t(x_{1:t}, q)
w_k = Ψ_k / Ψ_{k-1} = exp(α · (r_new - r_prev))
```

block-SMC abstraction:

- 1 particle = 1 complete answer (single `alc.llm` call).
- `ψ_t = exp(α · r(answer))` where `r` is the caller-injected
  `reward_fn`.
- K rounds: `{ESS resample, MH rejuvenation, weight-update}`
  repeated.

## Injection points {#injection-points}

Implementation follows paper §3.4 Algorithm 1 under the block-SMC
specialization of §A.4. The default path is paper-faithful; all
deviations are opt-in via explicit `ctx` knobs.

Paper-faithful defaults:

- Weight update runs only at init and on ESS-triggered resample.
  Between iterations, under fixed `α` the Target I incremental
  ratio is identically 1, so no between-iter reweight is applied.
- MH rejuvenation is selective: a slot receives an MH proposal iff
  it is a duplicate from the most recent resample and its reward is
  below `τ_R`.
- `α` is fixed globally (paper §4.1 Setup).

Injection points:

- `reward_fn` — REQUIRED. `(answer, task) → ℝ⁺ ∪ {0}`. Caller's
  verifier (unit test / LLM judge / scoring rule).
- `proposal_fn` — v2 opt-in (currently warning-then-ignore in v1).
- `mh_filter_fn` — `(idx, reward, was_duplicated, τ_R) → boolean`
  override of the paper's selective predicate. Use
  `function() return true end` for the legacy "MH every particle"
  variant (higher cost, correctness-preserving).
- `mh_reward_threshold` — `τ_R` cutoff for the default filter
  (default `0.5` for `[0, 1]` rewards; binary graders should set
  `1.0`).
- `post_mh_reweight` — `true` applies a legacy `exp(α·Δr)` reweight
  after each iteration's MH. **Not paper-faithful** — injects a
  reward-gain bias. Kept only for reproducing pre-0.2.0 runs.

## Caveats {#caveats}

With defaults (`N=16, K=4, S=2`) the entry can issue up to
`N + K·N·(1+S) = 208` LLM calls (the paper's HumanEval 87.8%
setting). Lightweight callers should override `n_particles` /
`n_iterations` / `rejuv_steps` (e.g. `N=4, K=2, S=1 → 20 calls`).
Paper-faithful selective MH typically runs MH only on iterations
where ESS-resample fires, so `total_llm_calls` is input-dependent
and often much less than the worst case.

## Comparison with related packages {#comparison-with-related-packages}

Category: selection (alongside `sc`, `usc`, `mbr_select`,
`diverse`, `ab_select`, `gumbel_search`). Encompasses `sc`
(`α = 0`, equal-weight) and `mbr_select` (similarity reward, 1
iteration) as special cases of the same probabilistic framework.

## References {#references}

- Markovic-Voronov, ... et al. (2026). "Sampling for Quality:
  Training-Free Reward-Guided LLM Decoding via Sequential Monte
  Carlo". https://arxiv.org/abs/2604.16453

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha` | number | optional | Tempering strength (default: 4.0) |
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'smc_sample_<task_hash>') |
| `ctx.ess_threshold` | number | optional | ESS trigger ratio (default: 0.5) |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 600) |
| `ctx.mh_filter_fn` | any | optional | Caller override for paper §3.4 Line 17 selective-MH predicate. Signature: (idx, reward, was_duplicated, τ_R) → boolean. Default: duplicated AND reward < τ_R. Use `function() return true end` for the legacy apply-MH-to-all variant (higher LLM cost). |
| `ctx.mh_reward_threshold` | number | optional | τ_R cutoff for the default selective-MH predicate (paper §3.4 Line 17). Default: 0.5. |
| `ctx.n_iterations` | number | optional | K SMC iterations (default: 4) |
| `ctx.n_particles` | number | optional | N particles (default: 16, paper §4.1) |
| `ctx.post_mh_reweight` | boolean | optional | Opt into the legacy exp(α·Δr) post-MH reweight (NOT paper-faithful — reward-gain bias). Default: false. Kept only for pre-0.2.0 run reproduction. |
| `ctx.rejuv_steps` | number | optional | S MH rejuvenation steps (default: 2) |
| `ctx.reward_fn` | any | **required** | Caller-injected fn(answer, task) → number ∈ [0, +∞). unit-test / LLM judge / scoring_rule. Runtime type-checked. |
| `ctx.scenario_name` | string | optional | Explicit scenario name for the emitted Card |
| `ctx.task` | string | **required** | Problem statement fed to the base LLM + reward_fn |

## Result {#result}

Returns `smc_sampled` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Argmax-weight particle's answer text |
| `card_id` | string | optional | Emitted Card id (only when auto_card=true) |
| `ess_trace` | array of number | — | ESS recorded at the start of each iteration (length K) |
| `iterations` | number | — | K SMC rounds actually executed |
| `particles` | array of shape { answer: string, history: array of table, reward: number, weight: number } | — | All N particles in their final state |
| `resample_count` | number | — | Number of iterations that triggered multinomial resample |
| `stats` | shape { total_llm_calls: number, total_reward_calls: number } | — | Execution counters (open for diagnostics like mh_rejected) |
| `weights` | array of number | — | Final normalized weights (Σ ≈ 1) |
