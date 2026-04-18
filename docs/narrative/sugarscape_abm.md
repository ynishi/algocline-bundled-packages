---
name: sugarscape_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { grid_size: number, initial_wealth_range: array of number, max_sugar: number, metabolism_range: array of number, n_agents: number, regrow_rate: number, steps: number, vision_range: array of number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { gini_mean: number, gini_median: number, gini_p25: number, gini_p75: number, gini_std: number, high_inequality_ci: shape { lower: number, upper: number }, high_inequality_count: number, high_inequality_rate: number, mean_wealth_mean: number, mean_wealth_median: number, mean_wealth_p25: number, mean_wealth_p75: number, mean_wealth_std: number, population_collapsed_ci: shape { lower: number, upper: number }, population_collapsed_count: number, population_collapsed_rate: number, runs: number, survival_rate_mean: number, survival_rate_median: number, survival_rate_p25: number, survival_rate_p75: number, survival_rate_std: number } }"
description: "Sugarscape model — agents forage on a sugar landscape, emergent wealth inequality, Pareto-like distributions, and carrying capacity. Based on Epstein & Axtell (1996)."
source: sugarscape_abm/init.lua
generated: gen_docs (V0)
---

# sugarscape_abm — Sugarscape Agent-Based Model

> Agents on a 2D toroidal grid forage for sugar. Each cell has a sugar capacity and regrows at a fixed rate. Agents have metabolism (sugar consumed per step) and vision (how far they can see). Each step, an agent looks in four cardinal directions up to its vision range and moves to the nearest unoccupied cell with the most sugar. Agents die when sugar wealth reaches zero.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.grid_size` | number | optional |  |
| `ctx.initial_wealth_range` | array of number | optional |  |
| `ctx.max_sugar` | number | optional |  |
| `ctx.metabolism_range` | array of number | optional |  |
| `ctx.n_agents` | number | optional |  |
| `ctx.regrow_rate` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.steps` | number | optional |  |
| `ctx.task` | string | optional |  |
| `ctx.vision_range` | array of number | optional |  |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `params` | shape { grid_size: number, initial_wealth_range: array of number, max_sugar: number, metabolism_range: array of number, n_agents: number, regrow_rate: number, steps: number, vision_range: array of number } | — |  |
| `sensitivity` | array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number } | — |  |
| `simulation` | shape { gini_mean: number, gini_median: number, gini_p25: number, gini_p75: number, gini_std: number, high_inequality_ci: shape { lower: number, upper: number }, high_inequality_count: number, high_inequality_rate: number, mean_wealth_mean: number, mean_wealth_median: number, mean_wealth_p25: number, mean_wealth_p75: number, mean_wealth_std: number, population_collapsed_ci: shape { lower: number, upper: number }, population_collapsed_count: number, population_collapsed_rate: number, runs: number, survival_rate_mean: number, survival_rate_median: number, survival_rate_p25: number, survival_rate_p75: number, survival_rate_std: number } | — |  |
