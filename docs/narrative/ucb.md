---
name: ucb
version: 0.1.0
category: selection
result_shape: "shape { best: string, ranking: array of shape { avg_score: number, hypothesis: string, pulls: number, rank: number } }"
description: "UCB1 hypothesis space exploration — generate, score, select, refine"
source: ucb/init.lua
generated: gen_docs (V0)
---

# UCB — UCB1 hypothesis space exploration

> Generates multiple hypotheses, scores them with UCB1, refines the best.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n` | number | optional | Number of hypotheses to generate (default: 3) |
| `ctx.rounds` | number | optional | Number of evaluate+refine rounds (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
