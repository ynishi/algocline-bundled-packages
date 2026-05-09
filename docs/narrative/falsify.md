---
name: falsify
version: 0.1.0
category: exploration
result_shape: "shape { all_hypotheses: array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string }, answer: string, stats: shape { initial_count: number, rounds: number, total_derived: number, total_generated: number, total_refuted: number, total_survived: number }, survivors: array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string } }"
description: "Popper-style sequential falsification of hypotheses with successor derivation."
source: falsify/init.lua
generated: gen_docs (V0)
---

# falsify(Falsify) — sequential falsification for hypothesis exploration

> Explores hypothesis space via Popper's falsificationism: generate hypotheses, attempt to refute each one, prune the refuted, and derive new hypotheses from the refutation insights. Unlike `verify_first` (checks consistency) or `cove` (verification chain), `falsify` actively attacks hypotheses and uses refutation failures as evidence of robustness while refutation successes drive successor generation.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local falsify = require("falsify")
return falsify.run(ctx)
```

## Algorithm {#algorithm}

1. Seed — generate initial hypotheses.
2. For each of `max_rounds` rounds:
   - Falsify — attempt to refute each active hypothesis (1 LLM call).
   - Judge — was the refutation successful? (1 LLM call).
   - Prune — remove refuted hypotheses.
   - Derive — generate successor hypotheses from refutation insights.
3. Synthesize the surviving hypotheses into a final answer.

## References {#references}

- Sourati, J. et al. (2025). "Automated Hypothesis Validation with
  Agentic Sequential Falsifications". https://arxiv.org/abs/2502.09858
- Yamada, Y. et al. (2025). "AI Scientist v2: Agentic Tree Search for
  Scientific Discovery". https://arxiv.org/abs/2504.08066
- Popper, K. (1959). "The Logic of Scientific Discovery".

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.derive_on_refute` | boolean | optional | Generate successor hypotheses from refuted ones (default: true) |
| `ctx.initial_hypotheses` | number | optional | Seed hypothesis count (default: 4) |
| `ctx.max_hypotheses` | number | optional | Upper bound on active hypotheses (default: 12) |
| `ctx.max_rounds` | number | optional | Maximum falsification rounds (default: 3) |
| `ctx.task` | string | **required** | The problem or question to investigate |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `all_hypotheses` | array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string } | — | All hypotheses (initial + derived), survivors and refuted alike |
| `answer` | string | — | Synthesized final answer from surviving hypotheses (or post-all-refuted fallback) |
| `stats` | shape { initial_count: number, rounds: number, total_derived: number, total_generated: number, total_refuted: number, total_survived: number } | — | Aggregate falsification statistics |
| `survivors` | array of shape { confidence: number, derived_from?: number, history: array of shape { refutation: string, round: number, verdict: string }, id: number, refutation_attempts: number, status: string, text: string } | — | Hypotheses that survived all refutation rounds |
