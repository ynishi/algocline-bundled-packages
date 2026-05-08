---
name: step_back
version: 0.1.0
category: reasoning
result_shape: "shape { abstractions: array of shape { level: number, principle: string, question: string }, answer: string, revised: boolean, verification: string, verified: boolean }"
description: "Step-Back prompting — abstract the principle first, then solve from principles"
source: step_back/init.lua
generated: gen_docs (V0)
---

# step_back(StepBack) — abstraction-first reasoning

> Instead of solving directly, first "step back" to identify the underlying principle or concept, then apply that principle to solve the original problem. Implements the Step-Back Prompting method (Zheng et al. 2023), extended with a verification pass and optional revision round.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local step_back = require("step_back")
return step_back.run({ task = "Why does ice float on water?" })
```

## Algorithm {#algorithm}

Given a problem `task`, the pkg performs five phases:

1. **Step-back question generation** — for each abstraction level, produce
   a higher-level question about the underlying principle (via `alc.llm`).
2. **Principle answering** — answer each step-back question to extract
   the domain principle.
3. **Principle-grounded solving** — solve `task` using the extracted
   principles as context.
4. **Verification** — check that the solution correctly applies the
   principles; output `VERIFIED` if consistent.
5. **Revision** (conditional) — if verification finds gaps, revise once.

## Theoretical foundations {#theoretical-foundations}

Step-Back Prompting (Zheng et al. 2023) shows that eliciting abstract
principles before answering specific questions improves factual accuracy
and reduces hallucination across multiple reasoning benchmarks. The
abstraction step forces the model to retrieve broader, more reliable
knowledge before grounding it to the specific query.

## References {#references}

- Zheng, H., Cai, S., Huang, L., Liu, Y., Han, X., Liu, Z. (2023).
  "Take a Step Back: Evoking Reasoning via Abstraction in Large Language
  Models". arXiv:2310.06117.
  https://arxiv.org/abs/2310.06117

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.abstraction_levels` | number | optional | Number of abstraction rounds (default: 1) |
| `ctx.domain_hint` | string | optional | Optional domain hint to guide abstraction |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `abstractions` | array of shape { level: number, principle: string, question: string } | — | Ordered step-back Q/A per abstraction level |
| `answer` | string | — | Final answer (post-verification / post-revision) |
| `revised` | boolean | — | Whether a revision pass was triggered |
| `verification` | string | — | Verifier output |
| `verified` | boolean | — | Whether verification returned VERIFIED |
