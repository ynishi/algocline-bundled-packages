---
name: ab_select
version: 0.1.0
category: selection
result_shape: "shape { best: string, best_index: number, best_score: number, budget: number, budget_used: number, candidates: array of string, ranking: array of shape { alpha: number, beta: number, evaluations: table, index: number, n_evals: number, posterior_mean: number }, rounds: array of shape { alpha: number, beta: number, budget_used: number, candidate: number, cost: number, iteration: number, level: number, level_name: string, score: number, score_norm: number, theta_pick: number }, total_llm_calls: number }"
description: "Multi-fidelity Thompson sampling over a fixed candidate pool."
source: ab_select/init.lua
generated: gen_docs (V0)
---

# ab_select(AB-Select) — multi-fidelity Thompson sampling for candidate selection

> Selects the best candidate from a fixed pool using staged evaluators of increasing cost. Thompson Sampling decides which candidate receives the next, more expensive evaluation, allocating expensive evaluators only to candidates whose Beta posterior suggests they are promising.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local ab_select = require("ab_select")
return ab_select.run(ctx)
```

## Algorithm {#algorithm}

AB-MCTS adapted to a fixed pool (no GEN node, no kill):

1. Generate N candidate answers from `ctx.task`.
2. Initialize Beta(α₀, β₀) per candidate.
3. While budget remains and at least one candidate has an unevaluated
   level affordable under remaining budget:
   - Sample θᵢ ~ Beta(αᵢ, βᵢ) for each affordable candidate.
   - Pick i* = argmax θᵢ.
   - Evaluate i* at its lowest unevaluated fidelity level.
   - Normalize: s = clamp(score / score_hi, 0, 1).
   - Bayesian update: αᵢ ← αᵢ + s ; βᵢ ← βᵢ + (1 - s).
4. Rank by posterior mean αᵢ / (αᵢ + βᵢ); return best.

## Caveats {#caveats}

There is no mid-flight kill. Thompson Sampling naturally starves
candidates with low posteriors by reducing the probability they are
picked. AB-MCTS (Inoue et al.) does not include a kill mechanism, and
our calibration analysis shows that any fixed credible-bound threshold
is depth-dependent and statistically unsound. See `pairwise_rank` /
`listwise_rank` / `setwise_rank` for theory-backed pruning when
calibration of absolute scores cannot be assumed.

## Comparison with related packages {#comparison-with-related-packages}

- `ab_mcts` builds reasoning paths in a tree; uses an LLM both to
  generate new nodes and evaluate them (2*B+1 LLM calls). Answers
  "what is a good reasoning path?".
- `gumbel_search` uses a fixed flat pool with a single evaluator and
  Sequential Halving. Cannot exploit a cheap-vs-expensive evaluator
  structure.
- `mbr_select` uses a fixed flat pool with pairwise similarity and no
  budget allocation.
- `ab_select` uses a fixed flat pool with a multi-fidelity evaluator
  cascade (cheap → expensive). Thompson Sampling allocates the
  expensive evaluator only to candidates worth the cost.
  Multi-fidelity is the unique axis vs every other selection package
  in this repository.

## References {#references}

- Inoue, Y. et al. (2025). "Wider or Deeper? Scaling LLM
  Inference-Time Compute with Adaptive Branching Tree Search".
  NeurIPS 2025 Spotlight. https://arxiv.org/abs/2503.04412

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
