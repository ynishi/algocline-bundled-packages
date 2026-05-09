---
name: factscore
version: 0.1.0
category: validation
result_shape: "shape { claims: array of shape { claim: string, justification: string, status: string }, score: number, supported: number, total: number, uncertain: number, unsupported: number }"
description: "Atomic claim decomposition — per-claim factual verification with scoring"
source: factscore/init.lua
generated: gen_docs (V0)
---

# factscore(FActScore) — atomic claim decomposition and per-claim verification

> Extracts atomic claims from text, then independently verifies each claim in parallel. Produces a factual precision score and annotated results.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local factscore = require("factscore")
return factscore.run(ctx)
```

## Algorithm {#algorithm}

Given a text, the pkg performs three phases:

1. **Decompose** — an LLM extracts the text into atomic, self-contained
   factual claims (each independently verifiable).
2. **Verify** — each claim is verified in parallel via `alc.parallel`.
   Each verifier emits SUPPORTED / UNSUPPORTED / UNCERTAIN with a
   one-sentence justification.
3. **Score** — factual precision is computed as:

```math
FActScore = supported / (supported + unsupported)
```

Uncertain claims are excluded from the denominator; score is 1.0 when
no decisive (supported or unsupported) claims exist.

## Theoretical foundations {#theoretical-foundations}

Min et al. (2023) define factual precision as the fraction of atomic
claims that are supported by a knowledge source. Each claim is the
smallest independently verifiable unit of information in the text.
The metric is designed to isolate factual errors from stylistic or
logical errors.

## References {#references}

- Min, S., Krishna, K., Lyu, X., Lewis, M., Yih, W., Koh, P. W.,
  Iyyer, M., Zettlemoyer, L., Hajishirzi, H. (2023).
  "FActScore: Fine-grained Atomic Evaluation of Factual Precision
  in Long Form Text Generation". arXiv:2305.14251.

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
