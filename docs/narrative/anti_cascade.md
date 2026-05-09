---
name: anti_cascade
version: 0.1.0
category: governance
result_shape: "shape { flagged_steps: array of string, max_drift: number, step_results: array of shape { cascade_risk: string, drift_score: number, drift_type: string, flagged: boolean, name: string, raw: string }, summary: string }"
description: "Pipeline error cascade detection via per-step independent re-derivation."
source: anti_cascade/init.lua
generated: gen_docs (V0)
---

# anti_cascade(AntiCascade) — pipeline error cascade amplification detection

> Detects when small errors compound through multi-step pipelines by independently re-deriving conclusions from the original input at each checkpoint and comparing with the pipeline's accumulated output. Steps whose drift exceeds the threshold are flagged.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local anti_cascade = require("anti_cascade")
return anti_cascade.run(ctx)
```

## Algorithm {#algorithm}

For a pipeline of N steps the entry uses ~1 + 2×N LLM calls:

1. For each step, independently re-derive what the step should produce
   from the original task in parallel.
2. Compare the re-derivation against the pipeline's actual output and
   compute a drift score in [0, 1].
3. Summarize flagged steps and overall cascade risk.

## Theoretical foundations {#theoretical-foundations}

Generalizes the "Cascade Amplification" countermeasure from Xie et al.
The paper proved that a single atomic error injection can collapse an
entire multi-agent system, and that independent re-derivation is one
of the key structural defenses. Also addresses MAST failure modes F3
("error propagation through pipeline") and F9 ("accumulated context
drift").

## References {#references}

- Xie, ... et al. (2026). "From Spark to Fire: Diagnosing and
  Overcoming the Fragility of Multi-Agent Systems". AAMAS 2026.
- Cemri, ... et al. (2025). MAST failure mode taxonomy (F3, F9).

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.compare_tokens` | number | optional | Max tokens per pipeline-vs-independent comparison (default 400) |
| `ctx.drift_threshold` | number | optional | Drift score threshold at which a step is flagged (default 0.4) |
| `ctx.rederive_tokens` | number | optional | Max tokens per independent re-derivation (default 500) |
| `ctx.steps` | array of shape { instruction?: string, name: string, output: string } | **required** | Ordered pipeline step outputs; at least 1 entry (required) |
| `ctx.summary_tokens` | number | optional | Max tokens for the final summary analysis (default 500) |
| `ctx.task` | string | **required** | Original task/input that the pipeline was given (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `flagged_steps` | array of string | — | Names of steps whose drift_score crossed the threshold |
| `max_drift` | number | — | Highest drift_score observed across all steps |
| `step_results` | array of shape { cascade_risk: string, drift_score: number, drift_type: string, flagged: boolean, name: string, raw: string } | — | Per-step drift analysis in pipeline order |
| `summary` | string | — | LLM-generated cascade analysis summary text |
