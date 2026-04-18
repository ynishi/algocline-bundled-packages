---
name: claim_trace
version: 0.1.0
category: attribution
result_shape: "shape { answer: string, attribution_score: number, claims: array of shape { claim: string, raw: string, reasoning: string, source_index?: number, span: string, status: string }, coverage: number, partial: number, sources_count?: number, supported: number, total: number, unsupported: number }"
description: "Span-level evidence attribution — trace each claim to supporting source spans for transparent provenance"
source: claim_trace/init.lua
generated: gen_docs (V0)
---

# claim_trace — Span-level evidence attribution for LLM outputs

> For each claim in an LLM-generated answer, traces it back to specific spans in the source context. Unlike factscore (which only verifies correctness), claim_trace provides provenance: which part of the source supports each claim, enabling transparent attribution.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.answer` | string | optional | Pre-supplied answer to attribute (auto-generated if nil) |
| `ctx.extract_tokens` | number | optional | Max tokens for claim extraction (default: 500) |
| `ctx.gen_tokens` | number | optional | Max tokens for answer generation (default: 600) |
| `ctx.sources` | any | **required** | Source text(s): single string or array of strings |
| `ctx.task` | string | **required** | The original question/task |
| `ctx.trace_tokens` | number | optional | Max tokens per claim attribution (default: 300) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Answer whose claims were traced (auto-generated or passed in) |
| `attribution_score` | number | — | (supported + 0.5*partial) / total; 1.0 when no claims |
| `claims` | array of shape { claim: string, raw: string, reasoning: string, source_index?: number, span: string, status: string } | — | Per-claim attribution records (empty when no claims extracted) |
| `coverage` | number | — | (supported + partial) / total; 1.0 when no claims |
| `partial` | number | — | Count of PARTIAL claims |
| `sources_count` | number | optional | Number of source documents (omitted on empty-claims short-circuit) |
| `supported` | number | — | Count of SUPPORTED claims |
| `total` | number | — | Total extracted claims |
| `unsupported` | number | — | Count of UNSUPPORTED claims |
