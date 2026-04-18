---
name: router_capability
version: 0.1.0
category: routing
result_shape: "shape { alternatives: array of shape { capabilities: array of string, cost: number, description: string, name: string, score: number }, confidence: number, method: string, reasoning: string, requirements: array of string, selected: string }"
description: "Capability-based routing using agent registry metadata matching. Extracts task requirements via LLM, then scores against agent capabilities using Jaccard similarity. Based on Dynamic Agent Registry pattern."
source: router_capability/init.lua
generated: gen_docs (V0)
---

# router_capability — Capability-based Registry Router

> Extracts task requirements via LLM, then scores against agent capabilities using Jaccard similarity. Based on Dynamic Agent Registry pattern.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_results` | number | optional | Number of top matches to return in alternatives (default 3) |
| `ctx.registry` | array of shape { capabilities: array of string, cost: number, description: string, name: string } | optional | Agent registry; defaults to DEFAULT_REGISTRY |
| `ctx.task` | string | **required** | Task description (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `alternatives` | array of shape { capabilities: array of string, cost: number, description: string, name: string, score: number } | — | Top N candidates sorted by score desc, cost asc |
| `confidence` | number | — | Top agent's Jaccard score (0 if no match) |
| `method` | string | — | Scoring method identifier ('jaccard') |
| `reasoning` | string | — | LLM-extracted reasoning, or failure note |
| `requirements` | array of string | — | Capability tags extracted from task |
| `selected` | string | — | Best-match agent name, or 'unknown' if registry empty |
