---
name: gumbel_search
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_index: number, best_score: number, candidates: array of shape { index: number, mean_score: number, n_evals: number }, halving_rounds: number, total_evaluations: number, total_llm_calls: number }"
description: "Budget-optimal search via Sequential Halving and Gumbel Top-k sampling."
source: gumbel_search/init.lua
generated: gen_docs (V0)
---

# gumbel_search(GumbelSearch) — Gumbel Top-k + Sequential Halving budget-optimal search

> Budget-optimal tree search that combines Gumbel Top-k for unbiased candidate sampling without replacement and Sequential Halving for optimal budget allocation when comparing candidates.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local gs = require("gumbel_search")
return gs.run(ctx)
```

## Theoretical foundations {#theoretical-foundations}

- Sequential Halving achieves an `O(N/log N)` simple-regret bound
  (Karnin et al., 2013) and is optimal among algorithms that do not
  use arm means.
- Gumbel Top-k provides unbiased non-replacement sampling from
  categorical distributions (Kool et al., 2019); equivalent to
  sorting by value plus Gumbel noise.
- The combination is fixed-budget optimal pure exploration; best when
  the question is "I have exactly B evaluation budget, find the best
  answer." Outperforms standard decoding with 5-15 simulations
  (~500 tokens).

## Comparison with related packages {#comparison-with-related-packages}

- `ab_mcts` — Thompson Sampling with adaptive branching; Beta
  posteriors need multiple visits and benefit from unlimited budget.
- `tot` — fixed DFS/BFS; structured but budget allocation is not
  optimized.
- `gumbel_search` — fixed-budget optimal pure exploration via
  Sequential Halving + Gumbel Top-k.

## References {#references}

- "Revisiting Tree Search for LLMs: Gumbel and Sequential Halving for
  Budget-Scalable Reasoning" (2026). https://arxiv.org/abs/2603.21162
- Karnin, Z. et al. (2013). "Almost Optimal Exploration in
  Multi-Armed Bandits". ICML 2013.
- Kool, W. et al. (2019). "Stochastic Beams and Where to Find Them".

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
