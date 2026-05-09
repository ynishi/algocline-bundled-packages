---
name: step_verify
version: 0.1.0
category: validation
result_shape: "shape { answer: string, rounds: array of shape { error_at?: number, round: number, steps: array of shape { correct: boolean, explanation: string, step: string }, verified_count: number }, total_llm_calls: number, total_rounds: number, total_verified: number, verified_steps: array of string }"
description: "Step-level reasoning verification — PRM-style LLM-as-Verifier that scores each reasoning step independently. Identifies the first point of failure and re-derives from the last correct step."
source: step_verify/init.lua
generated: gen_docs (V0)
---

# step_verify(StepVerify) — step-level verification (PRM-style LLM-as-Verifier)

> Verifies each intermediate reasoning step independently, identifies exactly where errors occur, retains only verified-correct steps, and re-derives from the last correct point.

## Contents

- [Usage](#usage)
- [Comparison with related packages](#comparison-with-related-packages)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local sv = require("step_verify")
return sv.run(ctx)
```

## Comparison with related packages {#comparison-with-related-packages}

- `cove` — generates verification questions about factual claims,
  answers them independently, then revises. Targets factual
  accuracy of the whole draft.
- `factscore` — decomposes text into atomic factual claims and
  scores each. Targets factual precision.
- `step_verify` — scores each reasoning step for logical
  correctness; identifies the first point of failure and re-derives
  from there.

## Theoretical foundations {#theoretical-foundations}

Grounded in Process Reward Model (PRM) research: PRMs consistently
outperform Outcome Reward Models (ORMs) for mathematical and
multi-step reasoning (Lightman et al. 2023); step-level
supervision localizes errors that outcome-level misses.

## References {#references}

- PRM Survey (2025). https://arxiv.org/abs/2510.08049
- ThinkPRM (2025). https://arxiv.org/abs/2504.16828
- DiVeRSe (Li, ... et al., 2025). https://arxiv.org/abs/2502.09955

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens for generation (default: 500) |
| `ctx.max_repair_rounds` | number | optional | Max re-derivation rounds (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per step verification (default: 200) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesized answer from verified reasoning |
| `rounds` | array of shape { error_at?: number, round: number, steps: array of shape { correct: boolean, explanation: string, step: string }, verified_count: number } | — | Per-round verification trace |
| `total_llm_calls` | number | — | Total LLM calls (generation + verification + synthesis) |
| `total_rounds` | number | — | Number of rounds actually executed (= #rounds) |
| `total_verified` | number | — | Count of verified steps (= #verified_steps) |
| `verified_steps` | array of string | — | Ordered list of verified-correct reasoning steps |
