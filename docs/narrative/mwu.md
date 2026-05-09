---
name: mwu
version: 0.1.0
category: selection
description: "Multiplicative Weights Update with O(sqrt(T ln N)) adversarial regret bound."
source: mwu/init.lua
generated: gen_docs (V0)
---

# mwu(MWU) — Multiplicative Weights Update for adversarial online learning

> Maintains a weight distribution over N agents (experts/arms) and updates weights multiplicatively based on observed losses. Provides an optimal `O(√(T ln N))` regret bound against any adversarial loss sequence — no stochastic assumption required.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)

## Usage {#usage}

```lua
local mwu = require("mwu")

-- Stateful updater
local u = mwu.new({ n = 5, T = 100 })
u:update({ 0.3, 0.8, 0.1, 0.5, 0.2 })
local w = u:weights()

-- One-shot from loss matrix
local r = mwu.solve(loss_matrix)
```

## Theoretical foundations {#theoretical-foundations}

```math
w_i(t+1) = w_i(t) · (1 - η · ℓ_i(t))
p_i(t)   = w_i(t) / Σ_j w_j(t)
Regret_T = Σ_t p(t)·ℓ(t) - min_i Σ_t ℓ_i(t)
         ≤ (ln N)/η + η·T
```

The optimal `η = √(ln N / T)` yields `Regret_T ≤ 2√(T ln N)`. MWU is
the principled way to learn agent weights over time in an adversarial
environment where tasks can change arbitrarily between rounds.
Unlike UCB1 (`ucb`), which selects one arm, MWU outputs a full weight
distribution. Implementation notes:

- Doubling trick: when `T` is unknown in advance, restart with
  doubled epoch lengths and recalculated `η` to maintain
  `O(√(T ln N))` regret.
- Log-space computation: weights are maintained in log space to
  prevent numerical underflow when agents have extreme loss contrast
  over many rounds.

Composable with `panel` / `moa` (weight the agent mixture),
`shapley` (post-hoc attribution), and `scoring_rule` (loss from
calibration scores).

## Comparison with related packages {#comparison-with-related-packages}

- `ucb` — stochastic bandits (i.i.d. losses), selects one arm.
- `mwu` — adversarial setting (arbitrary losses), outputs a weight
  distribution.

## References {#references}

- Littlestone, N., Warmuth, M. K. (1994). "The Weighted Majority
  Algorithm". Information and Computation 108(2), pp.212-261.
- Freund, Y., Schapire, R. E. (1997). "A Decision-Theoretic
  Generalization of On-Line Learning and an Application to Boosting".
  JCSS 55(1), pp.119-139.
- Cesa-Bianchi, N., Lugosi, G. (2006). "Prediction, Learning, and
  Games". Cambridge University Press, §2.1-2.3.
