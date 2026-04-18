---
name: setwise_rank
version: 0.1.0
category: selection
result_shape: "shape { best: string, best_index: number, killed: array of shape { index: number, rank: number, text: string }, n_candidates: number, ranked: array of shape { index: number, rank: number, text: string }, set_size: number, top_k: array of shape { index: number, rank: number, text: string }, total_llm_calls: number }"
description: "Setwise tournament reranking — LLM picks the best from small sets and winners advance. Mid-cost/mid-accuracy sweet spot between listwise and pairwise. Resolves calibration issue."
source: setwise_rank/init.lua
generated: gen_docs (V0)
---

# setwise_rank — Setwise Tournament Reranking

> Ranks N candidates by repeatedly asking the LLM "which is the best among these k items?" and advancing winners through tournament rounds. Each comparison spans a SET (size k) rather than a pair, dramatically reducing LLM calls vs pairwise while keeping the LLM task simpler than listwise (it only picks ONE best, not a full permutation).

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.candidates` | array of string | **required** | Candidate texts to rank (>= 2) |
| `ctx.gen_tokens` | number | optional | Max tokens per pick response (default: 20) |
| `ctx.set_size` | number | optional | Tournament group size (default: 4) |
| `ctx.task` | string | **required** | Ranking criterion |
| `ctx.top_k` | number | optional | How many to keep (default: N = full ranked list) |
