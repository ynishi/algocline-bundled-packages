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
- [Result](#result)

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

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Committed answer (winning proposal or synthesized) |
| `bft_valid` | boolean | — | True when bft.validate(n, f) passed (always true if we reach here) |
| `commit_method` | string | — | "quorum" (2f+1 agreement) \| "synthesis" (no consensus) |
| `f_assumed` | number | — | Byzantine-fault budget passed to bft |
| `n_agents` | number | — | Number of agents actually used |
| `proposals` | array of string | — | Raw proposals from Phase 1 (always preserved per N2 Red Line) |
| `quorum_met` | boolean | — | True iff winner_votes >= quorum_required |
| `quorum_required` | number | — | BFT threshold = n - f |
| `vote_distribution` | array of shape { proposal: number, votes: number } | — | Vote counts sorted desc by votes |
| `votes` | array of number | — | Per-agent vote (proposal index); falls back to own index on parse failure |
| `winner_proposal` | number | — | Proposal index with plurality (arbitrary tie-break order) |
| `winner_votes` | number | — | Vote count for winner_proposal |
