---
name: faithful
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, errors_found: boolean, formal: string, format: string, nl_reasoning: string, verification: string }"
description: "Faithful CoT — formalize reasoning into code/logic for verification, then answer"
source: faithful/init.lua
generated: gen_docs (V0)
---

# faithful(Faithful) — faithful chain-of-thought with formal verification

> Translates natural-language reasoning into a formal representation (code, logic, or structured proof) for verification, then produces a natural-language answer grounded in the verified formal output. Catches reasoning errors that are invisible in natural language.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local faithful = require("faithful")
return faithful.run(ctx)
```

## Algorithm {#algorithm}

The pipeline uses 3-4 LLM calls:

1. Reason — natural-language chain-of-thought.
2. Formalize — translate reasoning to a formal representation.
3. Verify — check the formal representation for correctness.
4. Answer — produce the final answer grounded in verification.

## References {#references}

- Lyu, Q. et al. (2023). "Faithful Chain-of-Thought Reasoning".
  https://arxiv.org/abs/2301.13379
- Gao, L. et al. (2023). "PAL: Program-Aided Language Models".
  https://arxiv.org/abs/2211.10435

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.format` | string | optional | Formal representation type: code / logic / auto (default: auto) |
| `ctx.gen_tokens` | number | optional | Max tokens per step (default: 500) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer grounded in formal verification |
| `errors_found` | boolean | — | True if verification surfaced any errors in the reasoning |
| `formal` | string | — | Step 2 formal representation (code or logic derivation) |
| `format` | string | — | Formal representation actually used: code / logic |
| `nl_reasoning` | string | — | Step 1 natural-language reasoning chain |
| `verification` | string | — | Step 3 verification output |
