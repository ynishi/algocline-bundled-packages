---
name: cumulative
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, established_facts: array of shape { proposition: string, round: number }, rounds: array of shape { proposed: array of string, round: number, verified: array of shape { accepted: boolean, proposition: string, verification: string } }, total_established: number, total_rounds: number }"
description: "Cumulative Reasoning — proposer/verifier/reporter loop with fact accumulation"
source: cumulative/init.lua
generated: gen_docs (V0)
---

# cumulative — propose-verify-accumulate reasoning

> Three roles (proposer, verifier, reporter) collaborate in a loop. The proposer generates new propositions, the verifier checks them, and verified propositions accumulate as established facts for the next round.

## Contents

- [Algorithm](#algorithm)
- [Theoretical foundations](#theoretical-foundations)
- [Usage](#usage)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Algorithm {#algorithm}

1. Proposer generates `propositions_per_round` candidate propositions,
   each conditioned on the current established-facts context.
2. Verifier independently assesses each proposition for logical soundness
   and consistency with established facts; accepted propositions are appended.
3. Early-termination check: if `#established >= 3` and the LLM judges
   facts sufficient, the loop exits before `max_rounds`.
4. Reporter synthesises all established facts into a final answer.

## Theoretical foundations {#theoretical-foundations}

Implements the Cumulative Reasoning framework of Zhang et al. (2024).
The key invariant is monotone fact accumulation: only propositions
confirmed by an independent verifier are added to the established set,
preventing hallucinated facts from propagating across rounds.

## Usage {#usage}

```lua
local cumulative = require("cumulative")
return cumulative.run(ctx)
```

## References {#references}

- Zhang, Y., Zhang, Y., Li, Y., Smola, A. (2024). "Cumulative Reasoning
  with Large Language Models". arXiv:2308.04371.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_rounds` | number | optional | Max propose-verify cycles (default: 4) |
| `ctx.propositions_per_round` | number | optional | Propositions generated per round (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Reporter's synthesis grounded in established facts |
| `established_facts` | array of shape { proposition: string, round: number } | — | Verified propositions accumulated across rounds |
| `rounds` | array of shape { proposed: array of string, round: number, verified: array of shape { accepted: boolean, proposition: string, verification: string } } | — | Per-round propose/verify trace |
| `total_established` | number | — | Count of verified propositions |
| `total_rounds` | number | — | Number of rounds actually executed (may be < max_rounds due to early termination) |
