---
name: lineage
version: 0.1.0
category: governance
result_shape: "shape { analysis: string, integrity_score?: number, lineage_graph: string, step_claims: array of shape { claims: array of shape { id: number, text: string }, name: string, raw: string }, traces: array of shape { from_step: string, raw: string, to_step: string, traces: array of shape { derives_from?: array of any, id: number, transformation?: string } } }"
description: "Pipeline-spanning claim lineage tracking with conflict and ungrounded detection."
source: lineage/init.lua
generated: gen_docs (V0)
---

# lineage(Lineage) — pipeline-spanning claim lineage tracking

> Tracks the provenance of claims across multi-step pipelines: extracts atomic claims from each step's output, traces inter-step dependencies (which claim in step `N` derived from which claim in step `N-1`), and detects conflicts and ungrounded claims in the final output.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local lineage = require("lineage")
return lineage.run(ctx)
```

## Algorithm {#algorithm}

For `N` pipeline steps the entry uses ~2N LLM calls:

1. Extract atomic claims from each step output (`N` calls, parallel).
2. Trace inter-step dependencies (`N-1` calls, parallel per pair).
3. Detect conflicts and ungrounded claims (1 call).

## Theoretical foundations {#theoretical-foundations}

Generalizes the "lineage graph governance layer" concept from Xie et
al., which demonstrated that provenance-tracking middleware improves
pipeline defense rate from 0.32 to 0.89 against cascade errors
without changing the underlying model. Also informed by MAST (Cemri
et al., 2025), which found 41.8% of multi-agent system failures
originate from system design rather than model performance; lineage
tracking addresses the "information loss at handoff" failure mode
(MAST category F7).

## References {#references}

- Xie, ... et al. (2026). "From Spark to Fire: Diagnosing and
  Overcoming the Fragility of Multi-Agent Systems". AAMAS 2026.
- Cemri, ... et al. (2025). MAST failure-mode taxonomy (F7).
ctx.summary_tokens: Max tokens for final summary (default: 600)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.extract_tokens` | number | optional | Max tokens per claim extraction (default 600) |
| `ctx.steps` | array of shape { name: string, output: string } | **required** | Ordered step outputs; at least 2 entries (required) |
| `ctx.summary_tokens` | number | optional | Max tokens for conflict/integrity summary (default 600) |
| `ctx.task` | string | **required** | Original task description passed to trace/summary prompts (required) |
| `ctx.trace_tokens` | number | optional | Max tokens per dependency trace (default 500) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `analysis` | string | — | Full conflict/ungrounded/drift analyzer output |
| `integrity_score` | number | optional | Parsed SCORE in [0, 1]; nil when the analyzer did not emit a parseable score |
| `lineage_graph` | string | — | Human-readable lineage graph text used as input to the conflict analyzer |
| `step_claims` | array of shape { claims: array of shape { id: number, text: string }, name: string, raw: string } | — | Per-step extracted claims |
| `traces` | array of shape { from_step: string, raw: string, to_step: string, traces: array of shape { derives_from?: array of any, id: number, transformation?: string } } | — | Consecutive-step dependency traces |
