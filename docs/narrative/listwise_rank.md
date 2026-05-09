---
name: listwise_rank
version: 0.1.0
category: selection
result_shape: listwise_ranked
description: "Zero-shot listwise reranking via permutation generation with sliding window."
source: listwise_rank/init.lua
generated: gen_docs (V0)
---

# listwise_rank(ListwiseRank) — zero-shot listwise reranking with sliding window

> Ranks N pre-existing candidates by asking the LLM to output a permutation of all candidates in a single call. For N exceeding the context window, a sliding-window strategy progressively reranks overlapping windows from the tail back to the head, merging the partial permutations into a final order.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [Empirical validation](#empirical-validation)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local lr = require("listwise_rank")
return lr.run(ctx)
```

## Theoretical foundations {#theoretical-foundations}

Resolves the calibration problem by reformulating ranking as
permutation generation rather than absolute scoring; the LLM never
commits to a numeric value, only to an order.

## Comparison with related packages {#comparison-with-related-packages}

- Pointwise scoring asks the LLM for an absolute score per candidate.
  The LLM's number-generation prior anchors output to the middle of
  the scale (typically 5-8), compressing variance and making any
  fixed threshold either kill nothing or kill everything. This is the
  "calibration problem" of LLM-as-Judge.
- Listwise asks the LLM for an ordering. Only the relative order is
  asked, so calibration is moot. Empirically dominates pointwise on
  TREC-DL and BEIR.

## Empirical validation {#empirical-validation}

- GPT-4 with RankGPT achieves SOTA zero-shot reranking on
  TREC-DL19/20.
- Outperforms supervised baselines (monoT5-3B) and pointwise LLM
  baselines on BEIR.
- Knowledge is distillable into smaller open-source models
  (RankZephyr, RankVicuna) that retain most of the effectiveness.

## References {#references}

- Sun, W. et al. (2023). "Is ChatGPT Good at Search? Investigating
  Large Language Models as Re-Ranking Agents". EMNLP 2023.
  https://arxiv.org/abs/2304.09542
- Ma, X. et al. (2023). "Zero-Shot Listwise Document Reranking with a
  Large Language Model". https://arxiv.org/abs/2305.02156
- Pradeep, R. et al. (2023). "RankZephyr: Effective and Robust
  Zero-Shot Listwise Reranking is a Breeze!".
  https://arxiv.org/abs/2312.02724
ctx.gen_tokens: max tokens for the ranking response (default 400)

## Result {#result}

Returns `listwise_ranked` shape:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Top-ranked text |
| `best_index` | number | — | Top-ranked original index (1-based) |
| `killed` | array of shape { index: number, rank: number, text: string } | — | Eliminated candidates |
| `n_candidates` | number | — |  |
| `ranked` | array of shape { index: number, rank: number, text: string } | — | Full ranking |
| `top_k` | array of shape { index: number, rank: number, text: string } | — | Top-k subset |
| `total_llm_calls` | number | — |  |
