---
name: evogame_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { generations: number, mutation_rate: number, n_agents: number, payoff_matrix: table, rounds_per_gen: number, strategies?: array of string }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { cooperation_rate_mean: number, cooperation_rate_median: number, cooperation_rate_p25: number, cooperation_rate_p75: number, cooperation_rate_std: number, dominant_fraction_mean: number, dominant_fraction_median: number, dominant_fraction_p25: number, dominant_fraction_p75: number, dominant_fraction_std: number, n_strategies_surviving_mean: number, n_strategies_surviving_median: number, n_strategies_surviving_p25: number, n_strategies_surviving_p75: number, n_strategies_surviving_std: number, runs: number, tft_survived_ci: shape { lower: number, upper: number }, tft_survived_count: number, tft_survived_rate: number } }"
description: "Evolutionary Game Theory ABM — iterated games with selection and mutation. Prisoner's Dilemma, Hawk-Dove, or custom payoff matrices. Based on Axelrod (1984)."
source: evogame_abm/init.lua
generated: gen_docs (V0)
---

# evogame_abm(EvoGameABM) — evolutionary game theory agent-based simulation

> N strategy-bearing agents play iterated games (Prisoner's Dilemma by default). Each generation runs random pairing, payoff calculation, selection, and mutation, producing emergent cooperation/defection equilibria, cyclic dominance, and strategy-invasion dynamics.

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local evogame = require("evogame_abm")
return evogame.run(ctx)
```

## References {#references}

- Axelrod, R. (1984). "The Evolution of Cooperation". Basic Books.
- Nowak, M. A., May, R. M. (1992). "Evolutionary Games and Spatial
  Chaos". Nature 359.
- Mao, S. et al. (2025). "ALYMPICS: LLM Agents Meet Game Theory".
  COLING 2025.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.generations` | number | optional | Number of generations (default 30) |
| `ctx.mutation_rate` | number | optional | Mutation rate per offspring (default 0.05) |
| `ctx.n_agents` | number | optional | Number of agents (default 50) |
| `ctx.payoff_matrix` | table | optional | Payoff matrix (CC/CD/DC/DD → {a,b} pairs) |
| `ctx.rounds_per_gen` | number | optional | Games per generation (default 10) |
| `ctx.runs` | number | optional | Monte Carlo runs (default 100) |
| `ctx.strategies` | array of string | optional | Initial strategy distribution |
| `ctx.task` | string | optional | Task description (free text) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `params` | shape { generations: number, mutation_rate: number, n_agents: number, payoff_matrix: table, rounds_per_gen: number, strategies?: array of string } | — |  |
| `sensitivity` | array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number } | — |  |
| `simulation` | shape { cooperation_rate_mean: number, cooperation_rate_median: number, cooperation_rate_p25: number, cooperation_rate_p75: number, cooperation_rate_std: number, dominant_fraction_mean: number, dominant_fraction_median: number, dominant_fraction_p25: number, dominant_fraction_p75: number, dominant_fraction_std: number, n_strategies_surviving_mean: number, n_strategies_surviving_median: number, n_strategies_surviving_p25: number, n_strategies_surviving_p75: number, n_strategies_surviving_std: number, runs: number, tft_survived_ci: shape { lower: number, upper: number }, tft_survived_count: number, tft_survived_rate: number } | — |  |
