---
name: boids_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { alignment_weight: number, cohesion_weight: number, max_force: number, max_speed: number, n_boids: number, perception_radius: number, separation_weight: number, steps: number, world_size: number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { alignment_score_mean: number, alignment_score_median: number, alignment_score_p25: number, alignment_score_p75: number, alignment_score_std: number, avg_nearest_distance_mean: number, avg_nearest_distance_median: number, avg_nearest_distance_p25: number, avg_nearest_distance_p75: number, avg_nearest_distance_std: number, clusters_mean: number, clusters_median: number, clusters_p25: number, clusters_p75: number, clusters_std: number, cohesive_flock_ci: shape { lower: number, upper: number }, cohesive_flock_count: number, cohesive_flock_rate: number, runs: number, scattered_ci: shape { lower: number, upper: number }, scattered_count: number, scattered_rate: number } }"
description: "Boids flocking model — separation, alignment, cohesion produce emergent flocking behavior. Tunable weights for Hybrid LLM parameter optimization. Based on Reynolds (1987)."
source: boids_abm/init.lua
generated: gen_docs (V0)
---

# boids_abm — Boids Flocking Model

> N agents (boids) in 2D continuous space follow three simple rules:   1. Separation: steer away from nearby boids to avoid crowding   2. Alignment: steer towards the average heading of nearby boids   3. Cohesion: steer towards the average position of nearby boids

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alignment_weight` | number | optional | Alignment rule weight (default 1.0) |
| `ctx.cohesion_weight` | number | optional | Cohesion rule weight (default 1.0) |
| `ctx.max_force` | number | optional | Per-step steering force cap (default 0.3) |
| `ctx.max_speed` | number | optional | Per-step velocity cap (default 4) |
| `ctx.n_boids` | number | optional | Number of boids (default 50) |
| `ctx.perception_radius` | number | optional | Neighbor perception radius (default 50) |
| `ctx.runs` | number | optional | Monte Carlo runs (default 100) |
| `ctx.separation_weight` | number | optional | Separation rule weight (default 1.5) |
| `ctx.steps` | number | optional | Simulation steps per run (default 100) |
| `ctx.task` | string | optional | Task description (free text) |
| `ctx.world_size` | number | optional | Square-world side length (default 300) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `params` | shape { alignment_weight: number, cohesion_weight: number, max_force: number, max_speed: number, n_boids: number, perception_radius: number, separation_weight: number, steps: number, world_size: number } | — |  |
| `sensitivity` | array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number } | — |  |
| `simulation` | shape { alignment_score_mean: number, alignment_score_median: number, alignment_score_p25: number, alignment_score_p75: number, alignment_score_std: number, avg_nearest_distance_mean: number, avg_nearest_distance_median: number, avg_nearest_distance_p25: number, avg_nearest_distance_p75: number, avg_nearest_distance_std: number, clusters_mean: number, clusters_median: number, clusters_p25: number, clusters_p75: number, clusters_std: number, cohesive_flock_ci: shape { lower: number, upper: number }, cohesive_flock_count: number, cohesive_flock_rate: number, runs: number, scattered_ci: shape { lower: number, upper: number }, scattered_count: number, scattered_rate: number } | — |  |
