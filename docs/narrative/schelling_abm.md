---
name: schelling_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { density: number, grid_size: number, steps: number, threshold: number, type_ratio: number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { converged_ci: shape { lower: number, upper: number }, converged_count: number, converged_rate: number, final_segregation_mean: number, final_segregation_median: number, final_segregation_p25: number, final_segregation_p75: number, final_segregation_std: number, high_segregation_ci: shape { lower: number, upper: number }, high_segregation_count: number, high_segregation_rate: number, runs: number, segregation_increase_mean: number, segregation_increase_median: number, segregation_increase_p25: number, segregation_increase_p75: number, segregation_increase_std: number, steps_to_converge_mean: number, steps_to_converge_median: number, steps_to_converge_p25: number, steps_to_converge_p75: number, steps_to_converge_std: number, unhappy_fraction_mean: number, unhappy_fraction_median: number, unhappy_fraction_p25: number, unhappy_fraction_p75: number, unhappy_fraction_std: number } }"
description: "Schelling Segregation model — agents on a 2D grid relocate when local same-type fraction falls below tolerance threshold. Mild preferences produce strong emergent segregation."
source: schelling_abm/init.lua
generated: gen_docs (V0)
---

# schelling_abm — Schelling Segregation Model

> Agents of two types on a 2D grid. Each agent has a tolerance threshold: if the fraction of same-type neighbors is below threshold, the agent moves to a random empty cell.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.density` | number | optional |  |
| `ctx.grid_size` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.steps` | number | optional |  |
| `ctx.task` | string | optional |  |
| `ctx.threshold` | number | optional |  |
| `ctx.type_ratio` | number | optional |  |
