---
name: analogical
version: 0.1.0
category: reasoning
result_shape: "shape { analogies: array of shape { problem: string, solution: string }, answer: string, patterns: string, total_analogies: number }"
description: "Analogical prompting — self-generate analogies, extract patterns, apply to original"
source: analogical/init.lua
generated: gen_docs (V0)
---

# Analogical — reasoning by self-generated analogies

> Instead of solving directly, generates relevant analogous problems, solves them, extracts transferable patterns, then applies to the original.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.domain_hint` | string | optional | Optional domain to draw analogies from |
| `ctx.n_analogies` | number | optional | Number of analogies to generate (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `analogies` | array of shape { problem: string, solution: string } | — | Self-generated analogous problems and their solutions |
| `answer` | string | — | Solution to the original problem produced by applying transferred patterns |
| `patterns` | string | — | Transferable reasoning patterns extracted from the analogies |
| `total_analogies` | number | — | Count of analogies actually generated |
