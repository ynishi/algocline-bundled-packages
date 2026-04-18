---
name: critic
version: 0.1.0
category: evaluation
result_shape: "shape { answer: string, avg_score: number, history: array of shape { answer: string, avg_score: number, round: number, scores: array of shape { dimension: string, feedback: string, raw: string, score: number }, weak_count: number }, initial_answer: string, revisions: number, rubric: array of shape { description: string, name: string }, scores: table, threshold: number }"
description: "Rubric-based structured evaluation — per-dimension scoring with targeted revision of weak areas"
source: critic/init.lua
generated: gen_docs (V0)
---

# critic — Rubric-based structured evaluation and targeted revision

> Unlike reflect (freeform self-critique), critic evaluates on predefined rubric dimensions (accuracy, logic, completeness, etc.), assigns per- dimension scores, generates targeted feedback, and revises only the weakest areas. Produces a structured quality profile.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.answer` | string | optional | Pre-supplied answer to evaluate (default: nil → auto-generate) |
| `ctx.eval_tokens` | number | optional | Max tokens per dimension evaluation (default: 200) |
| `ctx.gen_tokens` | number | optional | Max tokens for initial generation (default: 600) |
| `ctx.max_revisions` | number | optional | Max revision rounds (default: 2) |
| `ctx.revise_tokens` | number | optional | Max tokens for revision (default: 600) |
| `ctx.rubric` | any | optional | List of dimensions — either string names or {name, description} tables |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.threshold` | number | optional | Minimum acceptable per-dimension score (default: 7) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final (possibly revised) answer |
| `avg_score` | number | — | Average of final per-dimension scores |
| `history` | array of shape { answer: string, avg_score: number, round: number, scores: array of shape { dimension: string, feedback: string, raw: string, score: number }, weak_count: number } | — | Per-round evaluation trace |
| `initial_answer` | string | — | Initial answer before any revisions |
| `revisions` | number | — | Number of revision rounds actually performed |
| `rubric` | array of shape { description: string, name: string } | — | Normalized rubric used for evaluation |
| `scores` | table | — | Final per-dimension score map (dim_name → number) |
| `threshold` | number | — | Threshold value used (echoed from input) |
