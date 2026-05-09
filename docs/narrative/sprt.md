---
name: sprt
version: 0.1.0
category: validation
description: "Wald Sequential Probability Ratio Test — anytime 2-hypothesis stopping rule for Bernoulli streams with (α, β) error guarantees and Wald–Wolfowitz optimal E[N]. Complements cs_pruner (multi-arm anytime-valid elimination) and f_race (Friedman rank elimination)."
source: sprt/init.lua
generated: gen_docs (V0)
---

# sprt(SPRT) — Wald Sequential Probability Ratio Test for Bernoulli streams

> Given a Bernoulli stream `X₁, X₂, …` with unknown parameter `p`, SPRT decides between `H0: p = p0` and `H1: p = p1` (`p0 < p1`) while observing trials one at a time. Maintains the running log-likelihood ratio and stops as soon as it crosses an upper or lower boundary using Wald's classical approximations.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)

## Usage {#usage}

```lua
local sprt = require("sprt")
local st = sprt.new({ p0 = 0.5, p1 = 0.75, alpha = 0.05, beta = 0.10 })
for _, x in ipairs(stream) do
    sprt.observe(st, x)
    if sprt.decide(st).verdict ~= "continue" then break end
end
```

## Theoretical foundations {#theoretical-foundations}

```math
λ_n = Σᵢ log(f₁(Xᵢ) / f₀(Xᵢ))
A   = log((1 - β) / α)        B = log(β / (1 - α))
```

Wald & Wolfowitz (1948) proved SPRT minimizes `E[N]` among all
tests satisfying `(α, β)` error constraints under the two boundary
hypotheses. SPRT is the right primitive for "stop as soon as
evidence is strong enough" decisions.

## Comparison with related packages {#comparison-with-related-packages}

- `cs_pruner` — N candidates × D rubric dims, kill on CS overlap.
- `f_race` — N candidates × D dims, kill on Friedman rank gap.
- `sprt` — 1 stream of Bernoulli trials, 2-hypothesis stop.

## References {#references}

- Wald, A. (1945). "Sequential Tests of Statistical Hypotheses".
  Ann. Math. Statist. 16(2), 117-186.
- Wald, A., Wolfowitz, J. (1948). "Optimum character of the
  sequential probability ratio test". Ann. Math. Statist. 19(3),
  326-339.

This is a substrate-style primitive: it does NOT call alc.llm. It only
accumulates evidence and exposes the decision boundary. Users compose
it inside a recipe (see recipe_quick_vote) or orch driver loop.
