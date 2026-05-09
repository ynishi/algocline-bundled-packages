---
name: decompose
version: 0.1.0
category: planning
result_shape: "shape { answer: string, decomposition_raw: string, subtask_results: array of string, subtasks: array of string }"
description: "Task decomposition — LLM-driven split, parallel execution, merge"
source: decompose/init.lua
generated: gen_docs (V0)
---

# decompose — task decomposition and parallel sub-task execution

> Breaks a complex task into sub-tasks via LLM, executes each in parallel, then merges results into a unified answer.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local decompose = require("decompose")
return decompose.run(ctx)
```

## Algorithm {#algorithm}

1. Decompose — prompt the LLM to split the task into N independent
   sub-tasks (numbered list); falls back to single-task if parsing yields
   nothing.
2. Execute — run all sub-tasks in parallel via `alc.parallel`, each
   with full context of the overall goal.
3. Merge — synthesize all sub-task results into a unified, coherent
   answer, resolving inconsistencies and preserving completeness.

## Theoretical foundations {#theoretical-foundations}

Task decomposition draws on divide-and-conquer planning principles
formalised in TDAG (Task Decomposition with Action Graphs, 2025) and
HiPlan (Hierarchical Planning, 2025). Agent-Oriented Planning research
establishes that decomposing into self-contained, collectively exhaustive,
non-overlapping sub-tasks improves both accuracy and parallelism when
sub-tasks are independently solvable.

## References {#references}

- TDAG: Task Decomposition with Action Graphs (2025).
- HiPlan: Hierarchical Planning for LLM Agents (2025).
- Agent-Oriented Planning in Multi-Agent Systems (2025).

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
