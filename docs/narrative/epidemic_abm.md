---
name: epidemic_abm
version: 0.1.0
category: simulation
result_shape: "shape { params: shape { beta: number, contacts_per_step: number, gamma: number, initial_infected: number, n_agents: number, steps: number }, sensitivity: array of shape { base_value: number, delta: number, factor: number, high_value: number, low_value: number, param: string, score_at_high: number, score_at_low: number }, simulation: shape { attack_rate_mean: number, attack_rate_median: number, attack_rate_p25: number, attack_rate_p75: number, attack_rate_std: number, epidemic_duration_mean: number, epidemic_duration_median: number, epidemic_duration_p25: number, epidemic_duration_p75: number, epidemic_duration_std: number, epidemic_occurred_ci: shape { lower: number, upper: number }, epidemic_occurred_count: number, epidemic_occurred_rate: number, herd_immunity_reached_ci: shape { lower: number, upper: number }, herd_immunity_reached_count: number, herd_immunity_reached_rate: number, peak_fraction_mean: number, peak_fraction_median: number, peak_fraction_p25: number, peak_fraction_p75: number, peak_fraction_std: number, runs: number } }"
description: "SIR Agent-Based epidemic model — stochastic individual-level disease transmission with tunable R0. Emergent epidemic curves, herd immunity thresholds, and stochastic extinction."
source: epidemic_abm/init.lua
generated: gen_docs (V0)
---

# epidemic_abm — SIR Agent-Based Epidemic Model

> N agents transition between Susceptible → Infected → Recovered states. Each step, infected agents probabilistically transmit to susceptible contacts, and recover with probability γ.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.beta` | number | optional |  |
| `ctx.contacts_per_step` | number | optional |  |
| `ctx.gamma` | number | optional |  |
| `ctx.initial_infected` | number | optional |  |
| `ctx.n_agents` | number | optional |  |
| `ctx.runs` | number | optional |  |
| `ctx.steps` | number | optional |  |
| `ctx.task` | string | optional |  |
