---
name: contrastive
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, contrasts: array of shape { error_analysis: string, wrong_reasoning: string }, total_contrasts: number }"
description: "Contrastive CoT: generate correct and wrong chains and learn from the contrast."
source: contrastive/init.lua
generated: gen_docs (V0)
---

# contrastive(Contrastive) — learn from correct and incorrect reasoning

> Generates both a correct reasoning path and a plausible-but-wrong path then contrasts them to strengthen the final answer. Explicitly models failure modes alongside the success path.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local contrastive = require("contrastive")
return contrastive.run(ctx)
```

## Algorithm {#algorithm}

1. For `n_contrasts` pairs, generate one correct chain-of-thought and
   one plausible-but-wrong chain-of-thought.
2. Contrast the pairs to highlight failure modes.
3. Produce a final answer informed by the contrast.

## References {#references}

- Chia, Y. K. et al. (2023). "Contrastive Chain-of-Thought Prompting".
  https://arxiv.org/abs/2311.09277

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.n_contrasts` | number | optional | Number of contrast pairs (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer informed by contrast analysis |
| `contrasts` | array of shape { error_analysis: string, wrong_reasoning: string } | — | Per-iteration wrong-reasoning + error-analysis pairs |
| `total_contrasts` | number | — | = #contrasts |
