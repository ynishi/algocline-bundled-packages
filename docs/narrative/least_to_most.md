---
name: least_to_most
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, subproblems: array of shape { solution: string, subproblem: string }, total_subproblems: number }"
description: "Least-to-Most — decompose into ordered subproblems, solve simplest first, build up"
source: least_to_most/init.lua
generated: gen_docs (V0)
---

# Least-to-Most — progressive subproblem decomposition

> Decomposes a complex problem into subproblems ordered from simplest to most complex, then solves each in sequence, using previous solutions as context for the next.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_subproblems` | number | optional | Maximum number of subproblems (default: 5) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Synthesized final answer |
| `subproblems` | array of shape { solution: string, subproblem: string } | — | Ordered subproblem/solution pairs (simplest first) |
| `total_subproblems` | number | — | Count of subproblems parsed and solved |
