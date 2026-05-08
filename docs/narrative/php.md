---
name: php
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, conclusion: string, converged: boolean, rounds: array of shape { answer: string, conclusion: string, hint_used: boolean, round: number }, total_rounds: number }"
description: "Progressive-Hint Prompting — iterative re-solving with prior answers as hints"
source: php/init.lua
generated: gen_docs (V0)
---

# php(PHP) — iteratively re-solves problems using prior answers as hints

> Iteratively re-solves the problem using previous answers as hints. Each round feeds prior answer conclusions back as hints, allowing the model to self-correct by building on (or departing from) its previous attempt. Converges when two consecutive rounds produce matching conclusions.

## Contents

- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

Given a task, PHP performs the following steps:

1. Round 1 — initial solve: the model solves the task from scratch with no
   hints. A conclusion is extracted from the full answer.
2. Rounds 2–N — hint-guided re-solve: all previous conclusions are
   concatenated as hints. The model re-solves the task, either confirming
   or correcting its prior reasoning.
3. Convergence check: after each round, the current conclusion is compared
   to the previous one via a separate LLM call. If they match (`SAME`),
   the loop terminates early.
4. Termination: stops at convergence or when `max_rounds` is exhausted.

## Theoretical foundations {#theoretical-foundations}

Zheng et al. (2023) show that feeding prior answers as hints narrows the
hypothesis space and guides the model toward a stable fixpoint. Empirically,
PHP improves arithmetic and multi-step reasoning accuracy over self-consistency
baselines because hints act as soft constraints that reduce exploration variance.

## Usage {#usage}

```lua
local php = require("php")
return php.run(ctx)
```

## References {#references}

- Zheng, Cai, Chen, Liu (2023). "Progressive-Hint Prompting Improves Reasoning
  in Large Language Models". arXiv:2304.09797.
  https://arxiv.org/abs/2304.09797

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
