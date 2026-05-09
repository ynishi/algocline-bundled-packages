---
name: compute_alloc
version: 0.1.0
category: orchestration
result_shape: "shape { answer: string, candidates?: array of string, difficulty: string, paradigm: string, strategy: string, total_llm_calls: number }"
description: "Compute-optimal test-time scaling: select method and budget by difficulty."
source: compute_alloc/init.lua
generated: gen_docs (V0)
---

# compute_alloc(ComputeAlloc) — compute-optimal test-time scaling allocation

> Meta-strategy that dynamically selects the optimal reasoning method and budget allocation based on estimated problem difficulty, building on the finding that scaling test-time compute optimally can be more effective than scaling model parameters.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local ca = require("compute_alloc")
return ca.run(ctx)
```

## Algorithm {#algorithm}

1. Estimate the difficulty of `ctx.task`.
2. Select a paradigm from `{parallel, sequential, hybrid}` keyed on
   difficulty (easy=single-shot, medium=parallel `sc`/`usc`,
   hard=sequential `reflect` plus verify).
3. Allocate the token budget across the chosen paradigm and dispatch
   to existing AlgoCline packages.

## Comparison with related packages {#comparison-with-related-packages}

- `orch_escalate` — fixed 3-level cascade (quick → structured →
  thorough). Always starts light and escalates linearly.
- `router_daao` — classifies difficulty and routes to a strategy name;
  classification only, no compute-budget allocation.
- `compute_alloc` — estimates difficulty, selects a paradigm, and
  allocates token budget. The key insight is that the optimal method
  itself changes with difficulty.

## References {#references}

- Snell, C. et al. (2025). "Scaling LLM Test-Time Compute Optimally
  can be More Effective than Scaling Model Parameters". ICLR 2025.
  https://arxiv.org/abs/2408.03314
- "Test-Time Scaling Survey" (2025). https://arxiv.org/abs/2503.24235

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.budget` | string | optional | Budget hint: 'low' \| 'medium' \| 'high' (default: 'medium') |
| `ctx.gen_tokens` | number | optional | Max tokens per LLM call (default: 400) |
| `ctx.strategies` | table | optional | Custom difficulty→strategy map (overrides DEFAULT_STRATEGIES) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer produced by the selected paradigm |
| `candidates` | array of string | optional | Parallel candidates (set only for parallel / hybrid paradigms) |
| `difficulty` | string | — | Classified difficulty: 'easy' \| 'medium' \| 'hard' \| 'very_hard' |
| `paradigm` | string | — | Execution paradigm: 'single' \| 'parallel' \| 'sequential' \| 'hybrid' |
| `strategy` | string | — | Selected strategy name (e.g., 'direct', 'parallel', 'sequential', 'hybrid') |
| `total_llm_calls` | number | — | Total LLM calls (classification + execution) |
