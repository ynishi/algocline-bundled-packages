---
name: pbft
version: 0.1.0
category: aggregation
result_shape: "shape { answer: string, bft_valid: boolean, commit_method: string, f_assumed: number, n_agents: number, proposals: array of string, quorum_met: boolean, quorum_required: number, vote_distribution: array of shape { proposal: number, votes: number }, votes: array of number, winner_proposal: number, winner_votes: number }"
description: "PBFT-inspired 3-phase LLM consensus — propose, validate, commit with BFT quorum guarantees (Castro-Liskov 1999)"
source: pbft/init.lua
generated: gen_docs (V0)
---

# pbft — Practical Byzantine Fault Tolerant consensus via LLM

> Multi-agent 3-phase consensus protocol inspired by PBFT (Castro-Liskov OSDI 1999). Uses the bft package for quorum validation and threshold computation.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.f` | number | optional | Assumed Byzantine faults (default: 0) |
| `ctx.gen_system` | string | optional | Custom system prompt for proposal phase |
| `ctx.gen_tokens` | number | optional | Max tokens per proposal (default: 400) |
| `ctx.n_agents` | number | optional | Number of agents (default: 3, must satisfy n >= 3f+1) |
| `ctx.synth_system` | string | optional | Custom system prompt for synthesis phase |
| `ctx.synth_tokens` | number | optional | Max tokens for synthesis (default: 500) |
| `ctx.task` | string | **required** | The problem to solve |
| `ctx.vote_system` | string | optional | Custom system prompt for voting phase |
| `ctx.vote_tokens` | number | optional | Max tokens per vote (default: 200) |
