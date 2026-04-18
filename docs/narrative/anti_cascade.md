---
name: anti_cascade
version: 0.1.0
category: governance
result_shape: "shape { flagged_steps: array of string, max_drift: number, step_results: array of shape { cascade_risk: string, drift_score: number, drift_type: string, flagged: boolean, name: string, raw: string }, summary: string }"
description: "Pipeline error cascade detection — independently re-derives from original inputs at each step and compares with pipeline output to detect error amplification. Generalizes Cascade Amplification countermeasure from 'From Spark to Fire' (Xie et al., AAMAS 2026). Addresses MAST failure modes F3/F9."
source: anti_cascade/init.lua
generated: gen_docs (V0)
---

# anti_cascade — Pipeline error cascade amplification detection

> Detects when small errors compound through multi-step pipelines by independently re-deriving conclusions from original inputs at each checkpoint, then comparing with the pipeline's accumulated output. Flags steps where drift exceeds threshold.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.compare_tokens` | number | optional | Max tokens per pipeline-vs-independent comparison (default 400) |
| `ctx.drift_threshold` | number | optional | Drift score threshold at which a step is flagged (default 0.4) |
| `ctx.rederive_tokens` | number | optional | Max tokens per independent re-derivation (default 500) |
| `ctx.steps` | array of shape { instruction?: string, name: string, output: string } | **required** | Ordered pipeline step outputs; at least 1 entry (required) |
| `ctx.summary_tokens` | number | optional | Max tokens for the final summary analysis (default 500) |
| `ctx.task` | string | **required** | Original task/input that the pipeline was given (required) |
