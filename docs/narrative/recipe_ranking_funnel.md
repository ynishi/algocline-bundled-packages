---
name: recipe_ranking_funnel
version: 0.1.0
category: recipe
result_shape: funnel_ranked
description: "Verified 3-stage ranking funnel — listwise screening, multi-axis scoring, pairwise final rank. -87% calls vs naive pairwise on N=8 (verified). Encodes known failure modes as caveats."
source: recipe_ranking_funnel/init.lua
generated: gen_docs (V0)
---

# recipe_ranking_funnel — Verified 3-stage ranking funnel

> Recipe package: composes listwise_rank and pairwise_rank into a cost-efficient funnel for ranking large candidate sets (N ≥ 20). Applies the information retrieval classic pattern:   Recall (cheap) → Precision (medium) → Final Rank (expensive)

## Contents

- [Result](#result)

## Result {#result}

Returns `funnel_ranked` shape:

| key | type | optional | description |
|---|---|---|---|
| `best` | string | — | Top-ranked text |
| `best_index` | number | — | Top-ranked original index (1-based) |
| `bypass_reason` | string | optional | Reason for bypass (nil when not bypassed) |
| `funnel_bypassed` | boolean | — | True when N < 6 bypasses funnel stages |
| `funnel_shape` | array of number | — | Candidate counts per stage [N, s1_out, s2_out] |
| `naive_baseline_calls` | number | — | Hypothetical full-pairwise call count |
| `naive_baseline_kind` | string | — | Baseline method identifier |
| `ranking` | array of shape { original_index: number, pairwise_score: number, rank: number, text: string } | — | Final ranking |
| `savings_percent` | number | optional | LLM call savings vs baseline (nil on bypass) |
| `stages` | array of discriminated by "name" | — | Per-stage detail (discriminated by name) |
| `total_llm_calls` | number | — |  |
| `warnings` | array of shape { code: string, data: table, message: string, severity: one_of("warn", "critical") } | — | Diagnostic warnings |
