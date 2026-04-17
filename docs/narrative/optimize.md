---
name: optimize
version: 0.3.0
category: optimization
description: "Modular parameter optimization orchestrator. Composes pluggable search strategies (UCB1, OPRO, EA, greedy), evaluators (evalframe, custom, LLM judge), and stopping criteria (variance, patience, threshold). Persists history via alc.state."
source: optimize/init.lua
generated: gen_docs (V0)
---

# optimize — Modular parameter optimization orchestrator

> Explores parameter configurations for a target strategy by composing pluggable search strategies, evaluators, and stopping criteria. Persists history in alc.state for incremental optimization across sessions.
