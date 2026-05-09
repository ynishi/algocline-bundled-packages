---
name: diverse
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, best_avg_score: number, best_path_id: number, paths: array of shape { path_id: number, reasoning: string, verification: shape { avg_score: number, step_scores: array of shape { score: number, step: string }, total_score: number } }, ranking: array of shape { avg_score: number, path_id: number, rank: number, steps_verified: number } }"
description: "DiVERSe — diverse reasoning paths with step-level verification and selection"
source: diverse/init.lua
generated: gen_docs (V0)
---

# diverse(DiVERSe) — diverse reasoning paths with step-level verification

> Generates multiple diverse reasoning paths, then verifies each path at the step level (not just the final answer). Selects the path with the highest step-level verification score.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local diverse = require("diverse")
return diverse.run(ctx)
```

## Algorithm {#algorithm}

1. **Generate**: produce `n_paths` diverse reasoning paths by prompting
   with increasingly divergent instructions (straightforward → alternative
   → explicitly different from prior paths).
2. **Verify**: for each path, parse individual steps (numbered or
   sentence-split) and send each step to a step-level verifier LLM that
   rates correctness 1-10 given the task and prior steps.
3. **Select**: rank paths by average step score; pick the highest-scoring
   path as the winner.
4. **Synthesize**: ask the LLM to produce a final answer grounded in the
   winning path's reasoning chain.

## Theoretical foundations {#theoretical-foundations}

DiVERSe (Li et al., 2022) shows that step-level process reward models
outperform outcome reward models on mathematical reasoning benchmarks.
Verifying individual steps rather than only the final answer catches
faulty intermediate conclusions that happen to reach a correct endpoint.

## References {#references}

- Li, Y., Lin, Z., Liu, Z., Fu, Q., Lou, J.-G., Chen, W., Deng, Z. (2022).
  "Making Large Language Models Better Reasoners with Step-Aware Verifier".
  arXiv:2206.02336.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n_paths` | number | optional | Number of diverse reasoning paths (default: 3) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesized answer from the best path |
| `best_avg_score` | number | — | Average step score of the winning path |
| `best_path_id` | number | — | path_id of the highest-scoring path |
| `paths` | array of shape { path_id: number, reasoning: string, verification: shape { avg_score: number, step_scores: array of shape { score: number, step: string }, total_score: number } } | — | All generated paths with verification details (sorted) |
| `ranking` | array of shape { avg_score: number, path_id: number, rank: number, steps_verified: number } | — | Paths ordered from best to worst by avg_score |
