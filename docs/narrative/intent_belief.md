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
