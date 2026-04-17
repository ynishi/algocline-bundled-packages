---
name: mbr_select
version: 0.1.0
category: selection
description: "Minimum Bayes Risk selection — picks the candidate with highest expected agreement across all others. Bayes-optimal selection without bracket luck or position bias."
source: mbr_select/init.lua
generated: gen_docs (V0)
---

# mbr_select — Minimum Bayes Risk Selection

> Selects the candidate that minimizes expected loss across all other candidates. Instead of picking "the best" directly (which requires an absolute quality oracle), MBR picks the candidate most agreed-upon by all others — the one with minimum expected risk.
