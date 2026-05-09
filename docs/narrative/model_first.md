---
name: model_first
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, model: string, solution: string, verified: boolean, violations: array of string, violations_found: number }"
description: "Construct explicit problem model (entities/states/constraints) before solving."
source: model_first/init.lua
generated: gen_docs (V0)
---

# model_first(ModelFirst) — model-first reasoning via explicit problem modeling

> Separates problem representation from problem solving. First constructs an explicit problem model (entities, state variables, actions with preconditions/effects, and constraints), then reasons within that model. Unlike `plan_solve` (which generates "what to do"), `model_first` generates "what exists" before any solving, catching constraint violations that an implicit-constraint plan misses.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local mf = require("model_first")
return mf.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 2-4 LLM calls:

1. Model — construct an explicit problem model (entities, states,
   actions, constraints). Do not solve yet.
2. Solve — reason within the model, tracking state transitions.
3. Verify (optional) — check the solution against all model
   constraints.
4. Extract (optional) — produce a concise final answer.

## References {#references}

- Rana, ..., Kumar, ... (2025). "Model-First Reasoning LLM Agents:
  Reducing Hallucinations through Explicit Problem Modeling".
  https://arxiv.org/abs/2512.14474

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
