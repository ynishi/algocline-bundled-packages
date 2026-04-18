---
name: cascade
version: 0.1.0
category: routing
result_shape: "shape { answer: string, confidence: number, escalated: boolean, history: array of shape { answer: string, confidence: number, detail: any, level: number, name: string }, level_used: number, max_level: number, threshold: number }"
description: "Multi-level difficulty routing — escalate from fast to deep only when confidence is low"
source: cascade/init.lua
generated: gen_docs (V0)
---

# cascade — Multi-level difficulty routing with confidence gating

> Routes problems through escalating complexity levels. Starts with the simplest (cheapest) approach; if confidence is below threshold, escalates to a more sophisticated strategy. Minimizes compute for easy problems while ensuring quality for hard ones.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per generation call (default 400) |
| `ctx.max_level` | number | optional | Maximum cascade level to attempt (default 3) |
| `ctx.task` | string | **required** | Problem to solve (required) |
| `ctx.threshold` | number | optional | Confidence threshold at which the cascade stops early (default 0.8) |
| `ctx.verify_tokens` | number | optional | Max tokens per verification call (default 300) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer from the highest level actually run |
| `confidence` | number | — | Final confidence in [0, 1] |
| `escalated` | boolean | — | True iff level_used > 1 |
| `history` | array of shape { answer: string, confidence: number, detail: any, level: number, name: string } | — | Per-level execution trace in run order |
| `level_used` | number | — | Level at which the cascade stopped |
| `max_level` | number | — | Echo of input.max_level |
| `threshold` | number | — | Echo of input.threshold |
