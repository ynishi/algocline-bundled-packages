---
name: bft
version: 0.1.0
category: governance
description: "Byzantine Fault Tolerance bounds — quorum thresholds and impossibility validation for multi-agent governance. Computes minimum panel sizes and fault tolerance limits (Lamport-Shostak-Pease 1982, Theorem 1: n >= 3f+1)."
source: bft/init.lua
generated: gen_docs (V0)
---

# bft — Byzantine Fault Tolerance impossibility bounds

> Pure-computation utility for BFT quorum thresholds and validation. No LLM calls; used as a governance primitive by higher-level packages (e.g. pbft, dissent, anti_cascade).
