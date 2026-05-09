---
name: calibrate
version: 0.2.0
category: meta
result_shape: calibrated
description: "Confidence-gated reasoning — fast path when confident, escalation when not"
source: calibrate/init.lua
generated: gen_docs (V0)
---

# calibrate(Calibrate) — confidence-gated adaptive reasoning

> Asks the LLM to solve a task and self-assess its confidence. When confidence is below the threshold the entry escalates to a heavier strategy (ensemble, panel, or a custom fallback).

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Result](#result)

## Usage {#usage}

```lua
local calibrate = require("calibrate")
return calibrate.run(ctx)      -- full gated escalation
return calibrate.assess(ctx)   -- confidence assessment only (1 call)
```

## Algorithm {#algorithm}

1. Generate an initial attempt and a self-reported confidence score.
2. If confidence is at or above `threshold`, return the initial answer.
3. Otherwise escalate via the configured `fallback` (ensemble, panel,
   or retry) with `fallback_opts`.

## References {#references}

- "CISC: Confidence-Informed Self-Consistency". ACL Findings 2025.

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
