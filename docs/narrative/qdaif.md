---
name: qdaif
version: 0.1.0
category: exploration
result_shape: "shape { archive: array of shape { candidate: string, cell: string, features: array of string, score: number }, best?: string, best_score: number, coverage: number, stats: shape { filled_cells: number, iterations: number, seed_count: number, total_cells: number } }"
description: "Quality-Diversity through AI Feedback — MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification. Produces diverse, high-quality solution populations."
source: qdaif/init.lua
generated: gen_docs (V0)
---

# qdaif — Quality-Diversity through AI Feedback

> Maintains a MAP-Elites archive (feature-space × quality grid) using only LLM calls. Generates diverse, high-quality solutions by: (1) seeding the archive, (2) selecting elites, (3) mutating via LLM, (4) evaluating quality and feature placement via LLM, (5) inserting into the archive if superior.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.elite_tokens` | number | optional | Max tokens for candidate generation (default: 400) |
| `ctx.features` | array of shape { bins: array of string, name: string } | **required** | Feature axes defining the MAP-Elites grid |
| `ctx.iterations` | number | optional | Mutation-evaluation cycles (default: 20) |
| `ctx.seed_count` | number | optional | Initial candidates to generate (default: 5) |
| `ctx.task` | string | **required** | Problem / domain description |
