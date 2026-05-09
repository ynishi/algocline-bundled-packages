---
name: dmad
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, antithesis: string, debate_log: array of shape { role: one_of(\"thesis\", \"antithesis\", \"rebuttal\", \"synthesis\"), round: number, text: string }, rounds: number, synthesis: string, thesis: string }"
description: "Dialectical reasoning — thesis, antithesis, and synthesis for deeper analysis"
source: dmad/init.lua
generated: gen_docs (V0)
---

# dmad(DMAD) — dialectical reasoning (thesis → antithesis → synthesis)

> Applies the Hegelian dialectic to LLM reasoning: generates a thesis (initial position), constructs the strongest possible antithesis, and produces a synthesis that integrates valid points from both sides. Unlike `panel` (sequential multi-role discussion) or `negation` (destruction conditions), `dmad` explicitly builds a well-argued counter-position and forces genuine integration rather than simple error correction.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local dmad = require("dmad")
return dmad.run(ctx)
```

## Algorithm {#algorithm}

1. Thesis — generate the initial reasoned position.
2. Antithesis — construct the strongest opposing argument.
3. Rebuttal — the thesis side responds to the antithesis.
4. Synthesis — integrate valid points from both sides.

## References {#references}

- Du, Y. et al. (2023). "Improving Factuality and Reasoning in
  Language Models through Multiagent Debate".
  https://arxiv.org/abs/2305.14325
- Hegelian dialectic methodology.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per thesis/antithesis/rebuttal (default 500) |
| `ctx.rounds` | number | optional | Number of thesis–antithesis exchange rounds (default 1) |
| `ctx.synth_tokens` | number | optional | Max tokens for the final synthesis (default 600) |
| `ctx.task` | string | **required** | Task or question to analyze (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final synthesis text; alias of result.synthesis for caller convenience |
| `antithesis` | string | — | Last antithesis produced (round N) |
| `debate_log` | array of shape { role: one_of("thesis", "antithesis", "rebuttal", "synthesis"), round: number, text: string } | — | Full dialectical transcript in chronological order (thesis → antithesis/rebuttal*rounds → synthesis) |
| `rounds` | number | — | Number of rounds actually executed |
| `synthesis` | string | — | Integrated position from the dialectic |
| `thesis` | string | — | Initial reasoned position (round 0) |
