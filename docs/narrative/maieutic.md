---
name: maieutic
version: 0.1.0
category: reasoning
result_shape: "shape { consistency: shape { consistent: number, contradictory: number, independent: number }, evidence: shape { oppose: array of string, support: array of string }, synthesis: string, tree: any, verdict: string }"
description: "Maieutic prompting — recursive explanation tree with logical consistency verification"
source: maieutic/init.lua
generated: gen_docs (V0)
---

# Maieutic — recursive explanation tree with logical consistency filtering

> Given a proposition, generates supporting and opposing explanations recursively (depth-limited tree), then checks logical consistency between parent-child pairs to filter contradictions.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.consistency_tokens` | number | optional | Max tokens per consistency check (default: 100) |
| `ctx.gen_tokens` | number | optional | Max tokens per explanation (default: 300) |
| `ctx.max_depth` | number | optional | Tree depth (default: 2) |
| `ctx.proposition` | string | **required** | The claim to analyze |
