---
name: aco
version: 0.1.0
category: exploration
result_shape: "shape { answer: string, best_path: array of string, best_score: number, history: array of shape { avg_score: number, best_score: number, iteration: number }, iterations: number, n_ants: number, n_nodes: number, rho: number }"
description: "Ant Colony Optimization — discrete path search with pheromone-based learning (Dorigo 1996, Gutjahr 2000 convergence)"
source: aco/init.lua
generated: gen_docs (V0)
---

# aco — Ant Colony Optimization for discrete path search

> Implements the Ant System (Dorigo 1996) with convergence guarantees from Gutjahr 2000 (GBAS). Provides both a pure-computation engine and an LLM-integrated run(ctx) for workflow/path optimization.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha` | number | optional | Pheromone exponent α (default: 1.0) |
| `ctx.answer_tokens` | number | optional | Max tokens for final answer synthesis (default: 500) |
| `ctx.beta` | number | optional | Heuristic exponent β (default: 2.0) |
| `ctx.budget` | number | optional | Max iterations (default: 20) |
| `ctx.decompose_system` | string | optional | System prompt for the decompose LLM |
| `ctx.eval_fn` | any | optional | Optional user-supplied scorer: function(path) -> score; when absent an LLM-based scorer is used |
| `ctx.eval_system` | string | optional | System prompt for the eval LLM |
| `ctx.exec_system` | string | optional | System prompt for the exec LLM |
| `ctx.n_ants` | number | optional | Ants per iteration (default: 5) |
| `ctx.nodes` | array of string | optional | Node labels for the graph; generated via decompose LLM when omitted |
| `ctx.rho` | number | optional | Pheromone evaporation rate ρ ∈ (0,1) (default: 0.2) |
| `ctx.seed` | number | optional | RNG seed (default: 42) |
| `ctx.stagnation` | number | optional | Stagnation iteration threshold (default: 5) |
| `ctx.task` | string | **required** | The task to solve |
