---
name: ab_mcts
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_path: array of string, best_score: number, tree_stats: shape { branching_ratio: number, budget: number, deeper_decisions: number, max_depth: number, total_nodes: number, wider_decisions: number } }"
description: "Adaptive Branching MCTS — Thompson Sampling with dynamic wider/deeper decisions. GEN node mechanism for principled branching. Consistently outperforms standard MCTS and repeated sampling."
source: ab_mcts/init.lua
generated: gen_docs (V0)
---

# ab_mcts — Adaptive Branching Monte Carlo Tree Search

> Extends standard MCTS by dynamically deciding at each node whether to explore wider (generate new candidates) or deeper (refine existing ones). Uses Thompson Sampling with Beta posteriors instead of UCB1, enabling principled exploration-exploitation balance that adapts to problem structure.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha_prior` | number | optional | Beta prior alpha for Thompson sampling (default: 1.0) |
| `ctx.beta_prior` | number | optional | Beta prior beta for Thompson sampling (default: 1.0) |
| `ctx.budget` | number | optional | Total expansion iterations (default: 8) |
| `ctx.gen_tokens` | number | optional | Max tokens for generation/refinement (default: 400) |
| `ctx.max_depth` | number | optional | Maximum tree depth (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesized answer from the best leaf |
| `best_path` | array of string | — | Thought sequence from root to best leaf |
| `best_score` | number | — | Best leaf score in [0,1] |
| `tree_stats` | shape { branching_ratio: number, budget: number, deeper_decisions: number, max_depth: number, total_nodes: number, wider_decisions: number } | — | AB-MCTS statistics |
