---
name: rstar
version: 0.1.0
category: reasoning
result_shape: "shape { agreement: one_of(\"full\", \"partial\", \"none\"), answer: string, path_a: shape { conclusion: string, reasoning: string }, path_b: shape { conclusion: string, reasoning: string }, resolution_needed: boolean, verification: shape { a_agrees_b: boolean, a_checks_b: string, b_agrees_a: boolean, b_checks_a: string } }"
description: "Mutual reasoning verification — two paths cross-verify each other for efficient accuracy"
source: rstar/init.lua
generated: gen_docs (V0)
---

# rstar(RStar) — mutual reasoning verification via self-play

> Generates two independent reasoning paths, then each path verifies the other. Disagreements trigger a resolution round. Achieves MCTS-level accuracy at a fraction of the cost by replacing tree search with targeted mutual critique.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local rstar = require("rstar")
return rstar.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 4-6 LLM calls:

1. Generate Path A — independent reasoning attempt.
2. Generate Path B — independent reasoning attempt (parallel).
3. Cross-verify — A verifies B and B verifies A (parallel).
4. Resolve — on disagreement, synthesize the final answer.

## References {#references}

- Qi, Z. et al. (2024). "Mutual Reasoning Makes Smaller LLMs
  Stronger Problem-Solvers" (rStar).
  https://arxiv.org/abs/2408.06195

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per reasoning path (default: 400) |
| `ctx.task` | string | **required** | The problem to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per cross-verification (default: 300) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `agreement` | one_of("full", "partial", "none") | — | Agreement level between path_a and path_b |
| `answer` | string | — | Final answer (from agreement or resolution) |
| `path_a` | shape { conclusion: string, reasoning: string } | — | Path A (first-principles approach) |
| `path_b` | shape { conclusion: string, reasoning: string } | — | Path B (multi-angle approach) |
| `resolution_needed` | boolean | — | Whether a resolution LLM call was issued |
| `verification` | shape { a_agrees_b: boolean, a_checks_b: string, b_agrees_a: boolean, b_checks_a: string } | — | Cross-verification outputs |
