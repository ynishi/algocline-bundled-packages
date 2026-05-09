---
name: plan_solve
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, execution: string, plan: string, plan_steps: number }"
description: "Plan-and-Solve — devise an explicit plan, then execute step by step"
source: plan_solve/init.lua
generated: gen_docs (V0)
---

# plan_solve(PlanSolve) — Plan-and-Solve prompting

> Devises an explicit step-by-step plan before execution, then carries out each step sequentially. More structured than Chain-of-Thought, lighter than full `decompose` (no parallel subtask dispatch).

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local plan_solve = require("plan_solve")
return plan_solve.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 2-3 LLM calls:

1. Plan — devise a numbered plan of reasoning steps.
2. Execute — carry out the plan step by step.
3. Extract (optional) — produce a concise final answer.

## References {#references}

- Wang, L. et al. (2023). "Plan-and-Solve Prompting: Improving
  Zero-Shot Chain-of-Thought Reasoning by Large Language Models".
  https://arxiv.org/abs/2305.04091

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.extract` | boolean | optional | Extract concise final answer (default: true) |
| `ctx.plan_tokens` | number | optional | Max tokens for plan generation (default: 300) |
| `ctx.solve_tokens` | number | optional | Max tokens for execution (default: 500) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer (extracted or raw execution) |
| `execution` | string | — | Full step-by-step execution trace |
| `plan` | string | — | Numbered plan devised in Step 1 |
| `plan_steps` | number | — | Count of numbered steps parsed from plan |
