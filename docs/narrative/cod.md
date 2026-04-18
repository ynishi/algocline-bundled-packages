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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per round (default: 400) |
| `ctx.rounds` | number | optional | Number of densification rounds (default: 3) |
| `ctx.target_length` | number | optional | Approximate target length in words (default: auto ~1/3 of input) |
| `ctx.text` | string | **required** | Source text to compress (uses ctx.text, not ctx.task) |
