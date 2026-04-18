---
name: lineage
version: 0.1.0
category: governance
result_shape: "shape { analysis: string, integrity_score?: number, lineage_graph: string, step_claims: array of shape { claims: array of shape { id: number, text: string }, name: string, raw: string }, traces: array of shape { from_step: string, raw: string, to_step: string, traces: array of shape { derives_from?: array of any, id: number, transformation?: string } } }"
description: "Pipeline-spanning claim lineage tracking — extracts claims per step, traces inter-step dependencies, detects conflicts and ungrounded claims. Generalizes the lineage graph governance layer from 'From Spark to Fire' (Xie et al., AAMAS 2026). Defense rate improvement: 0.32 → 0.89."
source: lineage/init.lua
generated: gen_docs (V0)
---

# lineage — Pipeline-spanning claim lineage tracking

> Tracks the provenance of claims across multi-step pipelines. Extracts atomic claims from each step's output, traces inter-step dependencies (which claim in step N derived from which claim in step N-1), and detects conflicts and ungrounded claims in the final output.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.extract_tokens` | number | optional | Max tokens per claim extraction (default 600) |
| `ctx.steps` | array of shape { name: string, output: string } | **required** | Ordered step outputs; at least 2 entries (required) |
| `ctx.summary_tokens` | number | optional | Max tokens for conflict/integrity summary (default 600) |
| `ctx.task` | string | **required** | Original task description passed to trace/summary prompts (required) |
| `ctx.trace_tokens` | number | optional | Max tokens per dependency trace (default 500) |
