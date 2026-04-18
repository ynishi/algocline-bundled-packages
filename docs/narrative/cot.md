---
name: cot
version: 0.1.0
category: reasoning
result_shape: "shape { chain: array of string, conclusion: string }"
description: "Iterative chain-of-thought — cumulative reasoning steps, then synthesis"
source: cot/init.lua
generated: gen_docs (V0)
---

# CoT — iterative chain-of-thought reasoning

> Builds a reasoning chain step by step, then synthesizes the chain into a single coherent conclusion.

## Contents

- [Usage](#usage)
- [Behavior](#behavior)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local cot = require("cot")
return cot.run({ task = "Why is the sky blue?", depth = 3 })
```

## Behavior {#behavior}

For each step `i` in `1..depth`, the LLM is asked for the next key
insight conditional on all prior insights. After the last step, a
final synthesis prompt collapses the chain into `result.conclusion`.

Each `alc.llm` call is capped at 200 tokens for the chain steps and
500 tokens for the synthesis.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.depth` | number | optional | Number of reasoning steps (default: 3) |
| `ctx.task` | string | **required** | The question or task to reason about |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `chain` | array of string | — | Ordered insights, one per reasoning step |
| `conclusion` | string | — | Synthesized final answer |
