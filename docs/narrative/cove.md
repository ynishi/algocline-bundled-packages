---
name: cove
version: 0.1.0
category: validation
result_shape: "shape { draft: string, final_response: string, verifications: array of shape { answer: string, question: string } }"
description: "Draft-verify-revise — reduces hallucination via independent fact-checking"
source: cove/init.lua
generated: gen_docs (V0)
---

# cove(CoVe) — Chain-of-Verification draft-verify-revise cycle

> Reduces hallucination by drafting an answer, generating verification questions about its claims, answering them independently, and producing a verified final response.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local cove = require("cove")
return cove.run(ctx)
```

## Algorithm {#algorithm}

1. Draft an initial answer.
2. Generate `n_questions` verification questions about the draft.
3. Answer each verification question independently.
4. Revise the draft using the verification answers.

## References {#references}

- Dhuliawala, S. et al. (2023). "Chain-of-Verification Reduces
  Hallucination in Large Language Models".
  https://arxiv.org/abs/2309.11495

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
