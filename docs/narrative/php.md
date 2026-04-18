---
name: php
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, conclusion: string, converged: boolean, rounds: array of shape { answer: string, conclusion: string, hint_used: boolean, round: number }, total_rounds: number }"
description: "Progressive-Hint Prompting — iterative re-solving with prior answers as hints"
source: php/init.lua
generated: gen_docs (V0)
---

# PHP — Progressive-Hint Prompting

> Iteratively re-solves the problem using previous answers as hints. Each round feeds the prior answer back as a "hint", allowing the model to self-correct by building on (or departing from) its previous attempt. Converges when two consecutive answers agree.

## Contents

- [Parameters](#parameters)
- [Result](#result)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_rounds` | number | optional | Maximum hint-retry cycles (default: 4) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Final answer at convergence (or last round) |
| `conclusion` | string | — | Extracted core conclusion of the final answer |
| `converged` | boolean | — | True iff the last two rounds' conclusions match |
| `rounds` | array of shape { answer: string, conclusion: string, hint_used: boolean, round: number } | — | Per-round execution record |
| `total_rounds` | number | — | Total rounds actually executed |
