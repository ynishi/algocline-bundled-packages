---
name: review_and_investigate
version: 0.1.0
category: combinator
result_shape: "shape { summary: shape { by_category?: map of string to number, context_filtered?: boolean, deep_analyzed?: number, false_positives_removed?: number, policy_applied?: string, total_themes: number }, themes: array of shape { best_practice?: string, category?: string, current_state?: string, deep_analysis?: shape { verdict?: string, winner?: string }, diagnosis_confidence?: number, diagnosis_escalated?: boolean, expert_consultations?: array of shape { focus: string, question: string, response: string, role: string }, fix_anti_patterns?: array of shape { error_analysis: string, wrong_reasoning: string }, fixes?: array of shape { approach?: string, avoids?: string, id?: string, impact?: string, risk?: string, summary?: string }, gap?: string, id?: string, locations?: array of string, name: string, principle_violated?: string, ranking?: shape { best: shape { approach?: string, avoids?: string, id?: string, impact?: string, risk?: string, summary?: string }, matches: array of shape { a: string, b: string, reason: string, winner: string } }, references?: array of string, related_locations?: array of string, root_cause?: string, search_pattern?: string, span?: array of number, surface_symptom?: string, total_occurrences?: number, verification?: string } }"
description: "Deep code review with investigation — detect, verify, explore, diagnose, research, prescribe"
source: review_and_investigate/init.lua
generated: gen_docs (V0)
---

# review_and_investigate — deep code review with fact-checking and root-cause analysis

> Combinator package: orchestrates reflect, calibrate, factscore, triad, panel, rank to perform multi-phase investigative code review.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.code` | string | **required** | Source code or diff to review (required) |
| `ctx.context` | string | optional | Free-text design context used in Phase 1/1.5/2/4 |
| `ctx.deep_threshold` | number | optional | Confidence threshold below which the diagnose phase escalates to triad (default 0.6) |
| `ctx.max_fixes` | number | optional | Max fix candidates per theme (default 3) |
| `ctx.policy` | shape { priorities?: array of string, severity_weights?: map of string to number } | optional | Review policy (default: correctness > non_breaking > safety > testability > maintainability) |
