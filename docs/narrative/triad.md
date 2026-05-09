---
name: triad
version: 0.1.0
category: adversarial
result_shape: "shape { total_rounds: number, transcript: array of shape { opponent: string, proponent: string, round: number }, verdict: string, winner: string }"
description: "Adversarial 3-role debate — proponent/opponent/judge with multi-round argumentation"
source: triad/init.lua
generated: gen_docs (V0)
---

# triad(Triad) — adversarial 3-role debate with judge arbitration

> Three distinct roles: Proponent (argues for), Opponent (argues against), and Judge (arbitrates). Multiple rounds of attack and defense, then a final verdict.

## Contents

- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local triad = require("triad")
return triad.run(ctx)
```

## References {#references}

- Du, Y. et al. (2023). "Improving Factuality and Reasoning in
  Language Models through Multiagent Debate".
  https://arxiv.org/abs/2305.14325

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per argument (default: 400) |
| `ctx.judge_tokens` | number | optional | Max tokens for final verdict (default: 500) |
| `ctx.rounds` | number | optional | Number of debate rounds after opening (default: 3) |
| `ctx.task` | string | **required** | The question or claim to debate |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `total_rounds` | number | — | Number of rebuttal rounds (excludes opening) |
| `transcript` | array of shape { opponent: string, proponent: string, round: number } | — | Full debate transcript including opening |
| `verdict` | string | — | Full verdict text from the judge |
| `winner` | string | — | Parsed winner token ("proponent"\|"opponent"\|"draw"\|"unknown") |
