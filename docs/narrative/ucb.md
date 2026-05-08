---
name: ucb
version: 0.1.0
category: selection
result_shape: "shape { best: string, ranking: array of shape { avg_score: number, hypothesis: string, pulls: number, rank: number } }"
description: "UCB1 hypothesis space exploration — generate, score, select, refine"
source: ucb/init.lua
generated: gen_docs (V0)
---

# ucb(UCB) — upper confidence bound hypothesis exploration

> Generates N candidate hypotheses, scores each with an LLM evaluator, and selects the best-scoring candidate using the UCB1 bandit formula. The top-ranked hypothesis is then refined over multiple rounds.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local ucb = require("ucb")
return ucb.run({ task = "Design a caching strategy for a REST API." })
```

## Algorithm {#algorithm}

1. **Generate** — produce N distinct hypotheses via independent LLM calls.
2. **Score** — rate each hypothesis (1-10) for quality, feasibility, and
   originality. Scores accumulate across rounds.
3. **UCB1 select** — choose the hypothesis with the highest UCB1 value:
   `UCB1(i) = avg_score(i) + sqrt(2 * ln(total_pulls + 1) / n_pulls(i))`.
   A hypothesis with zero pulls returns `+inf`, ensuring each is sampled
   at least once.
4. **Refine** — rewrite the selected hypothesis, then repeat from step 2
   for the remaining rounds.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n` | number | optional | Number of hypotheses to generate (default: 3) |
| `ctx.rounds` | number | optional | Number of evaluate+refine rounds (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Highest avg-scored hypothesis after rounds |
| `ranking` | array of shape { avg_score: number, hypothesis: string, pulls: number, rank: number } | — | Full ranking sorted by average score descending |
