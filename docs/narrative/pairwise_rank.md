---
name: pairwise_rank
version: 0.1.0
category: selection
result_shape: pairwise_ranked
description: "Pairwise Ranking Prompting (PRP) — pairwise LLM-as-judge comparison with bidirectional position-bias cancellation. Highest-accuracy LLM reranker on TREC-DL/BEIR. Resolves the calibration problem."
source: pairwise_rank/init.lua
generated: gen_docs (V0)
---

# pairwise_rank — Pairwise Ranking Prompting (PRP)

> Ranks N candidates by asking the LLM "is A or B better?" for pairs and aggregating the wins (Copeland-style score). PRP is the most accurate known LLM-as-judge method when the LLM is small or the task is hard, because it asks the LLM the simplest possible question (a single pairwise preference) at the cost of more LLM calls.

## Contents

- [Result](#result)

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
