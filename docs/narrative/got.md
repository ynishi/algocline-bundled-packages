---
name: got
version: 0.1.0
category: reasoning
result_shape: "shape { aggregated_reasoning: string, answer: string, graph_stats: shape { branches_generated: number, branches_kept: number, operations: map of string to number, refine_rounds: number, total_nodes: number } }"
description: "Graph of Thoughts — DAG-structured reasoning with aggregation, refinement, and multi-path synthesis. Enables thought merging impossible in tree-based approaches (ToT)."
source: got/init.lua
generated: gen_docs (V0)
---

# GoT — Graph of Thoughts reasoning

> Models reasoning as a DAG (Directed Acyclic Graph) enabling operations impossible in tree structures: aggregation of multiple thought paths, self-refinement loops, and hierarchical decomposition with merge.

## Contents

- [Parameters](#parameters)
- [Result](#result)

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
