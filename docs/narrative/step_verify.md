---
name: step_verify
version: 0.1.0
category: validation
result_shape: "shape { answer: string, rounds: array of shape { error_at?: number, round: number, steps: array of shape { correct: boolean, explanation: string, step: string }, verified_count: number }, total_llm_calls: number, total_rounds: number, total_verified: number, verified_steps: array of string }"
description: "Step-level reasoning verification — PRM-style LLM-as-Verifier that scores each reasoning step independently. Identifies the first point of failure and re-derives from the last correct step."
source: step_verify/init.lua
generated: gen_docs (V0)
---

# step_verify — Step-Level Verification (PRM-style, LLM-as-Verifier)

> Verifies each intermediate reasoning step independently, identifying exactly where errors occur. Retains only verified-correct steps and re-derives from the last correct point.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for generation (default: 500) |
| `ctx.max_repair_rounds` | number | optional | Max re-derivation rounds (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per step verification (default: 200) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesized answer from verified reasoning |
| `rounds` | array of shape { error_at?: number, round: number, steps: array of shape { correct: boolean, explanation: string, step: string }, verified_count: number } | — | Per-round verification trace |
| `total_llm_calls` | number | — | Total LLM calls (generation + verification + synthesis) |
| `total_rounds` | number | — | Number of rounds actually executed (= #rounds) |
| `total_verified` | number | — | Count of verified steps (= #verified_steps) |
| `verified_steps` | array of string | — | Ordered list of verified-correct reasoning steps |
