---
name: refine_loop
version: 0.1.0
category: refinement
result_shape: "shape { accepted: boolean, final: string, history: shape { draft: string, iterations: array of shape { accepted: boolean, index: number, reflection: string, revision?: string } }, iterations_used: number }"
description: "Reflective draft-reflect-revise loop with rubric and external-feedback hooks"
source: refine_loop/init.lua
generated: gen_docs (V0)
---

# refine_loop(RefineLoop) — reflective refinement loop for 26-generation models

> A boost strategy that iterates draft -> reflection -> revise until the reflection stage signals acceptance or an iteration cap is reached. It is a single-strategy distillation of GEPA-style reflective refinement: linguistic self-reflection carries denser learning signal than a sparse scalar reward, which makes each round more sample-efficient than reward-only tuning.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [API](#api)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local refine_loop = require("refine_loop")
return refine_loop.run({ task = "Explain CAP theorem tradeoffs." })
```

## Algorithm {#algorithm}

1. **Draft** — one `alc.llm` pass produces the initial answer.
2. **Reflection** — one `alc.llm` pass critiques the current draft against
   the rubric (and, on the first round only, any external eval feedback). If
   the draft fully satisfies the rubric the reflection returns the literal
   ASCII marker `ACCEPT`, which triggers early-stop (no revise that round).
3. **Revise** — when the reflection did not accept, one `alc.llm` pass
   rewrites the draft addressing the critique. Steps 2-3 repeat up to
   `max_iterations` times.

## API {#api}

- `ctx.task`           — string, required. Empty / whitespace-only → error.
- `ctx.max_iterations` — number, optional. Max reflection→revise cycles
  (default 2).
- `ctx.rubric`         — string, optional. Critique criteria injected verbatim
  into every reflection prompt. Omitted → a generic quality rubric.
- `ctx.feedback`       — string, optional. External eval feedback injected
  into the FIRST reflection prompt only (eval-driven refinement v0 hook).

Result (`ctx.result`):
- `final`           — string, the final (possibly revised) answer.
- `iterations_used` — number, how many reflection rounds ran.
- `accepted`        — boolean, whether a reflection returned `ACCEPT`.
- `history`         — table `{ draft = string, iterations = [ { index,
  reflection, revision?, accepted } ] }` recording every stage.

## Comparison with related packages {#comparison-with-related-packages}

vs `reflect` (SelfRefine, Madaan 2023): `reflect` critiques with a
convergence marker (`NO_MAJOR_ISSUES`) and no external-signal hook. This
package adds a rubric-driven reflection prompt plus a `ctx.feedback` channel
so an external evaluator's verdict can steer the first reflection — the GEPA
direction of feeding textual eval feedback back into refinement.

## References {#references}

- Agrawal et al. (2025). "GEPA: Reflective Prompt Evolution Can Outperform
  Reinforcement Learning." arXiv:2507.19457.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.feedback` | string | optional | External eval feedback injected into the first reflection prompt only (eval-driven refinement hook) |
| `ctx.max_iterations` | number | optional | Maximum reflection->revise cycles (default: 2) |
| `ctx.rubric` | string | optional | Critique criteria injected into every reflection prompt (default: generic quality rubric) |
| `ctx.task` | string | **required** | The task to refine (required, non-empty) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `accepted` | boolean | — | True if a reflection returned the ACCEPT marker |
| `final` | string | — | Final (possibly revised) answer |
| `history` | shape { draft: string, iterations: array of shape { accepted: boolean, index: number, reflection: string, revision?: string } } | — | Full record of draft and each reflection/revision |
| `iterations_used` | number | — | Number of reflection rounds executed |
