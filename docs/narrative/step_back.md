---
name: step_back
version: 0.1.0
category: reasoning
result_shape: "shape { abstractions: array of shape { level: number, principle: string, question: string }, answer: string, revised: boolean, verification: string, verified: boolean }"
description: "Step-Back prompting — abstract the principle first, then solve from principles"
source: step_back/init.lua
generated: gen_docs (V0)
---

# Step-Back — abstraction-first reasoning

> Instead of solving directly, first "step back" to identify the underlying principle or concept, then apply that principle to solve the original problem.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.abstraction_levels` | number | optional | Number of abstraction rounds (default: 1) |
| `ctx.domain_hint` | string | optional | Optional domain hint to guide abstraction |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `abstractions` | array of shape { level: number, principle: string, question: string } | — | Ordered step-back Q/A per abstraction level |
| `answer` | string | — | Final answer (post-verification / post-revision) |
| `revised` | boolean | — | Whether a revision pass was triggered |
| `verification` | string | — | Verifier output |
| `verified` | boolean | — | Whether verification returned VERIFIED |
