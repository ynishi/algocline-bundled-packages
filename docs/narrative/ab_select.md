---
name: ab_select
version: 0.1.0
category: selection
result_shape: "shape { best: string, best_index: number, best_score: number, budget: number, budget_used: number, candidates: array of string, ranking: array of shape { alpha: number, beta: number, evaluations: table, index: number, n_evals: number, posterior_mean: number }, rounds: array of shape { alpha: number, beta: number, budget_used: number, candidate: number, cost: number, iteration: number, level: number, level_name: string, score: number, score_norm: number, theta_pick: number }, total_llm_calls: number }"
description: "Adaptive Branching Selection — multi-fidelity Thompson sampling over a fixed candidate pool. Allocates expensive evaluators only to promising candidates. Unique multi-fidelity axis vs other selection packages."
source: ab_select/init.lua
generated: gen_docs (V0)
---

# ab_select — Adaptive Branching Selection (multi-fidelity Thompson sampling)

> Selects the best candidate from a pool using staged evaluators of increasing cost. Thompson Sampling decides which candidate receives the next, more expensive evaluation, allocating expensive evaluations only to candidates whose Beta posterior suggests they are promising.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha_prior` | number | optional | Beta prior α (default: 1.0) |
| `ctx.beta_prior` | number | optional | Beta prior β (default: 1.0) |
| `ctx.budget` | number | optional | Total fidelity-cost budget (default: 18) |
| `ctx.fidelities` | array of shape { cost: number, max_tokens: number, name: string, prompt: string } | optional | Override the evaluator ladder (default: 3-level quick/detail/thorough) |
| `ctx.gen_tokens` | number | optional | Max tokens per candidate generation (default: 400) |
| `ctx.n` | number | optional | Number of initial candidates (default: 6) |
| `ctx.score_hi` | number | optional | Maximum raw score for normalization (default: 10) |
| `ctx.seed` | number | optional | PRNG seed for Thompson sampling (default: 1) |
| `ctx.task` | string | **required** | The problem to generate and select an answer for |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Text of the winning candidate |
| `best_index` | number | — | 1-based index of the winner |
| `best_score` | number | — | Posterior mean of the winner |
| `budget` | number | — | Total fidelity-cost budget supplied |
| `budget_used` | number | — | Total fidelity cost consumed |
| `candidates` | array of string | — | All generated candidate texts |
| `ranking` | array of shape { alpha: number, beta: number, evaluations: table, index: number, n_evals: number, posterior_mean: number } | — | All candidates sorted by posterior mean descending |
| `rounds` | array of shape { alpha: number, beta: number, budget_used: number, candidate: number, cost: number, iteration: number, level: number, level_name: string, score: number, score_norm: number, theta_pick: number } | — | Per-iteration Thompson sampling trace |
| `total_llm_calls` | number | — | Generation calls + evaluation calls |
