---
name: kemeny
version: 0.1.0
category: aggregation
description: "Kemeny-Young optimal rank aggregation minimizing total Kendall tau distance."
source: kemeny/init.lua
generated: gen_docs (V0)
---

# kemeny(Kemeny) — Kemeny-Young optimal rank aggregation

> Aggregates multiple rankings (total orders) into a single consensus ranking that minimizes total Kendall tau distance to the inputs. The Kemeny rule is the unique aggregation method satisfying Condorcet consistency + neutrality + consistency (Young-Levenglick 1978). Also exposes Borda count, Condorcet winner detection, and Kendall tau distance as standalone helpers.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local kemeny = require("kemeny")
local r = kemeny.aggregate(rankings)
-- r.ranking, r.total_distance, r.method
```

## Theoretical foundations {#theoretical-foundations}

```math
σ* = argmin_{σ} Σ_{k=1}^{N} d_KT(σ, σ_k)
```

where `d_KT` is the Kendall tau distance (pairwise disagreements).
Computational complexity is NP-hard (Bartholdi, Tovey, Trick 1989):

- `m ≤ 8` candidates: exact via full enumeration (`m! ≤ 40320`).
- `m > 8`: Borda count approximation (`O(N·m)`, 2-approximation).

When multiple agents produce rankings (ordering solution candidates,
prioritizing hypotheses, sorting search results), Kemeny-Young is the
axiomatically optimal way to merge them. Composable with
`listwise_rank`, `pairwise_rank`, `setwise_rank` for LLM-generated
rankings and with `scoring_rule` for evaluating ranking quality.

## References {#references}

- Kemeny, J. G. (1959). "Mathematics without Numbers". Daedalus
  88(4), pp.577-591.
- Young, H. P., Levenglick, A. (1978). "A Consistent Extension of
  Condorcet's Election Principle". SIAM J. Applied Math 35(2),
  pp.285-300.
- Bartholdi, J., Tovey, C., Trick, M. (1989). "Voting schemes for
  which it can be difficult to tell who won the election". Social
  Choice and Welfare 6, pp.157-165.
- de Borda, J.-C. (1781). Borda count.
- Young, H. P. (1974). Axiomatic characterization of Borda count.
