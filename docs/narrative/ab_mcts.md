---
name: ab_mcts
version: 0.1.0
category: reasoning
description: "Adaptive Branching MCTS — Thompson Sampling with dynamic wider/deeper decisions. GEN node mechanism for principled branching. Consistently outperforms standard MCTS and repeated sampling."
source: ab_mcts/init.lua
generated: gen_docs (V0)
---

# ab_mcts — Adaptive Branching Monte Carlo Tree Search

> Extends standard MCTS by dynamically deciding at each node whether to explore wider (generate new candidates) or deeper (refine existing ones). Uses Thompson Sampling with Beta posteriors instead of UCB1, enabling principled exploration-exploitation balance that adapts to problem structure.
