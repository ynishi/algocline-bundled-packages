---
name: p_tts
version: 0.1.0
category: planning
result_shape: "shape { all_passed: boolean, answer: string, constraints: array of string, fail_count: number, history: array of shape { answer: string, attempt: number, fail_count: number, pass_count: number, results: array of shape { constraint: string, reason: string, verdict: one_of(\"pass\", \"fail\") } }, pass_count: number, plan: string, repairs: number, total_constraints: number }"
description: "Plan-Test-Then-Solve — generate constraints before solving, verify solution against specification"
source: p_tts/init.lua
generated: gen_docs (V0)
---

# p_tts(PTTS) — Plan-Test-Then-Solve constraint-first reasoning

> Before solving, generates expected properties and test cases the answer must satisfy, solves while staying aware of those constraints, and verifies the solution against the test cases. Unlike `decompose` (splits into subtasks) or `reflect` (post-hoc critique), `p_tts` generates verifiable constraints before solving for a specification-driven approach.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local p_tts = require("p_tts")
return p_tts.run(ctx)
```

## Algorithm {#algorithm}

1. Plan — analyze the task and identify key requirements.
2. Test — generate verifiable properties and constraints.
3. Solve — produce a solution while aware of the constraints.
4. Verify — check the solution against each constraint.
5. Repair — fix any violations, up to `max_repairs`.

## References {#references}

- Zhang, S. et al. (2023). "Planning with Large Language Models for
  Code Generation". https://arxiv.org/abs/2303.05510
- Test-driven development methodology applied to reasoning.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for solving (default: 600) |
| `ctx.max_constraints` | number | optional | Max constraints to generate (default: 6) |
| `ctx.max_repairs` | number | optional | Max repair attempts (default: 2) |
| `ctx.plan_tokens` | number | optional | Max tokens for planning (default: 400) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per constraint check (default: 150) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `all_passed` | boolean | — | Whether all constraints passed |
| `answer` | string | — | Final answer after verify+repair |
| `constraints` | array of string | — | Verifiable constraints the answer must satisfy |
| `fail_count` | number | — | Number of constraints failing in the final round |
| `history` | array of shape { answer: string, attempt: number, fail_count: number, pass_count: number, results: array of shape { constraint: string, reason: string, verdict: one_of("pass", "fail") } } | — | Per-round repair history |
| `pass_count` | number | — | Number of constraints passing in the final round |
| `plan` | string | — | Planning phase LLM output |
| `repairs` | number | — | Number of repair rounds performed |
| `total_constraints` | number | — | Total number of constraints generated |
