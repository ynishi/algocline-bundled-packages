---
name: s2a
version: 0.1.0
category: preprocessing
result_shape: "shape { answer: string, denoised_context: string, denoised_context_length: number, original_context_length: number }"
description: "System 2 Attention — strip irrelevant context before reasoning to reduce distraction and sycophancy"
source: s2a/init.lua
generated: gen_docs (V0)
---

# s2a — System 2 Attention: context denoising before reasoning

> Strips irrelevant, distracting, or misleading information from the input context, then re-answers using only the cleaned context. Dramatically reduces sycophancy and distraction effects.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.context` | string | optional | Full (potentially noisy) context to denoise; empty/absent => task itself is reformulated |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 500) |
| `ctx.task` | string | **required** | The question or task to answer |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer produced from the denoised context |
| `denoised_context` | string | — | LLM-denoised context (or reformulated task when no context given) |
| `denoised_context_length` | number | — | Length in chars of the denoised_context |
| `original_context_length` | number | — | Length in chars of the original context (or task when no context given) |
