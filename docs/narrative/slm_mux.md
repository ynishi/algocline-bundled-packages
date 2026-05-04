---
name: slm_mux
version: 0.1.0
category: selection
result_shape: slm_muxed
description: "Complementarity-driven K-subset selection over a pool of small language models. Implements Wang et al. (arXiv:2510.05077, ICLR 2026 Poster) §3.1 Algorithm 1 (confidence-based inference selection) and §3.2 𝒪(S) = UnionAcc(S) − λ · Contradiction(S) with exhaustive search. Pure Computation pkg — no alc.llm calls; caller drives test-time inference. Fills selection-axis gap not covered by router_*/cascade (single-best routing) or ab_select/mbr_select (single-best selection): N→K subset complementarity over a pre-computed calibration tensor."
source: slm_mux/init.lua
generated: gen_docs (V0)
---

# slm_mux — Pure Computation pkg for orchestrating Small Language

> Models via complementarity-driven K-subset selection.
