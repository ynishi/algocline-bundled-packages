---
name: orch_adaptive
version: 0.1.0
category: orchestration
result_shape: "shape { active_phase_count: number, depth_config: table, difficulty: string, final_output: string, phases: array of shape { attempts: number, gate_passed: boolean, name: string, output: string }, status: string, total_llm_calls: number, total_phase_count: number }"
description: "Adaptive-depth orchestration: tune phase count and budget by task difficulty."
source: orch_adaptive/init.lua
generated: gen_docs (V0)
---

# orch_adaptive(OrchAdaptive) — adaptive-depth orchestration by task difficulty

> Dynamically adjusts phase count, retry budget, and context mode based on task difficulty. Combines with `router_daao` for pre-classified difficulty or estimates internally.

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local orch = require("orch_adaptive")
return orch.run(ctx)
```

## References {#references}

- DAAO. https://arxiv.org/abs/2509.11079

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.depth_config` | any | optional | Custom difficulty→config mapping (opaque) |
| `ctx.difficulty` | string | optional | Pre-classified difficulty (simple\|medium\|complex) |
| `ctx.on_fail` | string | optional | "error" \| "partial" (default: "error") |
| `ctx.phases` | array of any | **required** | Phase definitions (superset; trimmed by difficulty) |
| `ctx.task` | string | **required** | Task description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `active_phase_count` | number | — | Phases actually run (min(max_phases, #phases)) |
| `depth_config` | table | — | Active depth config (max_phases / max_retries / context_mode / max_tokens) |
| `difficulty` | string | — | Final difficulty (pre-classified or estimated) |
| `final_output` | string | — | Last phase output (empty on failure before first phase) |
| `phases` | array of shape { attempts: number, gate_passed: boolean, name: string, output: string } | — | Per-phase execution record |
| `status` | string | — | "completed" / "failed" / "partial" |
| `total_llm_calls` | number | — | Total LLM invocations |
| `total_phase_count` | number | — | Original phase count |
