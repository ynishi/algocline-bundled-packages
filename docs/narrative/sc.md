---
name: sc
version: 0.2.0
category: aggregation
result_shape: voted
description: "Independent multi-path sampling with majority vote aggregation"
source: sc/init.lua
generated: gen_docs (V0)
---

# SC — Self-Consistency: independent sampling with majority vote

> Samples multiple reasoning paths for the same problem, then selects the most consistent answer by majority voting.

## Contents

- [Result](#result)

## Result {#result}

Returns `voted` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | optional | Majority answer (nil when no paths converge) |
| `answer_norm` | string | optional | Normalized vote key |
| `consensus` | string | — | LLM-synthesized majority summary |
| `n_sampled` | number | — | Number of sampled paths |
| `paths` | array of shape { answer: string, reasoning: string } | — | Per-path reasoning + extracted answer |
| `total_llm_calls` | number | — |  |
| `vote_counts` | map of string to number | — | { [norm] = count } tally |
| `votes` | array of string | — | Normalized vote per path, 1-indexed |
