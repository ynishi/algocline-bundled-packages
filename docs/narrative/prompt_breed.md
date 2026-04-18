---
name: prompt_breed
version: 0.1.0
category: exploration
result_shape: "shape { best_prompt: string, best_score: number, evolution_history: array of shape { avg_score: number, best_score: number, generation: number }, mutation_prompts: array of string, population: array of shape { prompt: string, rank: number, score: number }, stats: shape { crossover_rate: number, generations: number, hyper_mutation_rate: number, mutation_pool: number, population_size: number } }"
description: "Self-Referential Prompt Evolution — evolves task prompts via genetic operators with meta-mutation (the mutation operators themselves evolve). Double evolutionary loop."
source: prompt_breed/init.lua
generated: gen_docs (V0)
---

# prompt_breed — Self-Referential Prompt Evolution

> Evolves a population of task prompts (instructions) using genetic operators, with a unique twist: the mutation operators themselves (mutation prompts) also evolve. This double loop — task-prompt evolution + meta-mutation evolution — enables the system to discover increasingly effective ways to explore prompt space.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.crossover_rate` | number | optional | Probability of crossover vs mutation for offspring (default 0.3) |
| `ctx.evaluator` | string | **required** | Evaluation criteria/prompt used by evaluate_prompt (required) |
| `ctx.generations` | number | optional | Number of evolution generations (default 8) |
| `ctx.hyper_mutation_rate` | number | optional | Per-mutation-prompt probability of meta-mutation (default 0.15) |
| `ctx.mutation_pool` | number | optional | Number of mutation meta-prompts (default 3) |
| `ctx.population_size` | number | optional | Number of task prompts in the population (default 6) |
| `ctx.task` | string | **required** | Task domain description used in all prompts (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `best_prompt` | string | — | Highest-scoring task prompt encountered across the entire run |
| `best_score` | number | — | Score of best_prompt |
| `evolution_history` | array of shape { avg_score: number, best_score: number, generation: number } | — | Per-generation best/avg summary |
| `mutation_prompts` | array of string | — | Final mutation meta-prompts (after hyper-mutation) |
| `population` | array of shape { prompt: string, rank: number, score: number } | — | Final population sorted descending by score |
| `stats` | shape { crossover_rate: number, generations: number, hyper_mutation_rate: number, mutation_pool: number, population_size: number } | — |  |
