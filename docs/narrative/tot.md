---
name: tot
version: 0.1.0
category: reasoning
result_shape: "shape { best_path: array of string, best_score: number, conclusion: string, explored_paths: array of shape { path: array of string, rank: number, score: number }, tree_stats: shape { beam_width: number, breadth: number, depth: number } }"
description: "Tree-of-Thought — branching reasoning with evaluation and pruning"
source: tot/init.lua
generated: gen_docs (V0)
---

# tot(ToT) — beam-search tree-of-thought reasoning over branching thought paths

> Explores multiple reasoning paths by generating candidate thoughts at each depth level, scoring them, and pruning to the top-scoring beams. Synthesizes the best beam path into a final answer.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local tot = require("tot")
return tot.run(ctx)
```

## Algorithm {#algorithm}

Given a task and beam parameters (breadth B, depth D, beam width K):

1. At each depth d ∈ {1..D}, for every surviving beam, generate B candidate
   thoughts via `alc.llm` (thought generation prompt).
2. Score each candidate thought with a separate `alc.llm` call that rates
   logical soundness and progress on a 1-10 scale.
3. Prune all candidates to the top-K by score (beam search step).
4. After D rounds, synthesize the best-scored beam path into a conclusion
   via a final `alc.llm` call.

Beam search complexity: O(D × K × B) LLM calls for generation +
O(D × K × B) calls for scoring = O(D × K × B) total.

## Theoretical foundations {#theoretical-foundations}

Yao et al. (2023) show that deliberate search over a tree of thoughts
outperforms linear chain-of-thought (CoT) on tasks requiring exploration,
strategic look-ahead, or backtracking. The beam-search variant implemented
here approximates the BFS/DFS variants in the paper with a fixed-width
pruning step that trades completeness for bounded LLM call count.

## References {#references}

- Yao, S., Yu, D., Zhao, J., Shafran, I., Griffiths, T. L., Cao, Y.,
  and Narasimhan, K. (2023). "Tree of Thoughts: Deliberate Problem Solving
  with Large Language Models". arXiv:2305.10601.
  https://arxiv.org/abs/2305.10601

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.beam_width` | number | optional | Branches kept after pruning (default: 2) |
| `ctx.breadth` | number | optional | Thoughts generated per beam node (default: 3) |
| `ctx.depth` | number | optional | Maximum tree depth (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best_path` | array of string | — | Best beam path: ordered reasoning steps |
| `best_score` | number | — | Score of the best beam (1-10) |
| `conclusion` | string | — | Synthesized final answer from the best-scored beam path |
| `explored_paths` | array of shape { path: array of string, rank: number, score: number } | — | All surviving beams, rank-ordered by score |
| `tree_stats` | shape { beam_width: number, breadth: number, depth: number } | — | Configuration echo for traceability |
