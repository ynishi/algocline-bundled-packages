---
name: intent_discovery
version: 0.1.0
category: intent
result_shape: "shape { converged: boolean, exploration_log: array of shape { key_dimension: string, options: array of shape { description: string, label: string, title: string }, preference: string, round: number }, intent_hierarchy: array of shape { remaining: string, resolved: string, understanding: string }, original_task: string, rounds: number, specified_task: string }"
description: "Exploratory intent formation — discover user goals through structured option presentation and iterative narrowing"
source: intent_discovery/init.lua
generated: gen_docs (V0)
---

# Intent Discovery — exploratory intent formation through action

> Users often approach tasks without fully-formed goals. This strategy helps users discover their intent by presenting structured options, observing preferences, and progressively concretizing a hierarchy of intents through iterative exploration.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.concretize_tokens` | number | optional | Max tokens for concretization (default 500) |
| `ctx.max_rounds` | number | optional | Maximum exploration rounds (default 3) |
| `ctx.n_options` | number | optional | Number of options to present per round (default 3) |
| `ctx.surface_tokens` | number | optional | Max tokens for option generation (default 600) |
| `ctx.task` | string | **required** | Initial (possibly vague) user request (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `converged` | boolean | — | Whether exploration ended early via CONVERGENCE:YES or empty remaining |
| `exploration_log` | array of shape { key_dimension: string, options: array of shape { description: string, label: string, title: string }, preference: string, round: number } | — | Per-round record of options, key_dimension, and user preference |
| `intent_hierarchy` | array of shape { remaining: string, resolved: string, understanding: string } | — | Per-round resolved/remaining/understanding trace (round-indexed, 1-based) |
| `original_task` | string | — | Echo of input task |
| `rounds` | number | — | Number of exploration rounds actually executed |
| `specified_task` | string | — | Current understanding after final round |
