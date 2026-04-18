---
name: pre_mortem
version: 0.1.0
category: combinator
result_shape: "shape { accepted: number, needs_investigation: number, proposals: array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank?: number, rejection_reasons: array of string, status: string, verdict: string }, ranking: array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank: number, rejection_reasons: array of string, status: string, verdict: string }, rejected: number, total: number }"
description: "Feasibility-gated proposal filtering — prerequisite verification before rating"
source: pre_mortem/init.lua
generated: gen_docs (V0)
---

# pre_mortem — feasibility-gated proposal filtering

> Combinator package: orchestrates factscore, contrastive, calibrate to validate proposals BEFORE output. Decomposes each proposal into prerequisite assumptions, checks verification status, generates rejection reasons pre-emptively, and demotes/filters proposals with unverified prerequisites.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.context` | string | optional | Additional verification context (e.g., known constraints) |
| `ctx.extract_tokens` | number | optional | Max tokens for prereq extraction (default: 500) |
| `ctx.n_contrasts` | number | optional | Contrastive pairs per proposal (default: 1) |
| `ctx.proposals` | any | **required** | Array of proposal strings or a single block to decompose |
| `ctx.task` | string | **required** | Original task/question addressed by the proposals |
| `ctx.threshold` | number | optional | Calibrate confidence threshold (default: 0.6) |
| `ctx.verify_tokens` | number | optional | Max tokens per prereq verification (default: 200) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `accepted` | number | — | Count of accepted proposals |
| `needs_investigation` | number | — | Count of low-confidence proposals needing escalation |
| `proposals` | array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank?: number, rejection_reasons: array of string, status: string, verdict: string } | — | Sorted evaluation records: ranked accepted → needs_investigation → rejected |
| `ranking` | array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank: number, rejection_reasons: array of string, status: string, verdict: string } | — | Accepted proposals in tournament-ranked order (empty when none accepted) |
| `rejected` | number | — | Count of rejected proposals |
| `total` | number | — | Total evaluated proposals |
