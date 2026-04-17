---
name: eval_guard
version: 0.1.0
category: validation
description: "Evaluation safety gates for multi-agent systems — self-critique guard (N2, Huang ICLR 2024), baseline enforcement (N3, Wang-Kapoor 2024), contamination shield (N4, Zhu EMNLP 2024). Pre-flight checks before trusting any multi-agent evaluation result."
source: eval_guard/init.lua
generated: gen_docs (V0)
---

# eval_guard — Evaluation safety gates (N2 + N3 + N4 Red Lines)

> Pure-computation gate checks for evaluation safety in multi-agent systems. Each gate returns (passed, reason) and can be used independently or combined via check_all().
