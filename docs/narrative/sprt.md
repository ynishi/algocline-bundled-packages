---
name: sprt
version: 0.1.0
category: validation
description: "Wald Sequential Probability Ratio Test — anytime 2-hypothesis stopping rule for Bernoulli streams with (α, β) error guarantees and Wald–Wolfowitz optimal E[N]. Complements cs_pruner (multi-arm anytime-valid elimination) and f_race (Friedman rank elimination)."
source: sprt/init.lua
generated: gen_docs (V0)
---

# sprt — Wald Sequential Probability Ratio Test (SPRT) for Bernoulli streams

> Given a Bernoulli stream X₁, X₂, … with unknown parameter p, SPRT decides between H0: p = p0 and H1: p = p1 (with p0 < p1) while observing trials one at a time. Maintains the running log-likelihood ratio
