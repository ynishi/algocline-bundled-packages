---
name: factscore
version: 0.1.0
category: validation
result_shape: "shape { claims: array of shape { claim: string, justification: string, status: string }, score: number, supported: number, total: number, uncertain: number, unsupported: number }"
description: "Atomic claim decomposition — per-claim factual verification with scoring"
source: factscore/init.lua
generated: gen_docs (V0)
---

# FActScore — atomic claim decomposition and per-claim verification

> Extracts atomic claims from text, then independently verifies each claim in parallel. Produces a factual precision score and annotated results.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.context` | string | optional | Optional reference context for verification |
| `ctx.extract_tokens` | number | optional | Max tokens for claim extraction (default: 500) |
| `ctx.text` | string | **required** | The text to fact-check |
| `ctx.verify_tokens` | number | optional | Max tokens per claim verification (default: 200) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `claims` | array of shape { claim: string, justification: string, status: string } | — | Per-claim verification records (empty when extraction yields no claims) |
| `score` | number | — | Factual precision score = supported / (supported+unsupported); 1.0 when no decisive claims |
| `supported` | number | — | Count of SUPPORTED claims |
| `total` | number | — | Total number of extracted claims |
| `uncertain` | number | — | Count of UNCERTAIN claims |
| `unsupported` | number | — | Count of UNSUPPORTED claims |
