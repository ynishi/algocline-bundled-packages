---
name: cove
version: 0.1.0
category: validation
result_shape: "shape { draft: string, final_response: string, verifications: array of shape { answer: string, question: string } }"
description: "Draft-verify-revise — reduces hallucination via independent fact-checking"
source: cove/init.lua
generated: gen_docs (V0)
---

# CoVe — Chain-of-Verification: draft-verify-revise cycle

> Reduces hallucination by: draft → generate verification questions → answer them independently → produce verified final response.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n_questions` | number | optional | Number of verification questions (default: 3) |
| `ctx.task` | string | **required** | The question/task to answer |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `draft` | string | — | Baseline draft answer |
| `final_response` | string | — | Final answer after fact-check revision |
| `verifications` | array of shape { answer: string, question: string } | — | Per-question verification records (may be shorter than n_questions) |
