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
