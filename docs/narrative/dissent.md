---
name: dissent
version: 0.1.0
category: governance
result_shape: "shape { consensus_held: boolean, dissent: string, evaluation: string, key_issues: string, merit_score: number, output: string, revised_consensus?: string }"
description: "Consensus inertia prevention — forces adversarial challenge before finalizing multi-agent agreement. Prevents groupthink lock-in. Generalizes the Consensus Inertia countermeasure from 'From Spark to Fire' (Xie et al., AAMAS 2026). Composable with moa, panel, sc."
source: dissent/init.lua
generated: gen_docs (V0)
---

# dissent — Consensus inertia prevention via forced adversarial challenge

> Before finalizing any multi-agent consensus, injects a dedicated adversarial agent that challenges the emerging agreement. Evaluates the dissent's validity and produces a revised consensus only when the challenge has merit. Prevents premature lock-in of incorrect conclusions.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.consensus` | string | **required** | The consensus text to challenge (REQUIRED) |
| `ctx.gen_tokens` | number | optional | Max tokens per generation (default: 500) |
| `ctx.merit_threshold` | number | optional | Score threshold for revision (default: 0.6) |
| `ctx.perspectives` | array of any | optional | Individual agent outputs that formed consensus; elements are either strings or {name?, output? \| text?} tables |
| `ctx.task` | string | **required** | Original task description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `consensus_held` | boolean | — | True iff the original consensus was NOT revised |
| `dissent` | string | — | Raw adversarial challenge produced in Phase 1 |
| `evaluation` | string | — | Raw judge output from Phase 2 |
| `key_issues` | string | — | Parsed key issues block from judge output (empty string when absent) |
| `merit_score` | number | — | Parsed merit score in [0, 1]; 0 on parse failure |
| `output` | string | — | Final output — original consensus when held, revised otherwise |
| `revised_consensus` | string | optional | Revised consensus text; nil iff no revision was triggered |
