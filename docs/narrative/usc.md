---
name: usc
version: 0.1.0
category: aggregation
result_shape: "shape { candidates: array of string, n_sampled: number, selected_index?: number, selection: string }"
description: "Universal Self-Consistency — LLM-based consistency selection across free-form responses. Extends SC to open-ended tasks where majority vote is inapplicable."
source: usc/init.lua
generated: gen_docs (V0)
---

# usc(USC) — Universal Self-Consistency for free-form generation

> Extends standard Self-Consistency (SC) to free-form generation tasks. Instead of majority voting on extracted answers (which requires structured answer formats), USC concatenates all candidate responses and asks the LLM to select the most consistent one. Mathematically, majority vote is a special case of USC where the consistency function is exact string match.

## Contents

- [Usage](#usage)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local usc = require("usc")
return usc.run(ctx)
```

## Comparison with related packages {#comparison-with-related-packages}

- `sc` — extracts short answers, clusters by string similarity, and
  majority votes. Only works when answers have a canonical form
  (numbers, options, etc.).
- `usc` — presents all full responses to the LLM and asks it to
  judge consistency. Works on any task: open-ended QA,
  summarization, code generation, etc.

## References {#references}

- Chen, X. et al. (2024). "Universal Self-Consistency for Large
  Language Model Generation". ICML 2024 (Google DeepMind).
  https://arxiv.org/abs/2311.17311
ctx.select_tokens: Max tokens for selection response (default: 500)

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
