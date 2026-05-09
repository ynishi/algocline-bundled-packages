---
name: critic
version: 0.1.0
category: evaluation
result_shape: "shape { answer: string, avg_score: number, history: array of shape { answer: string, avg_score: number, round: number, scores: array of shape { dimension: string, feedback: string, raw: string, score: number }, weak_count: number }, initial_answer: string, revisions: number, rubric: array of shape { description: string, name: string }, scores: table, threshold: number }"
description: "Rubric-based per-dimension scoring with targeted revision of weak areas."
source: critic/init.lua
generated: gen_docs (V0)
---

# critic(Critic) — rubric-based structured evaluation and targeted revision

> Unlike `reflect` (freeform self-critique), `critic` evaluates on pre-defined rubric dimensions (accuracy, logic, completeness, ...), assigns per-dimension scores, generates targeted feedback, and revises only the weakest areas, producing a structured quality profile.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local critic = require("critic")
return critic.run(ctx)
```

## Algorithm {#algorithm}

1. Generate an initial answer (or use `ctx.answer`).
2. Evaluate each rubric dimension independently with a numeric score.
3. Revise dimensions whose score is below `threshold`.
4. Optionally re-score to verify improvement, up to `max_revisions`.

## References {#references}

- Zheng, L. et al. (2023). "Judging LLM-as-a-Judge with MT-Bench and
  Chatbot Arena". https://arxiv.org/abs/2306.05685
- Rubric-based evaluation methodology from education research.

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
