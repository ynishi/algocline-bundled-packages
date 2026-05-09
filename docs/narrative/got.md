---
name: got
version: 0.1.0
category: reasoning
result_shape: "shape { aggregated_reasoning: string, answer: string, graph_stats: shape { branches_generated: number, branches_kept: number, operations: map of string to number, refine_rounds: number, total_nodes: number } }"
description: "Graph of Thoughts: DAG reasoning with aggregation, refinement, and synthesis."
source: got/init.lua
generated: gen_docs (V0)
---

# got(GoT) — Graph of Thoughts reasoning over a DAG

> Models reasoning as a directed acyclic graph, enabling operations impossible in tree structures: aggregation of multiple thought paths, self-refinement loops, and hierarchical decomposition with merge. Unlike `tot`, `got` supports Aggregate (many-to-one merge) where independent branches combine into a superior synthesis.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local got = require("got")
return got.run(ctx)
```

## Algorithm {#algorithm}

Operations:

- Generate — branch one thought into `k` new thoughts (1-to-many).
- Aggregate — merge `k` thoughts into one synthesis (GoT-unique).
- Refine — improve a thought in place (self-loop).
- Score — evaluate thought quality (LLM or custom function).
- KeepBest — prune to top-`n` thoughts by score.

Default Graph-of-Operations pipeline:

```text
Generate(k) → Score → KeepBest(n) → Refine → Aggregate → Refine → Answer
```

## References {#references}

- Besta, M. et al. (2024). "Graph of Thoughts: Solving Elaborate
  Problems with Large Language Models". AAAI 2024.
  https://arxiv.org/abs/2308.09687

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agg_tokens` | number | optional | Max tokens for Aggregate / final synthesis (default: 500) |
| `ctx.gen_tokens` | number | optional | Max tokens for Generate step (default: 300) |
| `ctx.k_generate` | number | optional | Branches per Generate (default: 3) |
| `ctx.keep_best` | number | optional | Nodes to keep after KeepBest pruning (default: 2) |
| `ctx.max_refine` | number | optional | Max refinement rounds on kept thoughts (default: 2) |
| `ctx.refine_tokens` | number | optional | Max tokens for Refine step (default: 400) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `aggregated_reasoning` | string | — | State of the merged node produced by the Aggregate op (after final Refine) |
| `answer` | string | — | Final synthesized answer from the aggregated reasoning |
| `graph_stats` | shape { branches_generated: number, branches_kept: number, operations: map of string to number, refine_rounds: number, total_nodes: number } | — | Graph-shape diagnostics; operations is { [origin_op] = count } |
