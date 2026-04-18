---
name: orch_gatephase
version: 0.1.0
category: orchestration
result_shape: "shape { final_output: string, phases: array of shape { attempts: number, gate_passed: boolean, name: string, output: string }, skipped_phases: array of string, status: string, task_type: string, total_llm_calls: number }"
description: "Phase orchestration with pre/post hooks and skip rules. Each phase has pre-event (context setup) and post-event (gate + checks). Task type determines which phases to skip. Based on Thin Agent / Fat Platform (Praetorian)."
source: orch_gatephase/init.lua
generated: gen_docs (V0)
---

# orch_gatephase — Gate-Phase Orchestration with Pre/Post Hooks

> Each phase has pre-event (context setup) and post-event (gate + checks). Task type determines which phases to skip. Based on Thin Agent / Fat Platform (Praetorian).

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_retries` | number | optional | Gate NG retry limit (default: 3) |
| `ctx.on_fail` | string | optional | "error" \| "partial" (default: "error") |
| `ctx.phases` | array of any | **required** | Phase definitions [{name, prompt, gate, checks, ...}, ...] |
| `ctx.skip_rules` | any | optional | Custom skip rules table (opaque) |
| `ctx.task` | string | **required** | Task description |
| `ctx.task_type` | string | optional | Pre-classified type (bugfix\|typo\|refactor\|feature\|test) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `final_output` | string | — | Last phase output (empty on failure before first phase) |
| `phases` | array of shape { attempts: number, gate_passed: boolean, name: string, output: string } | — | Per-phase execution record (active only) |
| `skipped_phases` | array of string | — | Phase names skipped for this task_type |
| `status` | string | — | "completed" / "failed" / "partial" |
| `task_type` | string | — | Final task type (pre-classified or estimated) |
| `total_llm_calls` | number | — | Total LLM invocations |
