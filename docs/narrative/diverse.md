---
name: diverse
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_avg_score: number, best_path_id: number, paths: array of shape { path_id: number, reasoning: string, verification: shape { avg_score: number, step_scores: array of shape { score: number, step: string }, total_score: number } }, ranking: array of shape { avg_score: number, path_id: number, rank: number, steps_verified: number } }"
description: "DiVERSe — diverse reasoning paths with step-level verification and selection"
source: diverse/init.lua
generated: gen_docs (V0)
---

# DiVERSe — diverse reasoning paths with step-level verification

> Generates multiple diverse reasoning paths, then verifies each path at the step level (not just the final answer). Selects the path with the highest step-level verification score.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n_paths` | number | optional | Number of diverse reasoning paths (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |
