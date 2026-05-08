---
name: reflect
version: 0.1.0
category: refinement
result_shape: "shape { converged: boolean, output: string, rounds: array of shape { converged: boolean, critique: string, round: number }, total_rounds: number }"
description: "Self-critique loop — generate, critique, revise until convergence"
source: reflect/init.lua
generated: gen_docs (V0)
---

# reflect(SelfRefine) — self-critique and iterative refinement

> Generate → Critique → Revise loop. The same LLM critiques its own output and refines until convergence or max rounds.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local reflect = require("reflect")
return reflect.run({ task = "Explain the halting problem." })
```

## Algorithm {#algorithm}

1. **Generate** — produce an initial draft for the task (skipped if
   `initial_draft` is provided).
2. **Critique** — the LLM evaluates its own draft and emits structured
   feedback. Outputs `NO_MAJOR_ISSUES` / `NO_ISSUES` as a convergence
   signal.
3. **Revise** — the LLM rewrites the draft addressing every critique
   point. Steps 2–3 repeat up to `max_rounds` times or until the stop
   condition is met.

## Theoretical foundations {#theoretical-foundations}

Based on Madaan et al. (2023): an LLM can reliably critique and improve
its own output without external feedback or reward models, provided the
critique and revision are performed in separate inference calls so the
model attends to the full prior draft without interference.

## References {#references}

- Madaan, A., Tandon, N., Gupta, P., Hallinan, S., Gao, L., Wiegreffe, S.,
  Alon, U., Dziri, N., Prabhumoye, S., Yang, Y., Gupta, S., Majumder, B. P.,
  Hermann, K., Welleck, S., Yazdanbakhsh, A., Clark, P. (2023).
  "Self-Refine: Iterative Refinement with Self-Feedback."
  arXiv:2303.17651.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.critique_tokens` | number | optional | Max tokens for critique (default: 300) |
| `ctx.gen_tokens` | number | optional | Max tokens for generation (default: 500) |
| `ctx.initial_draft` | string | optional | Pre-generated draft to refine (skips initial LLM generation) |
| `ctx.max_rounds` | number | optional | Maximum critique-revise cycles (default: 3) |
| `ctx.stop_when` | string | optional | Stop condition: 'no_major_issues' or 'no_issues' (default: 'no_major_issues') |
| `ctx.task` | string | **required** | The task to perform |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `converged` | boolean | — | Whether the last round converged |
| `output` | string | — | Final refined draft |
| `rounds` | array of shape { converged: boolean, critique: string, round: number } | — | Ordered critique rounds with convergence flag |
| `total_rounds` | number | — | Number of critique rounds executed |
