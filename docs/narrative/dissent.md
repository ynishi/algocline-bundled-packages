---
name: dissent
version: 0.1.0
category: governance
result_shape: "shape { consensus_held: boolean, dissent: string, evaluation: string, key_issues: string, merit_score: number, output: string, revised_consensus?: string }"
description: "Forced adversarial challenge to prevent multi-agent consensus inertia."
source: dissent/init.lua
generated: gen_docs (V0)
---

# dissent(Dissent) — consensus inertia prevention via forced adversarial challenge

> Before finalizing any multi-agent consensus, injects a dedicated adversarial agent that challenges the emerging agreement, evaluates the dissent's validity, and produces a revised consensus only when the challenge has merit. Composable: wrap around `moa`, `panel`, `sc`, or any strategy that produces a consensus output.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local dissent = require("dissent")
return dissent.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 3-4 LLM calls:

1. Adversarial challenge — a dedicated dissenter attacks the
   consensus.
2. Merit evaluation — an independent judge scores the dissent.
3. Conditional revision — when the score exceeds `merit_threshold`,
   revise the consensus.
4. Final synthesis — produce the final output with dissent metadata.

## Theoretical foundations {#theoretical-foundations}

Generalizes the "Consensus Inertia" countermeasure from Xie et al.
The paper finds that once a multi-agent group converges on an
incorrect answer, baseline systems fail to recover (defense rate
0.32). Forced adversarial challenge at the consensus boundary is one
of the key architectural interventions that raises defense to 0.89.
Also related to MAST failure mode F11: "groupthink convergence" where
agents reinforce each other's errors.

## References {#references}

- Xie, ... et al. (2026). "From Spark to Fire: Diagnosing and
  Overcoming the Fragility of Multi-Agent Systems". AAMAS 2026.
- Cemri, ... et al. (2025). MAST failure-mode taxonomy (F11).

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
