---
name: setwise_rank
version: 0.1.0
category: selection
result_shape: "shape { best: string, best_index: number, killed: array of shape { index: number, rank: number, text: string }, n_candidates: number, ranked: array of shape { index: number, rank: number, text: string }, set_size: number, top_k: array of shape { index: number, rank: number, text: string }, total_llm_calls: number }"
description: "Setwise tournament reranking — LLM picks the best from small sets and winners advance. Mid-cost/mid-accuracy sweet spot between listwise and pairwise. Resolves calibration issue."
source: setwise_rank/init.lua
generated: gen_docs (V0)
---

# setwise_rank(SetwiseRank) — setwise tournament reranking

> Ranks N candidates by repeatedly asking the LLM "which is the best among these k items?" and advancing winners through tournament rounds. Each comparison spans a set (size k) rather than a pair, dramatically reducing LLM calls vs pairwise while keeping the LLM task simpler than listwise (pick one best, not a full permutation). The setwise reformulation is free of the absolute-score calibration problem of pointwise judging.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Comparison with related packages](#comparison-with-related-packages)
- [Empirical validation](#empirical-validation)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local sr = require("setwise_rank")
return sr.run(ctx)
```

## Algorithm {#algorithm}

Iterative top-k extraction:

```text
active ← {1..N}
for rank = 1 .. top_k do
  while #active > 1 do
    partition active into groups of size set_size
    for each group of size >= 2: LLM picks the best index
    active ← winners ∪ singleton-groups
  end
  ranked[rank] ← active[1]
  remove ranked[rank] from pool; restart with remaining
end
```

## Comparison with related packages {#comparison-with-related-packages}

- `listwise_rank` — 1 LLM call to rank all; cheapest but limited by
  context, list-position bias risk.
- `setwise_rank` — tournament with set comparisons of size `k`;
  `O(top_k · N / k)` LLM calls. Mid-cost / mid-accuracy. Sweet spot
  for moderate N (10-50).
- `pairwise_rank` — pure pairwise (`O(N²)` or `O(N log N)`); highest
  accuracy.

## Empirical validation {#empirical-validation}

- Setwise with Flan-T5 matches RankGPT (listwise) on TREC-DL19/20.
- More efficient than pairwise; comparable accuracy to listwise with
  better robustness to position bias.

## References {#references}

- Zhuang, S. et al. (2024). "A Setwise Approach for Effective and
  Highly Efficient Zero-shot Ranking with Large Language Models".
  SIGIR 2024. https://arxiv.org/abs/2310.09497

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.candidates` | array of string | **required** | Candidate texts to rank (>= 2) |
| `ctx.gen_tokens` | number | optional | Max tokens per pick response (default: 20) |
| `ctx.set_size` | number | optional | Tournament group size (default: 4) |
| `ctx.task` | string | **required** | Ranking criterion |
| `ctx.top_k` | number | optional | How many to keep (default: N = full ranked list) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Text of the #1 candidate |
| `best_index` | number | — | Original 1-based index of the #1 candidate |
| `killed` | array of shape { index: number, rank: number, text: string } | — | Unranked tail (candidates not extracted into top_k) |
| `n_candidates` | number | — | Total number of input candidates |
| `ranked` | array of shape { index: number, rank: number, text: string } | — | Full ranked list: top_k winners followed by unranked tail |
| `set_size` | number | — | Tournament group size actually used |
| `top_k` | array of shape { index: number, rank: number, text: string } | — | Winners (the top-k portion of ranked) |
| `total_llm_calls` | number | — | Count of pick_best LLM calls performed |
