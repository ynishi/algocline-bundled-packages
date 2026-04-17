---
name: lineage
version: 0.1.0
category: governance
description: "Pipeline-spanning claim lineage tracking — extracts claims per step, traces inter-step dependencies, detects conflicts and ungrounded claims. Generalizes the lineage graph governance layer from 'From Spark to Fire' (Xie et al., AAMAS 2026). Defense rate improvement: 0.32 → 0.89."
source: lineage/init.lua
generated: gen_docs (V0)
---

# lineage — Pipeline-spanning claim lineage tracking

> Tracks the provenance of claims across multi-step pipelines. Extracts atomic claims from each step's output, traces inter-step dependencies (which claim in step N derived from which claim in step N-1), and detects conflicts and ungrounded claims in the final output.
