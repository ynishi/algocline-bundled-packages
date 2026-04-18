---
name: router_semantic
version: 0.1.0
category: routing
result_shape: "shape { alternatives: array of shape { description: string, matched_keywords: array of string, name: string, raw_matches: number, score: number }, confidence: number, method: one_of(\"keyword\", \"llm_fallback\", \"keyword_forced\"), reasoning: string, selected: string }"
description: "Keyword/pattern-based routing with LLM fallback. Zero LLM calls for clear matches, one call for ambiguous cases. Based on Semantic Router pattern (Microsoft Multi-Agent Reference Architecture)."
source: router_semantic/init.lua
generated: gen_docs (V0)
---

# router_semantic — Semantic Router with LLM Fallback

> Keyword/pattern-based routing with LLM fallback for ambiguous cases. Zero LLM calls for clear matches, one call for ambiguous cases.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.rules` | array of shape { description: string, keywords: array of string, name: string } | optional | Routing rules; defaults to DEFAULT_RULES |
| `ctx.task` | string | **required** | Task description (required) |
| `ctx.threshold` | number | optional | Minimum keyword score to skip LLM (default 0.3) |
