---
name: blind_spot
version: 0.1.0
category: correction
result_shape: "shape { answer: string, corrections_detected: number, history: array of shape { role: string, round: number, text: string }, initial_answer: string, rounds: number, wait_applied: boolean }"
description: "Bypass self-correction blind spot by re-presenting output as external source."
source: blind_spot/init.lua
generated: gen_docs (V0)
---

# blind_spot(BlindSpot) — bypass the self-correction blind spot via externalization

> LLMs cannot correct errors in their own outputs but successfully correct identical errors when presented as coming from external sources. This package exploits the asymmetry by generating an answer and re-presenting it as a "colleague's draft" for the same LLM to review and correct.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local blind_spot = require("blind_spot")
return blind_spot.run(ctx)
```

## Algorithm {#algorithm}

1. Generate an initial answer normally.
2. Re-present the answer as if it came from an external source.
3. Ask the model to find and fix errors in the "external" answer.
4. Optionally append a "Wait" reflection trigger for a final check.

## Theoretical foundations {#theoretical-foundations}

The "Wait" trigger activates dormant correction capabilities; the source
paper reports an 89.3% blind-spot reduction across 14 open-source models.

## References {#references}

- "Self-Correction Bench: Uncovering and Addressing the Self-Correction
  Blind Spot in Large Language Models". arXiv:2507.02778, 2025.
  https://arxiv.org/abs/2507.02778

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.correct_tokens` | number | optional | Max tokens per correction / reflection (default: 800) |
| `ctx.gen_tokens` | number | optional | Max tokens for initial generation (default: 600) |
| `ctx.rounds` | number | optional | Externalize→correct rounds (default: 1) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.wait` | boolean | optional | Enable 'Wait' reflection trigger (default: true) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer after externalize→correct (+ Wait) |
| `corrections_detected` | number | — | Count of rounds whose output matched error/correction keywords |
| `history` | array of shape { role: string, round: number, text: string } | — | Per-round trace including initial draft, corrections, and optional wait reflection |
| `initial_answer` | string | — | Initial answer before any correction rounds |
| `rounds` | number | — | Number of externalize→correct rounds executed |
| `wait_applied` | boolean | — | Whether 'Wait' reflection round ran |
