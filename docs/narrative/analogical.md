---
name: analogical
version: 0.1.0
category: reasoning
result_shape: "shape { analogies: array of shape { problem: string, solution: string }, answer: string, patterns: string, total_analogies: number }"
description: "Analogical prompting — self-generate analogies, extract patterns, apply to original"
source: analogical/init.lua
generated: gen_docs (V0)
---

# analogical(Analogical) — reasoning by self-generated analogies

> Instead of solving the task directly, generates relevant analogous problems, solves them, extracts transferable patterns, and applies the patterns to the original task.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local analogical = require("analogical")
return analogical.run(ctx)
```

## Algorithm {#algorithm}

1. Generate `n_analogies` distinct analogous problems from the original
   task, optionally biased by `domain_hint`.
2. Solve each analogous problem.
3. Extract transferable reasoning patterns shared across the analogies.
4. Apply the patterns to the original task to produce the final answer.

## References {#references}

- Yasunaga, M. et al. (2023). "Large Language Models as Analogical
  Reasoners". https://arxiv.org/abs/2310.01714

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.domain_hint` | string | optional | Optional domain to draw analogies from |
| `ctx.n_analogies` | number | optional | Number of analogies to generate (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `analogies` | array of shape { problem: string, solution: string } | — | Self-generated analogous problems and their solutions |
| `answer` | string | — | Solution to the original problem produced by applying transferred patterns |
| `patterns` | string | — | Transferable reasoning patterns extracted from the analogies |
| `total_analogies` | number | — | Count of analogies actually generated |
