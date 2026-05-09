---
name: router_daao
version: 0.1.0
category: routing
result_shape: "shape { alternatives: array of string, confidence: number, difficulty: string, profile: shape { confidence?: number, context_mode: string, depth: number, fallback_confidence?: number, max_retries: number, recommended_strategies: array of string, skip_phases: array of string }, reasoning: string, selected: string }"
description: "Difficulty-aware task routing based on DAAO (arxiv 2509.11079). Classifies task difficulty with a single LLM call, then maps to optimal strategy/depth/parameters via deterministic lookup."
source: router_daao/init.lua
generated: gen_docs (V0)
---

# router_daao(RouterDAAO) — difficulty-aware agent orchestration router

> Classifies task difficulty with a single LLM call, then maps to the optimal strategy / depth / parameters via deterministic lookup (lightweight difficulty estimation + adaptive resource allocation).

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local router = require("router_daao")
return router.run(ctx)
```

## References {#references}

- DAAO. https://arxiv.org/abs/2509.11079

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.candidates` | any | optional | Candidate strategies — string[] or {name=string}[] mix accepted |
| `ctx.profiles` | map of string to shape { confidence?: number, context_mode: string, depth: number, fallback_confidence?: number, max_retries: number, recommended_strategies: array of string, skip_phases: array of string } | optional | Custom difficulty→profile mapping; defaults to DEFAULT_PROFILES |
| `ctx.task` | string | **required** | Task description (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `alternatives` | array of string | — | profile.recommended_strategies |
| `confidence` | number | — | Profile-derived confidence (0-1) |
| `difficulty` | string | — | Classified difficulty: 'simple' \| 'medium' \| 'complex' (or default 'medium' on parse failure) |
| `profile` | shape { confidence?: number, context_mode: string, depth: number, fallback_confidence?: number, max_retries: number, recommended_strategies: array of string, skip_phases: array of string } | — | Full profile record for the selected difficulty |
| `reasoning` | string | — | LLM reasoning or parse-failure note |
| `selected` | string | — | Selected strategy name |
