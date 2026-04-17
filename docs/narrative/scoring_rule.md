---
name: scoring_rule
version: 0.1.0
category: evaluation
description: "Proper Scoring Rules — Brier, logarithmic, spherical scores + ECE calibration measurement for evaluating agent prediction quality. Audits whether agent confidence matches actual accuracy (Brier 1950, Gneiting-Raftery JASA 2007)."
source: scoring_rule/init.lua
generated: gen_docs (V0)
---

# scoring_rule — Proper Scoring Rules for calibration measurement

> Pure-computation utility for evaluating the calibration of probabilistic predictions. A scoring rule S(p, y) is "proper" if reporting one's true belief maximizes expected score, and "strictly proper" if this maximum is unique.
