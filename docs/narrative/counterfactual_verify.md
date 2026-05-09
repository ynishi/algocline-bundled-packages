---
name: counterfactual_verify
version: 0.1.0
category: validation
result_shape: "shape { answer: string, counterfactual_results: array of shape { actual: string, change: string, match: boolean, predicted: string, reason: string }, faithful: boolean, match_count: number, mismatches: array of shape { change: string, reason: string }, original_cot: string, total_counterfactuals: number }"
description: "Counterfactual simulation to verify causal faithfulness of a reasoning chain."
source: counterfactual_verify/init.lua
generated: gen_docs (V0)
---

# counterfactual_verify(CounterfactualVerify) — causal faithfulness via counterfactual simulation

> Tests whether a reasoning chain is genuinely faithful to its inputs by asking: if the input changed, would the conclusion change accordingly? Unlike `cove` (factual correctness) or `verify_first` (reverse verification), this entry detects pattern-matching and memorization by testing causal dependence between premises and conclusions.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local cf = require("counterfactual_verify")
return cf.run(ctx)
```

## Algorithm {#algorithm}

For `N = n_counterfactuals` the entry uses 2 + 3*N LLM calls:

1. Solve — generate the chain-of-thought and answer for the original
   problem.
2. Counterfactual — generate `N` variants by changing one condition.
3. Predict — from the original CoT, predict the answer under each
   variant.
4. Solve CF — solve each variant independently in parallel.
5. Judge — compare predicted vs actual answers per variant.
6. Verdict — if unfaithful, re-solve with explicit grounding.

## References {#references}

- Hase, P. et al. (2026). "Counterfactual Simulation Training for
  Chain-of-Thought Faithfulness". https://arxiv.org/abs/2602.20710

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.cf_tokens` | number | optional | Max tokens for counterfactual generation (default: 400) |
| `ctx.gen_tokens` | number | optional | Max tokens for solving (default: 600) |
| `ctx.n_counterfactuals` | number | optional | Number of counterfactual variants (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer (original CoT when faithful, re-solved otherwise) |
| `counterfactual_results` | array of shape { actual: string, change: string, match: boolean, predicted: string, reason: string } | — | Per-counterfactual evaluation records |
| `faithful` | boolean | — | Whether reasoning is causally faithful to inputs (all CFs matched) |
| `match_count` | number | — | Count of counterfactuals where predicted matched actual |
| `mismatches` | array of shape { change: string, reason: string } | — | Subset of counterfactual_results where match=false (empty when faithful) |
| `original_cot` | string | — | Original chain-of-thought reasoning for unmodified task |
| `total_counterfactuals` | number | — | Total counterfactuals evaluated (= #counterfactual_results) |
