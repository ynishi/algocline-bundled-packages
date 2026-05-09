---
name: qdaif
version: 0.1.0
category: exploration
result_shape: "shape { archive: array of shape { candidate: string, cell: string, features: array of string, score: number }, best?: string, best_score: number, coverage: number, stats: shape { filled_cells: number, iterations: number, seed_count: number, total_cells: number } }"
description: "Quality-Diversity through AI Feedback — MAP-Elites archive with LLM-driven mutation, evaluation, and feature classification. Produces diverse, high-quality solution populations."
source: qdaif/init.lua
generated: gen_docs (V0)
---

# qdaif(QDAIF) — Quality-Diversity through AI Feedback (MAP-Elites)

> Maintains a MAP-Elites archive (feature-space × quality grid) using only LLM calls. Generates diverse, high-quality solutions by seeding the archive, selecting elites, mutating via LLM, evaluating quality and feature placement via LLM, and inserting into the archive when superior. Unlike `optimize` (single best) or `diverse` (sample then pick), `qdaif` structurally maintains a population of elite solutions across a feature space, ensuring quality and diversity simultaneously.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local qdaif = require("qdaif")
return qdaif.run(ctx)
```

## Algorithm {#algorithm}

1. Seed — generate initial candidates.
2. For each of `iterations` cycles:
   - Select — pick an elite from the archive (empty-cell priority).
   - Mutate — LLM generates a variant of the selected elite.
   - Evaluate — LLM scores quality and assigns the feature bin.
   - Insert — replace the archive cell if the new candidate is
     better.
3. Return the archive and the best elite.

## References {#references}

- Bradley, H. et al. (2024). "Quality-Diversity through AI Feedback".
  ICLR 2024. https://arxiv.org/abs/2310.13032
- Lehman, J. et al. "Evolution through Large Models" (OpenELM).
- Mouret, J.-B., Clune, J. (2015). "Illuminating search spaces by
  mapping elites". https://arxiv.org/abs/1504.04909

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.elite_tokens` | number | optional | Max tokens for candidate generation (default: 400) |
| `ctx.features` | array of shape { bins: array of string, name: string } | **required** | Feature axes defining the MAP-Elites grid |
| `ctx.iterations` | number | optional | Mutation-evaluation cycles (default: 20) |
| `ctx.seed_count` | number | optional | Initial candidates to generate (default: 5) |
| `ctx.task` | string | **required** | Problem / domain description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `archive` | array of shape { candidate: string, cell: string, features: array of string, score: number } | — | Archive elites sorted by score descending |
| `best` | string | optional | Archive-best candidate (nil if archive empty) |
| `best_score` | number | — | Best score across the archive |
| `coverage` | number | — | filled_cells / total_cells ∈ [0,1] |
| `stats` | shape { filled_cells: number, iterations: number, seed_count: number, total_cells: number } | — | Quality-diversity statistics |
