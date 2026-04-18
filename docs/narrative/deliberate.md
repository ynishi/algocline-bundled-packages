---
name: deliberate
version: 0.1.0
category: combinator
result_shape: "shape { abstractions: any, confidence: number, confidence_escalated: boolean, debates: array of any, expert_analysis: string, expert_consultations: any, options: array of any, principles: string, ranking_matches: array of shape { a: number, b: number, reason: string, winner: number }, recommendation: shape { debate_outcome: string, description?: string, name?: string, ranking_wins: number }, total_options: number }"
description: "Structured deliberation — abstract principles, expert consultation, debate, ranked decision"
source: deliberate/init.lua
generated: gen_docs (V0)
---

# deliberate — structured multi-phase deliberation for complex decisions

> Combinator package: orchestrates step_back, meta_prompt, triad, calibrate, rank to perform principled decision-making.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.confidence_threshold` | number | optional | Calibrate threshold (default: 0.7) |
| `ctx.debate_rounds` | number | optional | Triad debate rounds per option (default: 2) |
| `ctx.max_options` | number | optional | Max options to consider (default: 4) |
| `ctx.options` | array of any | optional | Pre-defined options (auto-generated if absent); each opaque {name?, description?, strengths?, risks?} |
| `ctx.task` | string | **required** | The decision question |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `abstractions` | any | — | step_back's abstractions sub-result (opaque; shape owned by step_back) |
| `confidence` | number | — | Calibrate confidence score |
| `confidence_escalated` | boolean | — | Whether the confidence gate escalated |
| `debates` | array of any | — | Per-option triad result {option, verdict, winner}; option is opaque (user-shaped) |
| `expert_analysis` | string | — | meta_prompt's aggregated analysis answer |
| `expert_consultations` | any | — | meta_prompt's experts_consulted sub-result (opaque; shape owned by meta_prompt) |
| `options` | array of any | — | Options actually considered (as supplied or auto-generated) |
| `principles` | string | — | Extracted principles and criteria (from step_back) |
| `ranking_matches` | array of shape { a: number, b: number, reason: string, winner: number } | — | Pairwise-tournament match log |
| `recommendation` | shape { debate_outcome: string, description?: string, name?: string, ranking_wins: number } | — | Final recommendation built from the tournament winner |
| `total_options` | number | — | Number of options considered |
