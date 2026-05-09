---
name: mcts
version: 0.1.0
category: reasoning
result_shape: "shape { best_path: array of shape { avg_score: number, thought: string, visits: number }, conclusion: string, total_iterations: number, tree_stats: shape { exploration_constant: number, max_depth: number, root_children: number, root_visits: number } }"
description: "Monte Carlo Tree Search — selection, expansion, simulation, backpropagation for reasoning"
source: mcts/init.lua
generated: gen_docs (V0)
---

# mcts(MCTS) — Monte Carlo Tree Search reasoning

> Applies MCTS to LLM reasoning with selection (UCB1), expansion (generate), simulation (rollout to conclusion), and backpropagation (update scores). Explores deep reasoning trees more efficiently than exhaustive search.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local mcts = require("mcts")
return mcts.run(ctx)
```

## Algorithm {#algorithm}

1. Selection — descend with UCB1 to a promising leaf.
2. Expansion — generate new children with the LLM.
3. Simulation — roll out to a conclusion and score it.
4. Backpropagation — propagate the score back up to the root.

Optional reflection mechanism (`ctx.reflection = true`): when a
simulation scores below the reflection threshold, the LLM generates a
one-sentence diagnosis of why the path failed. The reflections are
accumulated and injected into subsequent expansion prompts to help
the search avoid repeating the same mistakes.

## References {#references}

- Hao, S. et al. (2023). "Reasoning with Language Model is Planning
  with World Model" (RAP). https://arxiv.org/abs/2305.14992
- Zhou, A. et al. (2024). "Language Agent Tree Search Unifies
  Reasoning, Acting, and Planning in Language Models" (LATS).
  ICML 2024. https://arxiv.org/abs/2310.04406
- Xu, ... et al. (2025). "CogMCTS: Cognitive-Guided Monte Carlo Tree
  Search". https://arxiv.org/abs/2512.08609

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
