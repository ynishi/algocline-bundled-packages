---
name: counterfactual_verify
version: 0.1.0
category: validation
description: "Counterfactual faithfulness verification — tests whether reasoning causally depends on inputs by simulating condition changes. Detects pattern-matching and unfaithful CoT."
source: counterfactual_verify/init.lua
generated: gen_docs (V0)
---

# counterfactual_verify — Causal faithfulness verification via counterfactual simulation

> Tests whether a reasoning chain is genuinely faithful to its inputs by checking: "If the input changed, would the conclusion change accordingly?" Unlike cove (factual correctness) or verify_first (reverse verification), this detects pattern-matching and memorization by testing causal dependence between premises and conclusions.
