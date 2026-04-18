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
- [Result](#result)

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
