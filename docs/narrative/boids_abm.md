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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alignment_weight` | number | optional |  |
| `ctx.cohesion_weight` | number | optional |  |
| `ctx.max_force` | number | optional |  |
| `ctx.max_speed` | number | optional |  |
| `ctx.n_boids` | number | optional |  |
| `ctx.perception_radius` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.separation_weight` | number | optional |  |
| `ctx.steps` | number | optional |  |
| `ctx.task` | string | optional |  |
| `ctx.world_size` | number | optional |  |
