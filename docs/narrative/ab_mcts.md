---
name: ab_mcts
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_path: array of string, best_score: number, tree_stats: shape { branching_ratio: number, budget: number, deeper_decisions: number, max_depth: number, total_nodes: number, wider_decisions: number } }"
description: "Adaptive branching MCTS with Thompson Sampling — wider/deeper per node"
source: ab_mcts/init.lua
generated: gen_docs (V0)
---

# ab_mcts(AB-MCTS) — adaptive branching MCTS with Thompson Sampling

> Extends standard MCTS by dynamically deciding at each node whether to explore wider (generate new candidates) or deeper (refine existing ones). Uses Thompson Sampling with Beta posteriors instead of UCB1, enabling principled exploration-exploitation balance that adapts to problem structure.

## Contents

- [Algorithm](#algorithm)
- [Usage](#usage)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

Pipeline (`2 * budget + 1` LLM calls). For each iteration:

1. **Selection** — Thompson Sampling down the tree using Beta posteriors
2. **Expansion** — generate new or refine existing (1 LLM call)
3. **Evaluation** — score the result (1 LLM call)
4. **Backprop** — update Beta posteriors along the path

Final step: synthesize the best answer from the highest-scoring leaf.

## Usage {#usage}

```lua
local ab_mcts = require("ab_mcts")
return ab_mcts.run(ctx)
```

## Comparison with related packages {#comparison-with-related-packages}

vs `mcts`: standard MCTS uses UCB1 with fixed branching. AB-MCTS
introduces a virtual GEN node at each position — when Thompson
Sampling selects GEN over existing children, a new candidate is
generated (wider). When an existing child is selected, it is
refined (deeper). This yields adaptive branching tuned to problem
structure.

vs `tot` / `got`: those use fixed-shape thought trees / graphs.
AB-MCTS's branching shape is data-driven via posterior sampling.

## References {#references}

Inoue et al. (2025). "Wider or Deeper? Scaling LLM Inference-Time
Compute with Adaptive Branching Tree Search". NeurIPS 2025 Spotlight.
arXiv:2503.04412.

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
