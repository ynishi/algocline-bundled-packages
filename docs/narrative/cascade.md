---
name: cascade
version: 0.1.0
category: routing
description: "Multi-level difficulty routing — escalate from fast to deep only when confidence is low"
source: cascade/init.lua
generated: gen_docs (V0)
---

# cascade — Multi-level difficulty routing with confidence gating

> Routes problems through escalating complexity levels. Starts with the simplest (cheapest) approach; if confidence is below threshold, escalates to a more sophisticated strategy. Minimizes compute for easy problems while ensuring quality for hard ones.
