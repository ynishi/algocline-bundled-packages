---
name: kemeny
version: 0.1.0
category: aggregation
description: "Kemeny-Young rank aggregation — axiomatically unique consensus ranking that minimizes total Kendall tau distance. Merges multiple agent rankings into optimal consensus with Condorcet consistency (Kemeny 1959, Young-Levenglick 1978)."
source: kemeny/init.lua
generated: gen_docs (V0)
---

# kemeny — Kemeny-Young optimal rank aggregation

> Aggregates multiple rankings (total orders) into a single consensus ranking that minimizes the total Kendall tau distance to all input rankings. The Kemeny rule is the UNIQUE aggregation method satisfying Condorcet consistency + neutrality + consistency (Young-Levenglick 1978).
