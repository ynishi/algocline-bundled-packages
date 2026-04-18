---
name: usc
version: 0.1.0
category: aggregation
result_shape: "shape { candidates: array of string, n_sampled: number, selected_index?: number, selection: string }"
description: "Universal Self-Consistency — LLM-based consistency selection across free-form responses. Extends SC to open-ended tasks where majority vote is inapplicable."
source: usc/init.lua
generated: gen_docs (V0)
---

# USC — Universal Self-Consistency

> Extends standard Self-Consistency (SC) to free-form generation tasks. Instead of majority voting on extracted answers (which requires structured answer formats), USC concatenates all candidate responses and asks the LLM to select the most consistent one.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per candidate (default: 400) |
| `ctx.n` | number | optional | Number of candidate responses to sample (default: 5) |
| `ctx.select_tokens` | number | optional | Max tokens for selection response (default: 500) |
| `ctx.task` | string | **required** | The problem/question to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `candidates` | array of string | — | All sampled candidate responses |
| `n_sampled` | number | — | Number of candidates sampled |
| `selected_index` | number | optional | 1-based index parsed from the selection (nil if unparseable) |
| `selection` | string | — | LLM's consistency-selection response (analysis + chosen answer content) |
