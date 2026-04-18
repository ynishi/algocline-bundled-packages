---
name: blind_spot
version: 0.1.0
category: correction
result_shape: "shape { answer: string, corrections_detected: number, history: array of shape { role: string, round: number, text: string }, initial_answer: string, rounds: number, wait_applied: boolean }"
description: "Self-Correction Blind Spot bypass — re-present own output as external source to trigger genuine error correction"
source: blind_spot/init.lua
generated: gen_docs (V0)
---

# blind_spot — Self-Correction Blind Spot bypass

> LLMs cannot correct errors in their own outputs but can successfully correct identical errors when presented as coming from external sources. This package exploits that asymmetry: generate an answer, then re-present it as a "colleague's draft" for the same LLM to review and correct.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.correct_tokens` | number | optional | Max tokens per correction / reflection (default: 800) |
| `ctx.gen_tokens` | number | optional | Max tokens for initial generation (default: 600) |
| `ctx.rounds` | number | optional | Externalize→correct rounds (default: 1) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.wait` | boolean | optional | Enable 'Wait' reflection trigger (default: true) |
