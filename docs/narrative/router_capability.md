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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_results` | number | optional | Number of top matches to return in alternatives (default 3) |
| `ctx.registry` | array of shape { capabilities: array of string, cost: number, description: string, name: string } | optional | Agent registry; defaults to DEFAULT_REGISTRY |
| `ctx.task` | string | **required** | Task description (required) |
