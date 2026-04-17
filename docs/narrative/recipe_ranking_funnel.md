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
