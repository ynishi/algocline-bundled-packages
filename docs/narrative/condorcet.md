---
name: condorcet
version: 0.1.0
category: aggregation
description: "Condorcet Jury Theorem probability and Anti-Jury detection."
source: condorcet/init.lua
generated: gen_docs (V0)
---

# condorcet(Condorcet) — Condorcet Jury Theorem probability calculator

> Pure-computation utility for majority-vote probability under independent voters. Detects Anti-Jury conditions (p < 0.5), estimates the required group size for a target accuracy, and measures inter-agent correlation to verify the independence assumption.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local condorcet = require("condorcet")
condorcet.prob_majority(5, 0.7)  -- => ~0.837
condorcet.is_anti_jury(0.4)      -- => true
```

## Theoretical foundations {#theoretical-foundations}

Core formula:

```math
P(Maj_n) = SUM_{k=ceil(n/2)}^{n} C(n,k) * p^k * (1-p)^{n-k}
```

Jury Theorem: under Uniform Independence (UI) and Uniform Competence
`p > 0.5` (UC), `P(Maj_n) → 1` as `n → ∞`. Anti-Jury: if `p < 0.5`,
`P(Maj_n) → 0` as `n → ∞`, meaning adding more voters makes the group
worse.

The Jury Theorem is the mathematical foundation for why multi-agent
voting (`sc`, `panel`, `moa`) can outperform single agents. It also
explains when it fails:

- Panel sizing: `optimal_n` computes the minimum number of agents
  needed to reach a target accuracy (e.g. 95%).
- Anti-Jury detection: `is_anti_jury` catches the dangerous case where
  agents are worse than random (`p < 0.5`); Self-Consistency and
  majority vote then degrade with more agents (see `inverse_u`).
- Independence verification: `correlation` measures pairwise Pearson
  correlation between agent outputs; high correlation violates UI and
  weakens the theorem's guarantee.
- Composable with `sc`, `panel`, `moa`, `pbft` as the theoretical
  justification for majority-vote aggregation.

## References {#references}

- Condorcet, M. (1785). "Essai sur l'application de l'analyse à la
  probabilité des décisions rendues à la pluralité des voix".
- Dietrich, F., List, C. (2008). "Jury Theorems". Stanford
  Encyclopedia of Philosophy.
