---
name: cost_pareto
version: 0.1.0
category: selection
description: "Multi-objective Pareto dominance, frontier extraction, and layered ranking."
source: cost_pareto/init.lua
generated: gen_docs (V0)
---

# cost_pareto(CostPareto) — multi-objective Pareto dominance computation

> Pure-computation utility for comparing candidates on multiple objectives (accuracy, cost, diversity, latency, etc.) via Pareto dominance and frontier extraction. The convention is that all objectives are higher-is-better; for cost, pass the negative or inverse (e.g. `-cost` or `1/cost`).

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)

## Usage {#usage}

```lua
local cp = require("cost_pareto")
local a = {accuracy = 0.93, neg_cost = -2.45}
local b = {accuracy = 0.88, neg_cost = -134.50}
cp.dominates(a, b) -- => true (a dominates b)
```

## Theoretical foundations {#theoretical-foundations}

Pareto optimality (Pareto, 1896): candidate A dominates candidate B
iff A is at least as good as B on all objectives and strictly better
on at least one. The Pareto frontier is the set of non-dominated
candidates. Multi-agent strategies often improve accuracy at large
cost increases; Pareto analysis prevents chasing marginal accuracy
gains with disproportionate resource expenditure. The Princeton "AI
Agents That Matter" paper reports a HumanEval warming baseline
($2.45 / 93.2%) Pareto-dominating LATS ($134.50 / 88.0%) and
Reflexion ($3.90 / 87.8%).

The entries are designed for:

- `frontier` — extract non-dominated configurations for deployment.
- `is_dominated` — baseline gate; reject complex strategies dominated
  by a simple baseline regardless of absolute accuracy.
- `layers` — assign candidates to Pareto layers (layer 0 = frontier,
  layer 1 = next frontier, etc.) for tournament-style elimination.

Composes with `eval_guard` (baseline gate), `inverse_u` (more agents
at declining accuracy = dominated), and `mwu` (weight allocation
should favor Pareto-optimal agents).

## References {#references}

- Pareto, V. (1896). "Cours d'économie politique".
- Kapoor, S., Stroebl, B., Siegel, Z., Nadgir, N., Narayanan, A.
  (2024). "AI Agents That Matter". https://arxiv.org/abs/2407.01502
