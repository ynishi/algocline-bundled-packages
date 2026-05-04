---
name: solve_verify_split
version: 0.1.0
category: orchestration
description: "Compute-optimal split between solution generation (SC) and generative verification (GenRM) under a fixed inference budget. Implements Singhi et al. (arXiv:2504.01005, COLM 2025) §3.1 cost model C(S,V) = S·(1+λV) and §5.2 power-law allocator S_opt ∝ C^a, V_opt ∝ C^b as five direct-args entries: cost, score_split, optimal_split, sc_pure, compare_paths. Pure Computation — no alc.llm calls; caller drives test-time inference with sc / step_verify / cove. Fills gap not covered by compute_alloc (paradigm choice) or gumbel_search/ab_mcts (search depth-vs-width): intra-paradigm S↔V split."
source: solve_verify_split/init.lua
generated: gen_docs (V0)
---

# solve_verify_split — Compute-optimal split between solution

> generation (Self-Consistency) and generative verification (GenRM) under a fixed inference compute budget. Pure Computation pkg.
