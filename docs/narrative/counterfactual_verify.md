---
name: counterfactual_verify
version: 0.1.0
category: validation
result_shape: "shape { answer: string, counterfactual_results: array of shape { actual: string, change: string, match: boolean, predicted: string, reason: string }, faithful: boolean, match_count: number, mismatches: array of shape { change: string, reason: string }, original_cot: string, total_counterfactuals: number }"
description: "Counterfactual faithfulness verification — tests whether reasoning causally depends on inputs by simulating condition changes. Detects pattern-matching and unfaithful CoT."
source: counterfactual_verify/init.lua
generated: gen_docs (V0)
---

# counterfactual_verify — Causal faithfulness verification via counterfactual simulation

> Tests whether a reasoning chain is genuinely faithful to its inputs by checking: "If the input changed, would the conclusion change accordingly?" Unlike cove (factual correctness) or verify_first (reverse verification), this detects pattern-matching and memorization by testing causal dependence between premises and conclusions.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.cf_tokens` | number | optional | Max tokens for counterfactual generation (default: 400) |
| `ctx.gen_tokens` | number | optional | Max tokens for solving (default: 600) |
| `ctx.n_counterfactuals` | number | optional | Number of counterfactual variants (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
