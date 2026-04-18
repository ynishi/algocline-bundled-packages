---
name: p_tts
version: 0.1.0
category: planning
result_shape: "shape { all_passed: boolean, answer: string, constraints: array of string, fail_count: number, history: array of shape { answer: string, attempt: number, fail_count: number, pass_count: number, results: array of shape { constraint: string, reason: string, verdict: one_of(\"pass\", \"fail\") } }, pass_count: number, plan: string, repairs: number, total_constraints: number }"
description: "Plan-Test-Then-Solve — generate constraints before solving, verify solution against specification"
source: p_tts/init.lua
generated: gen_docs (V0)
---

# p_tts — Plan-Test-Then-Solve (constraint-first reasoning)

> Before solving, generates expected properties and test cases the answer must satisfy. Then solves while checking against those constraints. Finally verifies the solution against all generated test cases.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for solving (default: 600) |
| `ctx.max_constraints` | number | optional | Max constraints to generate (default: 6) |
| `ctx.max_repairs` | number | optional | Max repair attempts (default: 2) |
| `ctx.plan_tokens` | number | optional | Max tokens for planning (default: 400) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per constraint check (default: 150) |
