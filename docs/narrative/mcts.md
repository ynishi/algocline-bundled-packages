---
name: mcts
version: 0.1.0
category: reasoning
result_shape: "shape { best_path: array of shape { avg_score: number, thought: string, visits: number }, conclusion: string, total_iterations: number, tree_stats: shape { exploration_constant: number, max_depth: number, root_children: number, root_visits: number } }"
description: "Monte Carlo Tree Search — selection, expansion, simulation, backpropagation for reasoning"
source: mcts/init.lua
generated: gen_docs (V0)
---

# MCTS — Monte Carlo Tree Search reasoning

> Applies MCTS to LLM reasoning: selection (UCB1), expansion (generate), simulation (rollout to conclusion), backpropagation (update scores). Explores deep reasoning trees more efficiently than exhaustive search.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.exploration` | number | optional | UCB1 exploration constant C (default: √2 ≈ 1.41) |
| `ctx.iterations` | number | optional | Number of MCTS iterations (default: 6) |
| `ctx.max_depth` | number | optional | Maximum tree depth per rollout (default: 3) |
| `ctx.max_reflections` | number | optional | Maximum stored reflections (default: 5) |
| `ctx.reflection` | boolean | optional | Enable reflection on low-score paths (default: false) |
| `ctx.reflection_threshold` | number | optional | Score below which reflection triggers (default: 4) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best_path` | array of shape { avg_score: number, thought: string, visits: number } | — | Best path from root to leaf |
| `conclusion` | string | — | Synthesized final answer from the best path |
| `total_iterations` | number | — | Iterations actually performed |
| `tree_stats` | shape { exploration_constant: number, max_depth: number, root_children: number, root_visits: number } | — | Tree-level statistics |
