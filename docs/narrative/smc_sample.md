---
name: smc_sample
version: 0.1.0
category: selection
result_shape: smc_sampled
description: "Block-level Sequential Monte Carlo sampling for LLM quality (Markovic-Voronov et al. 2026, arXiv:2604.16453). Reward-weighted importance sampling with ESS-triggered multinomial resampling and Metropolis-Hastings rejuvenation. Caller-injected reward_fn (unit-test / LLM judge / scoring rule) drives the Target I tempered potential ψ=exp(α·r). Default (N=16,K=4,S=2) issues 208 LLM calls per run."
source: smc_sample/init.lua
generated: gen_docs (V0)
---

# smc_sample — Sequential Monte Carlo (block-SMC) sampling for LLM quality.

> Based on: Markovic-Voronov et al., "Sampling for Quality: Training-Free Reward-Guided LLM Decoding via Sequential Monte Carlo" (arXiv:2604.16453v1, 2026-04-07).

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha` | number | optional | Tempering strength (default: 4.0) |
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'smc_sample_<task_hash>') |
| `ctx.ess_threshold` | number | optional | ESS trigger ratio (default: 0.5) |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 600) |
| `ctx.n_iterations` | number | optional | K SMC iterations (default: 4) |
| `ctx.n_particles` | number | optional | N particles (default: 16, paper §4.1) |
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
