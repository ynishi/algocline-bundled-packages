---
name: schelling_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { density: number, grid_size: number, steps: number, threshold: number, type_ratio: number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { converged_ci: shape { lower: number, upper: number }, converged_count: number, converged_rate: number, final_segregation_mean: number, final_segregation_median: number, final_segregation_p25: number, final_segregation_p75: number, final_segregation_std: number, high_segregation_ci: shape { lower: number, upper: number }, high_segregation_count: number, high_segregation_rate: number, runs: number, segregation_increase_mean: number, segregation_increase_median: number, segregation_increase_p25: number, segregation_increase_p75: number, segregation_increase_std: number, steps_to_converge_mean: number, steps_to_converge_median: number, steps_to_converge_p25: number, steps_to_converge_p75: number, steps_to_converge_std: number, unhappy_fraction_mean: number, unhappy_fraction_median: number, unhappy_fraction_p25: number, unhappy_fraction_p75: number, unhappy_fraction_std: number } }"
description: "Schelling Segregation model — agents on a 2D grid relocate when local same-type fraction falls below tolerance threshold. Mild preferences produce strong emergent segregation."
source: schelling_abm/init.lua
generated: gen_docs (V0)
---

# schelling_abm(SchellingABM) — Schelling segregation model

> Agents of two types on a 2D grid. Each agent has a tolerance threshold; if the fraction of same-type neighbors is below the threshold, the agent moves to a random empty cell. Even mild preferences (threshold ~0.3) produce strong macro-level segregation, demonstrating how micro-motives produce macro-behavior that no individual intended.

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local schelling = require("schelling_abm")
return schelling.run(ctx)
```

## References {#references}

- Schelling, T. C. (1971). "Dynamic Models of Segregation". Journal
  of Mathematical Sociology 1(2).
- Schelling, T. C. (1978). "Micromotives and Macrobehavior". Norton.

ctx.task (required): Description
ctx.grid_size?: number Side length of square grid (default 20)
ctx.threshold?: number Tolerance threshold (default 0.375)
ctx.density?: number Fraction of cells occupied (default 0.8)
ctx.type_ratio?: number Fraction of type A among agents (default 0.5)
ctx.steps?: number Max steps (default 100)
ctx.runs?: number MC runs (default 100)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.density` | number | optional | Occupancy fraction (default 0.8) |
| `ctx.grid_size` | number | optional | Square-grid side length (default 20) |
| `ctx.runs` | number | optional | Monte Carlo runs (default 100) |
| `ctx.steps` | number | optional | Max simulation steps (default 100) |
| `ctx.task` | string | optional | Task description (free text) |
| `ctx.threshold` | number | optional | Tolerance threshold (min same-type neighbor fraction, default 0.375) |
| `ctx.type_ratio` | number | optional | Fraction of type-A agents (default 0.5) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `params` | shape { density: number, grid_size: number, steps: number, threshold: number, type_ratio: number } | — |  |
| `sensitivity` | array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number } | — |  |
| `simulation` | shape { converged_ci: shape { lower: number, upper: number }, converged_count: number, converged_rate: number, final_segregation_mean: number, final_segregation_median: number, final_segregation_p25: number, final_segregation_p75: number, final_segregation_std: number, high_segregation_ci: shape { lower: number, upper: number }, high_segregation_count: number, high_segregation_rate: number, runs: number, segregation_increase_mean: number, segregation_increase_median: number, segregation_increase_p25: number, segregation_increase_p75: number, segregation_increase_std: number, steps_to_converge_mean: number, steps_to_converge_median: number, steps_to_converge_p25: number, steps_to_converge_p75: number, steps_to_converge_std: number, unhappy_fraction_mean: number, unhappy_fraction_median: number, unhappy_fraction_p25: number, unhappy_fraction_p75: number, unhappy_fraction_std: number } | — |  |
