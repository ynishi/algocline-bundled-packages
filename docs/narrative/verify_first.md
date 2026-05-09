---
name: verify_first
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, candidate_source: string, extracted_answer: string, history: array of shape { extracted_answer: string, input_candidate: string, round: number, verification: string }, iterations: number }"
description: "Verification-First prompting — verify a candidate answer before generating, reducing logical errors via reverse reasoning"
source: verify_first/init.lua
generated: gen_docs (V0)
---

# verify_first(VerifyFirst) — verification-first prompting

> Provides a candidate answer (trivial, random, or CoT-generated), then instructs the LLM to verify it before generating the real answer. Reverse reasoning is cognitively easier than forward generation and reduces logical errors by overcoming egocentric bias. Supports iterative mode (Iter-VF): a Markovian verify→extract→re-verify loop that scales test-time compute without context overflow.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local verify_first = require("verify_first")
return verify_first.run(ctx)
```

## Algorithm {#algorithm}

1. Generate — produce an initial candidate answer (CoT or trivial).
2. Verify — "a possible answer is X; first verify if X is correct,
   then think step by step to find the answer".
3. Iter-VF (optional) — repeat step 2 with the extracted answer
   from the previous round.

## References {#references}

- "Asking LLMs to Verify First is Almost Free Lunch" (2025).
  https://arxiv.org/abs/2511.21734
ctx.trivial: Use trivial candidate "1" instead of CoT (default: false)
ctx.iterations: Number of Iter-VF rounds (default: 1, i.e. single VF)
ctx.gen_tokens: Max tokens for generation (default: 600)
ctx.verify_tokens: Max tokens for verification (default: 800)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.candidate` | string | optional | Pre-supplied candidate answer (default: nil => auto-generate) |
| `ctx.gen_tokens` | number | optional | Max tokens for candidate generation (default: 600) |
| `ctx.iterations` | number | optional | Number of Iter-VF rounds (default: 1) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.trivial` | boolean | optional | Use trivial candidate '1' instead of CoT (default: false) |
| `ctx.verify_tokens` | number | optional | Max tokens per verification round (default: 800) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final verification text of the last round |
| `candidate_source` | string | — | Origin of initial candidate: provided / trivial / cot |
| `extracted_answer` | string | — | Answer extracted from the final verification |
| `history` | array of shape { extracted_answer: string, input_candidate: string, round: number, verification: string } | — | Per-round Markovian trace: candidate in, verification out, extracted answer |
| `iterations` | number | — | Number of Iter-VF rounds actually executed |
