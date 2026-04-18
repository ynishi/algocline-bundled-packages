---
name: opinion_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { distribution: string, epsilon: number, n_agents: number, steps: number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { clusters_mean: number, clusters_median: number, clusters_p25: number, clusters_p75: number, clusters_std: number, consensus_ci: shape { lower: number, upper: number }, consensus_count: number, consensus_rate: number, converged_ci: shape { lower: number, upper: number }, converged_count: number, converged_rate: number, polarized_ci: shape { lower: number, upper: number }, polarized_count: number, polarized_rate: number, runs: number, variance_mean: number, variance_median: number, variance_p25: number, variance_p75: number, variance_std: number } }"
description: "Hegselmann-Krause Bounded Confidence opinion dynamics — agents update opinions by averaging nearby opinions within threshold ε. Emergent consensus, polarization, or fragmentation."
source: opinion_abm/init.lua
generated: gen_docs (V0)
---

# opinion_abm — Hegselmann-Krause Bounded Confidence Opinion Dynamics

> N agents hold continuous opinion values in [0,1]. Each step, an agent updates its opinion to the average of all agents whose opinions are within ε (bounded confidence threshold).

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.epsilon` | number | optional |  |
| `ctx.initial_distribution` | string | optional |  |
| `ctx.n_agents` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.steps` | number | optional |  |
| `ctx.task` | string | optional |  |
