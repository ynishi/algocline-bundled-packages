---
name: ensemble_div
version: 0.1.0
category: aggregation
description: "Krogh-Vedelsby ambiguity decomposition for ensemble diversity measurement."
source: ensemble_div/init.lua
generated: gen_docs (V0)
---

# ensemble_div(EnsembleDiv) — Krogh-Vedelsby ambiguity decomposition

> Pure-computation utility for ensemble diversity measurement that implements the fundamental identity `E = E_bar - A_bar`. The identity holds without any independence assumption and for arbitrary weight distributions; it is exact, not an approximation.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local ed = require("ensemble_div")
local r = ed.decompose({0.8, 0.6, 0.9}, 1.0)
-- r.E, r.E_bar, r.A_bar, r.identity_holds
```

## Theoretical foundations {#theoretical-foundations}

Where:

```math
E     = ensemble squared error = (V - t)²
E_bar = weighted average individual error = Σ w_a · (V^a - t)²
A_bar = ambiguity (diversity) = Σ w_a · (V^a - V)²
```

Key insight: `A_bar > 0 ⟹ E < E_bar` (the ensemble always beats the
weighted average of individuals when there is any disagreement).

The decomposition answers the fundamental multi-agent question "does
adding another agent actually help?":

- Diversity monitoring: `A_bar` measures how much agents disagree.
  If `A_bar ≈ 0`, agents are redundant. Diversity is the only
  mechanism by which ensembles reduce error.
- Ensemble health: `decompose` verifies the identity in real time,
  providing a live diagnostic of ensemble quality.
- Weight optimization: non-uniform weights (e.g. from `mwu` or `ucb`)
  are fully supported. The identity holds for arbitrary weights.
- Composable with `panel`, `moa`, `sc` as a diagnostic layer.
- Connects to `condorcet` (independence assumption) and `inverse_u`
  (diminishing returns): low diversity often co-occurs with high
  correlation and inverse-U scaling.

## References {#references}

- Krogh, A., Vedelsby, J. (1995). "Neural Network Ensembles, Cross
  Validation, and Active Learning". NeurIPS 7, pp.231-238.
- Hong, L., Page, S. E. (2004). "Groups of diverse problem solvers
  can outperform groups of high-ability problem solvers". PNAS
  101(46), pp.16385-16389.
