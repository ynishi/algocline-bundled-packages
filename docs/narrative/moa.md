---
name: moa
version: 0.1.0
category: selection
result_shape: "shape { answer: string, layer_outputs: array of array of string, n_agents: number, n_layers: number, total_calls: number }"
description: "Mixture of Agents — layered multi-agent aggregation with cross-referencing improvement"
source: moa/init.lua
generated: gen_docs (V0)
---

# moa — Mixture of Agents: layered multi-agent aggregation

> Multiple agents generate responses independently, then a second layer of agents improves upon those responses by referencing all of them. Unlike simple panel (single-round), MoA uses iterative layers where each layer's agents see ALL previous layer outputs, enabling cross- pollination of ideas and progressive refinement.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.agg_tokens` | number | optional | Max tokens for final aggregation (default: 500) |
| `ctx.gen_tokens` | number | optional | Max tokens per agent response (default: 400) |
| `ctx.n_agents` | number | optional | Agents per layer (default: 3, capped to #PERSONAS=5) |
| `ctx.n_layers` | number | optional | Number of improvement layers (default: 2) |
| `ctx.task` | string | **required** | Task description |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesized answer |
| `layer_outputs` | array of array of string | — | Per-layer agent outputs ([layer_idx][agent_idx]) |
| `n_agents` | number | — | Agents per layer actually used |
| `n_layers` | number | — | Layers actually executed |
| `total_calls` | number | — | Total LLM invocations (agents * layers + 1 aggregation) |
