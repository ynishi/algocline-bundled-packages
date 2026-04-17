---
name: ab_select
version: 0.1.0
category: selection
description: "Adaptive Branching Selection — multi-fidelity Thompson sampling over a fixed candidate pool. Allocates expensive evaluators only to promising candidates. Unique multi-fidelity axis vs other selection packages."
source: ab_select/init.lua
generated: gen_docs (V0)
---

# ab_select — Adaptive Branching Selection (multi-fidelity Thompson sampling)

> Selects the best candidate from a pool using staged evaluators of increasing cost. Thompson Sampling decides which candidate receives the next, more expensive evaluation, allocating expensive evaluations only to candidates whose Beta posterior suggests they are promising.
