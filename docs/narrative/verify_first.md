---
name: verify_first
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, candidate_source: string, extracted_answer: string, history: array of shape { extracted_answer: string, input_candidate: string, round: number, verification: string }, iterations: number }"
description: "Verification-First prompting — verify a candidate answer before generating, reducing logical errors via reverse reasoning"
source: verify_first/init.lua
generated: gen_docs (V0)
---

# verify_first — Verification-First prompting

> Provides a candidate answer (trivial, random, or CoT-generated), then instructs the LLM to verify it before generating the real answer. "Reverse reasoning" is cognitively easier than forward generation and reduces logical errors by overcoming egocentric bias.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.candidate` | string | optional | Pre-supplied candidate answer (default: nil => auto-generate) |
| `ctx.gen_tokens` | number | optional | Max tokens for candidate generation (default: 600) |
| `ctx.iterations` | number | optional | Number of Iter-VF rounds (default: 1) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.trivial` | boolean | optional | Use trivial candidate '1' instead of CoT (default: false) |
| `ctx.verify_tokens` | number | optional | Max tokens per verification round (default: 800) |
