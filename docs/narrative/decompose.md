---
name: decompose
version: 0.1.0
category: planning
result_shape: "shape { answer: string, decomposition_raw: string, subtask_results: array of string, subtasks: array of string }"
description: "Task decomposition — LLM-driven split, parallel execution, merge"
source: decompose/init.lua
generated: gen_docs (V0)
---

# Decompose — task decomposition and parallel sub-task execution

> Breaks a complex task into sub-tasks via LLM, executes each in parallel, then merges results into a unified answer.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_subtasks` | number | optional | Maximum sub-tasks to generate (default: 5) |
| `ctx.merge_tokens` | number | optional | Max tokens for final merge (default: 600) |
| `ctx.subtask_tokens` | number | optional | Max tokens per sub-task (default: 400) |
| `ctx.task` | string | **required** | The complex task to decompose |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Unified merged answer across sub-tasks |
| `decomposition_raw` | string | — | Raw decomposition LLM output before parsing |
| `subtask_results` | array of string | — | Per-sub-task LLM outputs, same order as subtasks |
| `subtasks` | array of string | — | Parsed sub-task descriptions (fallback: single-element = original task) |
