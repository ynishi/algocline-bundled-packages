---
name: tot
version: 0.1.0
category: reasoning
result_shape: "shape { best_path: array of string, best_score: number, conclusion: string, explored_paths: array of shape { path: array of string, rank: number, score: number }, tree_stats: shape { beam_width: number, breadth: number, depth: number } }"
description: "Tree-of-Thought — branching reasoning with evaluation and pruning"
source: tot/init.lua
generated: gen_docs (V0)
---

# ToT — Tree-of-Thought reasoning

> Explores multiple reasoning paths via branching, evaluation, and pruning. Unlike linear CoT, ToT maintains a tree of thought branches and uses beam search to focus on the most promising paths.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.beam_width` | number | optional | Branches kept after pruning (default: 2) |
| `ctx.breadth` | number | optional | Thoughts generated per beam node (default: 3) |
| `ctx.depth` | number | optional | Maximum tree depth (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |
