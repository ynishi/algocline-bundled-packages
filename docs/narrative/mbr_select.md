---
name: mbr_select
version: 0.1.0
category: selection
result_shape: "shape { best: string, best_index: number, best_mbr_score: number, candidates: array of string, ranking: array of shape { index: number, mbr_score: number }, similarity_matrix: array of array of number, total_llm_calls: number }"
description: "Minimum Bayes Risk selection: pick candidate with highest pairwise agreement."
source: mbr_select/init.lua
generated: gen_docs (V0)
---

# mbr_select(MBRSelect) — Minimum Bayes Risk candidate selection

> Selects the candidate that minimizes expected loss across all other candidates. Instead of picking "the best" directly (which requires an absolute quality oracle), MBR picks the candidate most agreed-upon by the others — the one with minimum expected risk.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local mbr = require("mbr_select")
return mbr.run(ctx)
```

## Theoretical foundations {#theoretical-foundations}

```math
argmin_y E_{y'~P}[L(y, y')]   ≡   argmax_y E_{y'~P}[similarity(y, y')]
```

where `L = 1 - similarity`. This is the Bayes-optimal decision under
the candidate distribution.

## Comparison with related packages {#comparison-with-related-packages}

- `rank` — single-elimination tournament with pairwise LLM-as-Judge.
  `O(N log N)` comparisons. Subject to bracket luck: a strong
  candidate can be eliminated by a flawed matchup; A/B position bias
  affects results.
- `mbr_select` — computes pairwise similarity for all pairs and
  selects the candidate with highest total agreement. `O(N²/2)`
  symmetric comparisons. No bracket luck and mathematically optimal
  under Bayes decision theory.

## References {#references}

- "Regularized Best-of-N Sampling with Minimum Bayes Risk" (NAACL
  2025).
- Eikema, B., Aziz, W. (2020). MBR decoding literature.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.criteria` | string | optional | Similarity criteria (default: substantive agreement) |
| `ctx.gen_tokens` | number | optional | Max tokens per candidate (default: 400) |
| `ctx.n` | number | optional | Number of candidates to generate (default: 5) |
| `ctx.sim_tokens` | number | optional | Max tokens per similarity judgment (default: 80) |
| `ctx.task` | string | **required** | The task to generate candidates for |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Text of the MBR-selected candidate |
| `best_index` | number | — | 1-based index of the selected candidate |
| `best_mbr_score` | number | — | Expected similarity score (0-1) of the winner |
| `candidates` | array of string | — | All generated candidate texts |
| `ranking` | array of shape { index: number, mbr_score: number } | — | All candidates sorted by MBR score descending |
| `similarity_matrix` | array of array of number | — | Symmetric N×N pairwise similarity matrix (values in [0, 1]) |
| `total_llm_calls` | number | — | Generation calls (N) + pairwise similarity calls (N(N-1)/2) |
