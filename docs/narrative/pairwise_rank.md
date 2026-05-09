---
name: pairwise_rank
version: 0.1.0
category: selection
result_shape: pairwise_ranked
description: "Pairwise Ranking Prompting (PRP) — pairwise LLM-as-judge comparison with bidirectional position-bias cancellation. Highest-accuracy LLM reranker on TREC-DL/BEIR. Resolves the calibration problem."
source: pairwise_rank/init.lua
generated: gen_docs (V0)
---

# pairwise_rank(PairwiseRank) — Pairwise Ranking Prompting (PRP)

> Ranks N candidates by asking the LLM "is A or B better?" for pairs and aggregating wins (Copeland-style score). PRP is the most accurate known LLM-as-judge method when the LLM is small or the task is hard, because it asks the LLM the simplest possible question (a single pairwise preference) at the cost of more LLM calls. By comparing two items at a time, PRP sidesteps both numeric calibration and list-positional reasoning.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Comparison with related packages](#comparison-with-related-packages)
- [Empirical validation](#empirical-validation)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local pr = require("pairwise_rank")
return pr.run(ctx)
```

## Algorithm {#algorithm}

- `allpair` — every unordered pair compared in both directions to
  cancel position bias. `2 · C(N,2) = N·(N-1)` LLM calls. Most
  accurate; use for `N ≤ 12`.
- `sorting` — heap-style insertion sort using pairwise comparisons.
  `O(N log N)` calls in expectation; use for larger N.

## Comparison with related packages {#comparison-with-related-packages}

- `listwise_rank` — 1 LLM call ranks everything; cheapest but limited
  by context window and can suffer list-position bias.
- `setwise_rank` — tournament with set comparisons of size `k`,
  `O(N log N)` calls; mid-cost / mid-accuracy.
- `pairwise_rank` — pure pairwise; highest accuracy when N is modest.

## Empirical validation {#empirical-validation}

- Flan-UL2 (20B params) with PRP-Allpair matches GPT-4 (~50× larger)
  on TREC-DL 2019/2020.
- Outperforms pointwise LLM rankers by >10% NDCG@10 on average across
  7 BEIR tasks.
- Outperforms blackbox ChatGPT listwise reranking by 4.2% NDCG@10.

## References {#references}

- Qin, Z. et al. (2024). "Large Language Models are Effective Text
  Rankers with Pairwise Ranking Prompting". NAACL 2024 Findings.
  https://arxiv.org/abs/2306.17563

## Result {#result}

Returns `pairwise_ranked` shape:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Top-ranked text |
| `best_index` | number | — | Top-ranked original index (1-based) |
| `both_tie_pairs` | number | — | Pairs that tied in both directions |
| `killed` | array of shape { index: number, rank: number, score: number, text: string } | — | Eliminated candidates |
| `method` | one_of("allpair", "sorting") | — | Comparison strategy |
| `n_candidates` | number | — |  |
| `position_bias_splits` | number | — | Position-bias correction splits |
| `ranked` | array of shape { index: number, rank: number, score: number, text: string } | — | Full ranking with scores |
| `score_semantics` | one_of("copeland", "rank_inverse") | — | Score interpretation |
| `top_k` | array of shape { index: number, rank: number, score: number, text: string } | — | Top-k subset |
| `total_llm_calls` | number | — |  |
