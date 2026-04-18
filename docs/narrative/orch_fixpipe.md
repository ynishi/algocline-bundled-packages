---
name: orch_fixpipe
version: 0.1.0
category: orchestration
result_shape: "shape { final_output: string, phases: array of shape { attempts: number, gate_passed: boolean, name: string, output: string }, status: string, total_llm_calls: number }"
description: "Deterministic fixed pipeline with gate/retry. Phases execute in strict order. Gate NG triggers retry up to max_retries. Based on Lobster (OpenClaw) deterministic workflow pattern."
source: orch_fixpipe/init.lua
generated: gen_docs (V0)
---

# orch_fixpipe — Deterministic Fixed Pipeline

> Phases execute in strict order. Gate NG triggers retry up to max_retries. Based on Lobster (OpenClaw) deterministic workflow pattern.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.context_mode` | string | optional | "summary" \| "full" (default: "summary") |
| `ctx.max_retries` | number | optional | Gate NG retry limit (default: 3) |
| `ctx.on_fail` | string | optional | "error" \| "partial" (default: "error") |
| `ctx.phases` | array of any | **required** | Phase definitions (opaque user-supplied records) |
| `ctx.task` | string | **required** | Task description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `final_output` | string | — | Last phase output (empty on failure before first phase) |
| `phases` | array of shape { attempts: number, gate_passed: boolean, name: string, output: string } | — | Per-phase execution record |
| `status` | string | — | "completed" / "failed" / "partial" |
| `total_llm_calls` | number | — | Total LLM invocations |
