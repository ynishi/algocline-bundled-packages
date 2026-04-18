---
name: cod
version: 0.1.0
category: optimization
result_shape: "shape { compression_ratio: number, history: array of shape { round: number, summary: string, word_count: number }, input_words: number, output: string, output_words: number, total_rounds: number }"
description: "Chain-of-Density — iterative information densification with fidelity preservation"
source: cod/init.lua
generated: gen_docs (V0)
---

# CoD — Chain-of-Density iterative compression

> Iteratively rewrites text to increase information density while maintaining length. Each round adds missing entities/details and removes filler, producing progressively denser output.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per round (default: 400) |
| `ctx.rounds` | number | optional | Number of densification rounds (default: 3) |
| `ctx.target_length` | number | optional | Approximate target length in words (default: auto ~1/3 of input) |
| `ctx.text` | string | **required** | Source text to compress (uses ctx.text, not ctx.task) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `compression_ratio` | number | — | output_words / input_words (0 when input_words == 0) |
| `history` | array of shape { round: number, summary: string, word_count: number } | — | Per-round history starting with round 0 (initial sparse summary) |
| `input_words` | number | — | Word count of original source text |
| `output` | string | — | Final densified summary after all rounds |
| `output_words` | number | — | Word count of final densified summary |
| `total_rounds` | number | — | Number of densification rounds executed (excludes round 0) |
