---
name: pre_mortem
version: 0.1.0
category: combinator
result_shape: "shape { accepted: number, needs_investigation: number, proposals: array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank?: number, rejection_reasons: array of string, status: string, verdict: string }, ranking: array of shape { calibrate_detail: table, confidence: number, contrastive_answer: string, prerequisites: table, proposal: string, rank: number, rejection_reasons: array of string, status: string, verdict: string }, rejected: number, total: number }"
description: "Feasibility-gated proposal filtering — prerequisite verification before rating"
source: pre_mortem/init.lua
generated: gen_docs (V0)
---

# pre_mortem(PreMortem) — feasibility-gated proposal filtering

> Combinator package that orchestrates `factscore`, `contrastive`, and `calibrate` to validate proposals before output. Decomposes each proposal into prerequisite assumptions, checks verification status, generates rejection reasons pre-emptively, and demotes or filters proposals with unverified prerequisites.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local pre_mortem = require("pre_mortem")
return pre_mortem.run(ctx)
```

## Algorithm {#algorithm}

1. `factscore` — decompose each proposal into atomic prerequisites
   and label each as SUPPORTED / UNSUPPORTED / UNCERTAIN.
2. `contrastive` — for each proposal generate "why it would be
   adopted" vs "why it would be rejected" reasoning pairs.
3. `calibrate` — judge VERDICT (adopt / reject) with CONFIDENCE as a
   meta-reliability gate. High confidence + adopt → accepted, high
   confidence + reject → rejected, low confidence →
   `needs_investigation` (escalate).
4. `rank` — pairwise tournament of accepted proposals to produce a
   final ordering by effectiveness.
ctx.n_contrasts: Number of contrastive pairs per proposal (default: 1)
ctx.extract_tokens: Max tokens for prerequisite extraction (default: 500)
ctx.verify_tokens: Max tokens per prerequisite verification (default: 200)

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
