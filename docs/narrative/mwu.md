---
name: mwu
version: 0.1.0
category: selection
description: "Multiplicative Weights Update — adversarial online agent weight learning with O(√(T ln N)) regret bound. Learns optimal agent mixture weights over time without stochastic assumptions (Littlestone-Warmuth 1994, Freund-Schapire 1997)."
source: mwu/init.lua
generated: gen_docs (V0)
---

# mwu — Multiplicative Weights Update for adversarial online learning

> Maintains a weight distribution over N agents (experts/arms) and updates weights multiplicatively based on observed losses. Provides optimal O(√(T ln N)) regret bound against ANY adversarial loss sequence — no stochastic assumption required.
