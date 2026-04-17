---
name: falsify
version: 0.1.0
category: exploration
description: "Sequential Falsification — Popper-style hypothesis exploration via active refutation, pruning, and successor derivation. Expands search space through refutation-driven insight."
source: falsify/init.lua
generated: gen_docs (V0)
---

# falsify — Sequential Falsification for Hypothesis Exploration

> Explores hypothesis space via Popper's falsificationism: generate hypotheses, attempt to refute each one, prune the refuted, derive new hypotheses from the refutation insights. Unlike verify_first (checks consistency) or cove (verification chain), falsify actively ATTACKS hypotheses and uses refutation failures as evidence of robustness, while refutation successes drive the generation of improved successor hypotheses.
