---
name: calibrate
version: 0.2.0
category: meta
result_shape: calibrated
description: "Confidence-gated reasoning — fast path when confident, escalation when not"
source: calibrate/init.lua
generated: gen_docs (V0)
---

# Calibrate — confidence-gated adaptive reasoning

> Asks LLM to solve a task and self-assess confidence. If confidence is below threshold, escalates to a heavier strategy (ensemble, panel, or custom fallback).

## Contents

- [Result](#result)

## Result {#result}

Returns `calibrated` shape:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — |  |
| `confidence` | number | — | Initial self-assessed confidence |
| `escalated` | boolean | — | Whether fallback was triggered |
| `fallback_detail` | table | optional | Fallback strategy result (voted/paneled) |
| `strategy` | one_of("direct", "retry", "panel", "ensemble") | — |  |
| `total_llm_calls` | number | — |  |
