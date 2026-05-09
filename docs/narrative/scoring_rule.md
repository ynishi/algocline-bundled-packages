---
name: scoring_rule
version: 0.1.0
category: evaluation
description: "Proper Scoring Rules — Brier, logarithmic, spherical scores + ECE calibration measurement for evaluating agent prediction quality. Audits whether agent confidence matches actual accuracy (Brier 1950, Gneiting-Raftery JASA 2007)."
source: scoring_rule/init.lua
generated: gen_docs (V0)
---

# scoring_rule(ScoringRule) — proper scoring rules for calibration measurement

> Pure-computation utility for evaluating the calibration of probabilistic predictions. A scoring rule `S(p, y)` is *proper* if reporting one's true belief maximizes expected score, and *strictly proper* if the maximum is unique.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local sr = require("scoring_rule")
sr.brier(0.8, 1)           -- => -0.04
sr.log_score(0.8, 1)       -- => -0.2231...
local cal = sr.calibration(predictions, outcomes, { bins = 10 })
```

## Theoretical foundations {#theoretical-foundations}

Properness (Savage 1971):

```math
S is proper  ⟺  ∀q: E_{Y~q}[S(q, Y)] ≥ E_{Y~q}[S(p, Y)] ∀p
Strictly proper: equality only when p = q
```

Provided rules (all strictly proper):

```math
Brier:        S(p, y) = -(p - y)²
Logarithmic:  S(p, y) = y·ln(p) + (1-y)·ln(1-p)
Spherical:    S(p, y) = [p·y + (1-p)·(1-y)] / √(p² + (1-p)²)
```

Proper scoring rules are the mathematically correct way to evaluate
whether an agent's confidence matches its actual accuracy. An agent
that says "80% sure" should be right ~80% of the time.

- `evaluate` scores a series of agent predictions against outcomes;
  poorly calibrated agents are identified quantitatively.
- `calibration` computes Expected Calibration Error with binned
  analysis and flags systematic over/under confidence.
- `compare` ranks multiple agents by calibration quality.
- Rule selection: Brier is robust; log score is more sensitive to
  extreme miscalibration; spherical has less extreme penalties than
  log.

Composes with `mwu` (calibration scores as loss input for weight
learning), `condorcet` (well-calibrated `p > 0.5` validates the Jury
Theorem), and `eval_guard` (calibration as evaluation quality
metric).

## References {#references}

- Brier, G. W. (1950). "Verification of forecasts expressed in
  terms of probability". Monthly Weather Review 78(1), pp.1-3.
- Savage, L. J. (1971). "Elicitation of personal probabilities and
  expectations". JASA 66(336), pp.783-801.
- Gneiting, T., Raftery, A. E. (2007). "Strictly Proper Scoring
  Rules, Prediction, and Estimation". JASA 102(477), pp.359-378.
- Naeini, M. P., Cooper, G. F., Hauskrecht, M. (2015). "Obtaining
  Well Calibrated Probabilities Using Bayesian Binning into
  Quantiles". AAAI 2015.
