---
name: listwise_rank
version: 0.1.0
category: selection
result_shape: listwise_ranked
description: "Zero-shot listwise reranking — RankGPT-style permutation generation in 1 LLM call. Resolves the calibration problem of pointwise scoring. Sliding window for large N."
source: listwise_rank/init.lua
generated: gen_docs (V0)
---

# listwise_rank — Zero-shot Listwise Reranking with Sliding Window

> Ranks N pre-existing candidates by asking the LLM to output a permutation of all candidates in a single call. For N exceeding the context window, a sliding-window strategy progressively reranks overlapping windows from the tail back to the head, merging the partial permutations into a final order.
