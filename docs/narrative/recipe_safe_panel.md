---
name: recipe_safe_panel
version: 0.1.0
category: recipe
result_shape: safe_paneled
description: "Verified safe majority-vote panel — Condorcet-sized, Anti-Jury gated, inverse-U monitored, confidence-calibrated. Composes condorcet + sc + inverse_u + calibrate with known failure mode awareness."
source: recipe_safe_panel/init.lua
generated: gen_docs (V0)
---

# recipe_safe_panel — Verified safe majority-vote panel

> Recipe package: composes condorcet, sc, inverse_u, and calibrate into a safety-gated panel vote. The recipe ensures that majority voting is only applied when the mathematical preconditions are met, and provides early warnings when adding more agents would degrade rather than improve accuracy.
