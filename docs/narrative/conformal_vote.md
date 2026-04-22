---
name: conformal_vote
version: 0.1.0
category: validation
result_shape: conformal_decided
description: "Linear opinion pool + split conformal prediction gate for multi-agent deliberation. Emits a three-way decision (commit / escalate / anomaly) per Proposition 3, with a finite-sample coverage guarantee Pr[Y ∈ C(X)] ≥ 1-α (Theorem 2). Calibration and online rounds share aggregation weights so exchangeability is preserved."
source: conformal_vote/init.lua
generated: gen_docs (V0)
---

# conformal_vote — Linear opinion pool + split conformal prediction

> gate for safe multi-agent deliberation.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agents` | any | **required** | Array of agent specs (prompt string or {prompt,system?,model?,temperature?,max_tokens?} table) |
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default: false) |
| `ctx.calibration` | shape { alpha: number, n: number, q_hat: number, tau: number, weights: table } | **required** |  |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default: 'conformal_vote_<task_hash>') |
| `ctx.gen_tokens` | number | optional | Max tokens for LLM generation (default: 400) |
| `ctx.options` | array of string | **required** | Candidate label set |
| `ctx.scenario_name` | string | optional | Explicit scenario name for the emitted Card |
| `ctx.task` | string | **required** | Task text presented to each agent |

## Result {#result}

Returns `conformal_decided` shape:

| key | type | optional | description |
|---|---|---|---|
| `action` | one_of("commit", "escalate", "anomaly") | — | Three-way decision per Proposition 3 |
| `card_id` | string | optional | Emitted Card id (only when auto_card=true) |
| `coverage_level` | number | — | 1 - alpha (finite-sample guarantee) |
| `p_social` | map of string to number | — | Linear opinion pool output { [label] = prob } |
| `prediction_set` | array of string | — | Labels y with P_social(y\|x) >= tau |
| `q_hat` | number | — | Calibration quantile of nonconformity scores |
| `selected` | string | optional | Committed label (nil when action != 'commit') |
| `tau` | number | — | 1 - q_hat (prediction-set threshold) |
