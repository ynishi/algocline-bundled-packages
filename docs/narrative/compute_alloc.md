---
name: compute_alloc
version: 0.1.0
category: orchestration
result_shape: "shape { answer: string, candidates?: array of string, difficulty: string, paradigm: string, strategy: string, total_llm_calls: number }"
description: "Compute-optimal test-time scaling — dynamically selects reasoning method (parallel/sequential/hybrid) and budget allocation based on problem difficulty. Uses existing packages as components."
source: compute_alloc/init.lua
generated: gen_docs (V0)
---

# compute_alloc — Compute-Optimal Test-Time Scaling Allocation

> Meta-strategy that dynamically selects the optimal reasoning method and budget allocation based on problem difficulty. Implements the key finding from Snell et al. (ICLR 2025): "scaling test-time compute optimally can be more effective than scaling model parameters."

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.budget` | string | optional | Budget hint: 'low' \| 'medium' \| 'high' (default: 'medium') |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 400) |
| `ctx.strategies` | table | optional | Custom difficulty→strategy map (overrides DEFAULT_STRATEGIES) |
| `ctx.task` | string | **required** | The problem to solve |
