---
name: triad
version: 0.1.0
category: adversarial
result_shape: "shape { total_rounds: number, transcript: array of shape { opponent: string, proponent: string, round: number }, verdict: string, winner: string }"
description: "Adversarial 3-role debate — proponent/opponent/judge with multi-round argumentation"
source: triad/init.lua
generated: gen_docs (V0)
---

# Triad — adversarial 3-role debate with judge arbitration

> Three distinct roles: Proponent (argues for), Opponent (argues against), Judge (arbitrates). Multiple rounds of attack/defense, then final verdict.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per argument (default: 400) |
| `ctx.judge_tokens` | number | optional | Max tokens for final verdict (default: 500) |
| `ctx.rounds` | number | optional | Number of debate rounds after opening (default: 3) |
| `ctx.task` | string | **required** | The question or claim to debate |
