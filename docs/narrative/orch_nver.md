---
name: orch_nver
version: 0.1.0
category: orchestration
result_shape: "shape { best_reasoning?: string, best_score?: number, method: string, rankings?: array of shape { output: string, phase_outputs?: array of shape { name: string, output: string }, reasoning: string, score: number, variant_id: number }, selected: string, status: string, total_llm_calls: number, variants?: array of shape { output: string, phase_outputs?: array of shape { name: string, output: string }, variant_id: number } }"
description: "N-version programming: execute N parallel variants, evaluate each, select best. Trades cost for quality. Based on N-version approach from Agentic SE Roadmap (arxiv 2509.06216). Mitigates 29.6% regression rate found in SWE-Bench audits."
source: orch_nver/init.lua
generated: gen_docs (V0)
---

# orch_nver — N-version Programming Orchestration

> Execute N parallel variants, evaluate each, select best. Trades cost for quality. Mitigates 29.6% regression rate (SWE-Bench).

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n` | number | optional | Number of parallel variants (default: 3) |
| `ctx.phases` | array of any | optional | Phase definitions for each variant's pipeline |
| `ctx.selection` | string | optional | "score" \| "vote" (default: "score") |
| `ctx.task` | string | **required** | Task description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best_reasoning` | string | optional | Reasoning for the top-ranked variant (score-branch only) |
| `best_score` | number | optional | Highest score (score-branch only) |
| `method` | string | — | Selection method actually used ("score" \| "vote") |
| `rankings` | array of shape { output: string, phase_outputs?: array of shape { name: string, output: string }, reasoning: string, score: number, variant_id: number } | optional | Variants sorted by score desc (score-branch only) |
| `selected` | string | — | Selected variant's final output |
| `status` | string | — | "completed" |
| `total_llm_calls` | number | — | Total LLM invocations |
| `variants` | array of shape { output: string, phase_outputs?: array of shape { name: string, output: string }, variant_id: number } | optional | Raw variants (vote-branch only) |
