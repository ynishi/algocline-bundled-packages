---
name: evogame_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { generations: number, mutation_rate: number, n_agents: number, payoff_matrix: table, rounds_per_gen: number, strategies?: array of string }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { cooperation_rate_mean: number, cooperation_rate_median: number, cooperation_rate_p25: number, cooperation_rate_p75: number, cooperation_rate_std: number, dominant_fraction_mean: number, dominant_fraction_median: number, dominant_fraction_p25: number, dominant_fraction_p75: number, dominant_fraction_std: number, n_strategies_surviving_mean: number, n_strategies_surviving_median: number, n_strategies_surviving_p25: number, n_strategies_surviving_p75: number, n_strategies_surviving_std: number, runs: number, tft_survived_ci: shape { lower: number, upper: number }, tft_survived_count: number, tft_survived_rate: number } }"
description: "Evolutionary Game Theory ABM — iterated games with selection and mutation. Prisoner's Dilemma, Hawk-Dove, or custom payoff matrices. Based on Axelrod (1984)."
source: evogame_abm/init.lua
generated: gen_docs (V0)
---

# evogame_abm — Evolutionary Game Theory ABM

> N agents with strategies play iterated games (Prisoner's Dilemma by default). Each generation: random pairing → payoff calculation → selection → mutation. Emergent phenomena: cooperation/defection equilibria, cyclic dominance, strategy invasion dynamics.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.generations` | number | optional |  |
| `ctx.mutation_rate` | number | optional |  |
| `ctx.n_agents` | number | optional |  |
| `ctx.payoff_matrix` | table | optional |  |
| `ctx.rounds_per_gen` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.strategies` | array of string | optional |  |
| `ctx.task` | string | optional |  |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `params` | shape { generations: number, mutation_rate: number, n_agents: number, payoff_matrix: table, rounds_per_gen: number, strategies?: array of string } | — |  |
| `sensitivity` | array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number } | — |  |
| `simulation` | shape { cooperation_rate_mean: number, cooperation_rate_median: number, cooperation_rate_p25: number, cooperation_rate_p75: number, cooperation_rate_std: number, dominant_fraction_mean: number, dominant_fraction_median: number, dominant_fraction_p25: number, dominant_fraction_p75: number, dominant_fraction_std: number, n_strategies_surviving_mean: number, n_strategies_surviving_median: number, n_strategies_surviving_p25: number, n_strategies_surviving_p75: number, n_strategies_surviving_std: number, runs: number, tft_survived_ci: shape { lower: number, upper: number }, tft_survived_count: number, tft_survived_rate: number } | — |  |
