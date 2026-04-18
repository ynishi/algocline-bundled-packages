---
name: bisect
version: 0.1.0
category: debugging
result_shape: "shape { answer: string, initial_chain: string, repairs: array of shape { bisect_log: array of shape { correct: boolean, hi: number, lo: number, mid: number, reason: string }, error_content: string, error_label: string, error_step: number, regenerated: string, repair_round: number }, total_repairs: number }"
description: "Binary search for reasoning errors — locate first incorrect step in O(log n), then regenerate from that point"
source: bisect/init.lua
generated: gen_docs (V0)
---

# bisect — Binary search for reasoning errors

> Instead of verifying every step of a reasoning chain (O(n)), bisects the chain to locate the first error in O(log n) steps. Once found, regenerates only the erroneous step and continues.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for chain generation (default: 800) |
| `ctx.max_repairs` | number | optional | Maximum number of bisect→repair cycles (default: 2) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per verification (default: 200) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final reasoning chain after all repairs |
| `initial_chain` | string | — | Original pre-repair reasoning chain |
| `repairs` | array of shape { bisect_log: array of shape { correct: boolean, hi: number, lo: number, mid: number, reason: string }, error_content: string, error_label: string, error_step: number, regenerated: string, repair_round: number } | — | Per-cycle repair records |
| `total_repairs` | number | — | Number of repair cycles applied |
