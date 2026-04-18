---
name: model_first
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, model: string, solution: string, verified: boolean, violations: array of string, violations_found: number }"
description: "Model-First Reasoning — construct explicit problem model (entities, states, actions, constraints) before solving. Reduces constraint violations in planning and scheduling tasks."
source: model_first/init.lua
generated: gen_docs (V0)
---

# model_first — Model-First Reasoning

> Separates problem representation from problem solving. First constructs an explicit problem model (entities, state variables, actions with preconditions/effects, and constraints), then reasons within that model.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.extract` | boolean | optional | Extract concise final answer (default true) |
| `ctx.model_tokens` | number | optional | Max tokens for model construction (default 500) |
| `ctx.solve_tokens` | number | optional | Max tokens for solve/verify/repair steps (default 600) |
| `ctx.task` | string | **required** | Problem to solve (required) |
| `ctx.verify` | boolean | optional | Run constraint-verification + repair step (default true) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer (concise extract when extract=true, otherwise the verified solution) |
| `model` | string | — | Raw problem model text (entities / state vars / actions / constraints) |
| `solution` | string | — | Verified solution text; equals the initial solution when verify=false or no violations |
| `verified` | boolean | — | Whether the verification step actually ran (mirrors input.verify) |
| `violations` | array of string | — | Parsed violation descriptions; empty when verify=false or no violations |
| `violations_found` | number | — | Count of constraint violations parsed from the verification LLM output (0 when verify=false) |
