---
name: anti_cascade
version: 0.1.0
category: governance
description: "Pipeline error cascade detection — independently re-derives from original inputs at each step and compares with pipeline output to detect error amplification. Generalizes Cascade Amplification countermeasure from 'From Spark to Fire' (Xie et al., AAMAS 2026). Addresses MAST failure modes F3/F9."
source: anti_cascade/init.lua
generated: gen_docs (V0)
---

# anti_cascade — Pipeline error cascade amplification detection

> Detects when small errors compound through multi-step pipelines by independently re-deriving conclusions from original inputs at each checkpoint, then comparing with the pipeline's accumulated output. Flags steps where drift exceeds threshold.
