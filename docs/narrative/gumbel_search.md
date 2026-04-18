---
name: gumbel_search
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_index: number, best_score: number, candidates: array of shape { index: number, mean_score: number, n_evals: number }, halving_rounds: number, total_evaluations: number, total_llm_calls: number }"
description: "Budget-optimal tree search — Sequential Halving for optimal budget allocation + Gumbel Top-k for unbiased sampling. Provably minimizes simple regret under fixed evaluation budget."
source: gumbel_search/init.lua
generated: gen_docs (V0)
---

# gumbel_search — Gumbel Top-k + Sequential Halving Tree Search

> Budget-optimal tree search that combines two theoretically grounded techniques: Gumbel Top-k for unbiased candidate sampling without replacement, and Sequential Halving for optimal budget allocation when comparing candidates.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.eval_tokens` | number | optional | Max tokens for evaluation (default: 100) |
| `ctx.gen_tokens` | number | optional | Max tokens for generation (default: 400) |
| `ctx.initial_candidates` | number | optional | Number of initial candidates (default: 8) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Winning candidate's response text |
| `best_index` | number | — | 1-based index of the winning candidate |
| `best_score` | number | — | Final mean score of the winner in [0,1] |
| `candidates` | array of shape { index: number, mean_score: number, n_evals: number } | — | All candidates' final state (order preserved from generation) |
| `halving_rounds` | number | — | Number of Sequential Halving rounds executed |
| `total_evaluations` | number | — | Total per-candidate evaluations across rounds |
| `total_llm_calls` | number | — | Total LLM calls (generation + evaluations) |
