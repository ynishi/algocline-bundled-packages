---
name: rstar
version: 0.1.0
category: reasoning
result_shape: "shape { agreement: one_of(\"full\", \"partial\", \"none\"), answer: string, path_a: shape { conclusion: string, reasoning: string }, path_b: shape { conclusion: string, reasoning: string }, resolution_needed: boolean, verification: shape { a_agrees_b: boolean, a_checks_b: string, b_agrees_a: boolean, b_checks_a: string } }"
description: "Mutual reasoning verification — two paths cross-verify each other for efficient accuracy"
source: rstar/init.lua
generated: gen_docs (V0)
---

# rstar — Mutual reasoning verification via self-play

> Generates two independent reasoning paths, then each path verifies the other. Disagreements trigger a resolution round. Achieves MCTS-level accuracy at a fraction of the cost by replacing tree search with targeted mutual critique.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per reasoning path (default: 400) |
| `ctx.task` | string | **required** | The problem to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per cross-verification (default: 300) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `agreement` | one_of("full", "partial", "none") | — | Agreement level between path_a and path_b |
| `answer` | string | — | Final answer (from agreement or resolution) |
| `path_a` | shape { conclusion: string, reasoning: string } | — | Path A (first-principles approach) |
| `path_b` | shape { conclusion: string, reasoning: string } | — | Path B (multi-angle approach) |
| `resolution_needed` | boolean | — | Whether a resolution LLM call was issued |
| `verification` | shape { a_agrees_b: boolean, a_checks_b: string, b_agrees_a: boolean, b_checks_a: string } | — | Cross-verification outputs |
