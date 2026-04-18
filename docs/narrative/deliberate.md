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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.confidence_threshold` | number | optional | Calibrate threshold (default: 0.7) |
| `ctx.debate_rounds` | number | optional | Triad debate rounds per option (default: 2) |
| `ctx.max_options` | number | optional | Max options to consider (default: 4) |
| `ctx.options` | array of any | optional | Pre-defined options (auto-generated if absent); each opaque {name?, description?, strengths?, risks?} |
| `ctx.task` | string | **required** | The decision question |
