---
name: meta_prompt
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, experts_consulted: array of shape { focus: string, question: string, response: string, role: string }, total_experts: number }"
description: "Meta-Prompting — orchestrator identifies and dispatches to specialist personas"
source: meta_prompt/init.lua
generated: gen_docs (V0)
---

# Meta-Prompting — orchestrator dispatches to specialist personas

> A meta-orchestrator analyzes the task, identifies required expertise, then sequentially delegates to specialist personas, collecting and integrating their outputs.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_experts` | number | optional | Maximum number of expert consultations (default: 4) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Orchestrator's integrated synthesis of all expert analyses |
| `experts_consulted` | array of shape { focus: string, question: string, response: string, role: string } | — | Sequential expert consultations with the question asked and the response received |
| `total_experts` | number | — | Count of experts actually consulted (may be < max_experts due to parsing fallback) |
