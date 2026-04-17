---
name: claim_trace
version: 0.1.0
category: attribution
description: "Span-level evidence attribution — trace each claim to supporting source spans for transparent provenance"
source: claim_trace/init.lua
generated: gen_docs (V0)
---

# claim_trace — Span-level evidence attribution for LLM outputs

> For each claim in an LLM-generated answer, traces it back to specific spans in the source context. Unlike factscore (which only verifies correctness), claim_trace provides provenance: which part of the source supports each claim, enabling transparent attribution.
