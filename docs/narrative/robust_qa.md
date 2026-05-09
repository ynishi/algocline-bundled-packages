---
name: robust_qa
version: 0.1.0
category: pipeline
result_shape: "shape { adversarial_survived: boolean, answer: string, constraints_passed: boolean, critic_avg_score: number, critic_scores: table, phase1_answer: string, phase2_answer: string, phase3_answer: string, phases: array of any }"
description: "Three-phase QA pipeline: constraint-first, adversarial test, rubric evaluation."
source: robust_qa/init.lua
generated: gen_docs (V0)
---

# robust_qa(RobustQA) — three-phase quality-assurance pipeline

> Chains three independent verification strategies into a single pipeline. Each phase operates on a different axis of quality and on the (potentially revised) output of the previous phase, so later phases evaluate a progressively hardened answer.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local robust_qa = require("robust_qa")
return robust_qa.run(ctx)
```

## Algorithm {#algorithm}

1. `p_tts` — constraint-first solving. Generate constraints before
   solving and verify the solution against the specification ("does
   it satisfy the requirements?").
2. `negation` — adversarial stress test. Generate destruction
   conditions, check whether they hold, revise on flaws ("can it be
   broken?").
3. `critic` — rubric-based evaluation. Score per dimension and
   revise weak areas with targeted feedback ("is it well-crafted?").

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Shared generation token budget (default: 600) |
| `ctx.max_conditions` | number | optional | Phase 2 (negation): max destruction conditions (default: 4) |
| `ctx.max_constraints` | number | optional | Phase 1 (p_tts): max constraints (default: 5) |
| `ctx.max_repairs` | number | optional | Phase 1 (p_tts): max repair attempts (default: 1) |
| `ctx.max_revisions` | number | optional | Phase 3 (critic): max revision rounds (default: 1) |
| `ctx.plan_tokens` | number | optional | Phase 1 (p_tts): planning token budget (default: 400) |
| `ctx.rubric` | any | optional | Phase 3 (critic): rubric dimension list (passed through) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.threshold` | number | optional | Phase 3 (critic): min acceptable per-dimension score (default: 7) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `adversarial_survived` | boolean | — | Phase 2 survived flag (convenience) |
| `answer` | string | — | Final answer after all 3 phases |
| `constraints_passed` | boolean | — | Phase 1 all_passed flag (convenience) |
| `critic_avg_score` | number | — | Phase 3 avg score (convenience) |
| `critic_scores` | table | — | Phase 3 per-dimension score map |
| `phase1_answer` | string | — | Answer at end of Phase 1 (p_tts) |
| `phase2_answer` | string | — | Answer at end of Phase 2 (negation) |
| `phase3_answer` | string | — | Answer at end of Phase 3 (critic) — matches `answer` |
| `phases` | array of any | — | Sequential phase records (phase1 p_tts / phase2 negation / phase3 critic) — each carries per-phase fields keyed by name |
