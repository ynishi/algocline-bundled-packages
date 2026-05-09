---
name: inverse_u
version: 0.1.0
category: validation
description: "Detect inverse-U accuracy scaling when adding more agents (safety gate)."
source: inverse_u/init.lua
generated: gen_docs (V0)
---

# inverse_u(InverseU) — inverse-U scaling detection for multi-agent systems

> Pure-computation utility for detecting non-monotonic accuracy scaling when increasing the number of LLM agents or calls.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local iu = require("inverse_u")
local r = iu.detect({0.70, 0.75, 0.73, 0.71})
-- r.peak_idx=2, r.is_declining=true, r.consecutive_drops=2
```

## Theoretical foundations {#theoretical-foundations}

Chen et al.'s Theorem 2: for a synthetic dataset `D_{α,p1,p2}`, if
`p1 + p2 > 1` and `α < 1 - 1/t`, then Vote / Filter-Vote accuracy is
inverse-U shaped in `N` (the number of agents). This contradicts the
naive assumption that more agents always improves accuracy. The
mechanism: on hard queries (accuracy `< 0.5`) majority vote amplifies
the wrong answer as `N` grows.

The package is a critical safety gate for any multi-agent system that
scales by adding agents (`sc`, `panel`, `moa`, `pbft`):

- `detect` analyzes an accuracy-by-`N` series to identify whether
  performance has peaked and is declining; run after each round of
  agent addition.
- `should_stop` returns a binary go/no-go: if 2+ consecutive accuracy
  drops are observed, stop adding agents immediately.
- `chen_condition` checks whether Theorem 2's formal conditions hold
  for a given task distribution (easy/hard split, per-subset
  accuracy).

Composes with `condorcet` (Anti-Jury is the `p < 0.5` case),
`ensemble_div` (low diversity + inverse-U co-occur), and
`cost_pareto` (more agents at declining accuracy = Pareto-dominated).
Used as gate G1 in agent-swarm orchestration: before spawning more
agents, check whether the inverse-U has already been reached.

## References {#references}

- Chen, L. et al. (2024). "Are More LM Calls All You Need? Scaling
  Laws in Multi-Agent Systems". NeurIPS 2024.
  https://arxiv.org/abs/2403.02419
