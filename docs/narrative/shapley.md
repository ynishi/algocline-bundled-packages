---
name: shapley
version: 0.1.0
category: attribution
description: "Shapley Value — axiomatically unique agent contribution attribution via exact O(2^n) computation or Monte Carlo permutation sampling. Identifies essential, redundant, and harmful agents in multi-agent ensembles (Shapley 1953, Ghorbani-Zou AISTATS 2019)."
source: shapley/init.lua
generated: gen_docs (V0)
---

# shapley(Shapley) — Shapley value computation for agent contribution attribution

> Pure-computation utility for attributing individual agent contributions within a coalition (ensemble or swarm). Implements both exact computation and Monte Carlo permutation sampling.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local shapley = require("shapley")

-- Exact computation (n <= 12)
local r = shapley.exact({"a","b","c"}, v_fn)

-- Monte Carlo approximation
local r = shapley.montecarlo({"a","b","c"}, v_fn, {samples=1000})

-- Helper: build v_fn from agent outputs + ground truth
local v_fn = shapley.accuracy_coalition(outputs, truth)
```

## Theoretical foundations {#theoretical-foundations}

The Shapley value is the unique allocation satisfying four axioms:

1. Efficiency: `Σ φ_i = v(N) - v(∅)`.
2. Symmetry: `i, j` interchangeable ⟹ `φ_i = φ_j`.
3. Dummy: `i` contributes nothing ⟹ `φ_i = 0`.
4. Additivity: `φ_i(v+w) = φ_i(v) + φ_i(w)`.

```math
φ_i(v) = Σ_{S ⊆ N\{i}} [|S|! · (n-|S|-1)! / n!] · [v(S∪{i}) - v(S)]
```

Monte Carlo approximation (Ghorbani & Zou 2019): sample random
permutations `π`, compute the marginal contribution of `i` as
`v(predecessors_of_i ∪ {i}) - v(predecessors_of_i)`. Convergence
`O(1/√M)` by CLT.

In a multi-agent swarm not all agents contribute equally; Shapley
values give a fair attribution. `exact` (n ≤ 12) uses `O(2^n)`
bitmask enumeration; `montecarlo` is `O(M·n)` with 95% CIs.
`accuracy_coalition` helper builds a coalition value function from
binary predictions plus ground truth via majority vote. Composable
with `panel`, `moa`, `sc` for post-hoc analysis.

## References {#references}

- Shapley, L. S. (1953). "A Value for n-Person Games". Contributions
  to the Theory of Games II, Annals of Mathematics Studies 28,
  pp.307-317.
- Ghorbani, A., Zou, J. (2019). "Data Shapley". AISTATS 2019.
