---
name: least_to_most
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, subproblems: array of shape { solution: string, subproblem: string }, total_subproblems: number }"
description: "Decompose into ordered subproblems and solve simplest first, building up."
source: least_to_most/init.lua
generated: gen_docs (V0)
---

# least_to_most(LeastToMost) — progressive subproblem decomposition

> Decomposes a complex problem into subproblems ordered from simplest to most complex, then solves each in sequence using previous solutions as context for the next.

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local ltm = require("least_to_most")
return ltm.run(ctx)
```

## References {#references}

- Zhou, D. et al. (2022). "Least-to-Most Prompting Enables Complex
  Reasoning in Large Language Models". https://arxiv.org/abs/2205.10625

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
