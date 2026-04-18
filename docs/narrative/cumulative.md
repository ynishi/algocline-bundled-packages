---
name: cumulative
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, established_facts: array of shape { proposition: string, round: number }, rounds: array of shape { proposed: array of string, round: number, verified: array of shape { accepted: boolean, proposition: string, verification: string } }, total_established: number, total_rounds: number }"
description: "Cumulative Reasoning — proposer/verifier/reporter loop with fact accumulation"
source: cumulative/init.lua
generated: gen_docs (V0)
---

# Cumulative — propose-verify-accumulate reasoning

> Three roles (proposer, verifier, reporter) collaborate in a loop. The proposer generates new propositions, the verifier checks them, and verified propositions accumulate as established facts for the next round.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.max_rounds` | number | optional | Max propose-verify cycles (default: 4) |
| `ctx.propositions_per_round` | number | optional | Propositions generated per round (default: 2) |
| `ctx.task` | string | **required** | The problem to solve |
