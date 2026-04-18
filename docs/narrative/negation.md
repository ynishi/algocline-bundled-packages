---
name: negation
version: 0.1.0
category: validation
result_shape: "shape { answer: string, conditions: array of shape { condition: string, raw: string, reasoning: string, verdict: string }, holding: number, initial_answer?: string, refuted: number, revised: boolean, survived: boolean, total: number }"
description: "Adversarial self-test — generate destruction conditions and verify answer survival"
source: negation/init.lua
generated: gen_docs (V0)
---

# negation — Adversarial self-test via destruction conditions

> Given an answer, generates "destruction conditions": specific scenarios or facts that, if true, would invalidate the answer. Then attempts to verify whether any destruction condition actually holds. Surviving answers are strengthened; refuted answers are revised.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.answer` | string | optional | Pre-supplied answer to test (auto-generated if nil) |
| `ctx.gen_tokens` | number | optional | Max tokens for generation / condition listing (default: 600) |
| `ctx.max_conditions` | number | optional | Max destruction conditions to generate (default: 5) |
| `ctx.revise_tokens` | number | optional | Max tokens for revision (default: 600) |
| `ctx.task` | string | **required** | The task/question to solve |
| `ctx.verify_tokens` | number | optional | Max tokens per condition verification (default: 200) |
