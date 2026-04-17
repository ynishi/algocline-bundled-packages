---
name: setwise_rank
version: 0.1.0
category: selection
description: "Setwise tournament reranking — LLM picks the best from small sets and winners advance. Mid-cost/mid-accuracy sweet spot between listwise and pairwise. Resolves calibration issue."
source: setwise_rank/init.lua
generated: gen_docs (V0)
---

# setwise_rank — Setwise Tournament Reranking

> Ranks N candidates by repeatedly asking the LLM "which is the best among these k items?" and advancing winners through tournament rounds. Each comparison spans a SET (size k) rather than a pair, dramatically reducing LLM calls vs pairwise while keeping the LLM task simpler than listwise (it only picks ONE best, not a full permutation).
