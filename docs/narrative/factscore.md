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

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.context` | string | optional | Optional reference context for verification |
| `ctx.extract_tokens` | number | optional | Max tokens for claim extraction (default: 500) |
| `ctx.text` | string | **required** | The text to fact-check |
| `ctx.verify_tokens` | number | optional | Max tokens per claim verification (default: 200) |
