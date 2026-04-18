---
name: intent_belief
version: 0.1.0
category: intent
result_shape: "shape { converged?: boolean, error?: string, final_entropy?: number, map_confidence?: number, map_hypothesis?: string, original_task?: string, ranked_hypotheses?: array of shape { belief: number, description: string, id: number }, raw?: string, rounds?: number, specified_task?: string, update_log?: array of shape { answer: string, entropy: number, likelihoods: array of number, posterior: array of number, prior: array of number, question: string, round: number } }"
description: "Bayesian intent estimation — hypothesis generation with iterative belief updates via diagnostic questions"
source: intent_belief/init.lua
generated: gen_docs (V0)
---

# Intent Belief — Bayesian intent estimation via hypothesis generation and update

> Maintains a belief distribution over candidate intents. Generates multiple intent hypotheses as prior, then iteratively updates beliefs through diagnostic questions and likelihood estimation.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.confidence_threshold` | number | optional | Stop when top hypothesis exceeds this (default 0.7) |
| `ctx.diagnose_tokens` | number | optional | Max tokens per diagnostic question (default 400) |
| `ctx.max_rounds` | number | optional | Maximum belief update rounds (default 3) |
| `ctx.n_hypotheses` | number | optional | Number of intent hypotheses to generate (default 5) |
| `ctx.prior_tokens` | number | optional | Max tokens for prior generation (default 600) |
| `ctx.task` | string | **required** | Initial user request (required) |
| `ctx.update_tokens` | number | optional | Max tokens per belief update (default 500) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `converged` | boolean | optional | Whether MAP exceeded confidence_threshold before max_rounds (success path) |
| `error` | string | optional | Set only on prior-parse failure; success path omits this |
| `final_entropy` | number | optional | Shannon entropy of final posterior (success path) |
| `map_confidence` | number | optional | Posterior probability of MAP hypothesis (success path) |
| `map_hypothesis` | string | optional | Description of maximum-a-posteriori hypothesis (success path) |
| `original_task` | string | optional | Echo of input task (success path) |
| `ranked_hypotheses` | array of shape { belief: number, description: string, id: number } | optional | All hypotheses sorted by posterior desc (success path) |
| `raw` | string | optional | Raw prior LLM output; present only on error path |
| `rounds` | number | optional | Number of update rounds actually executed (success path) |
| `specified_task` | string | optional | LLM-rewritten task aligned to MAP hypothesis (success path) |
| `update_log` | array of shape { answer: string, entropy: number, likelihoods: array of number, posterior: array of number, prior: array of number, question: string, round: number } | optional | Per-round Bayesian update trace (success path) |
