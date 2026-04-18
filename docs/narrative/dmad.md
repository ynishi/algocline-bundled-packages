---
name: dmad
version: 0.1.0
category: reasoning
result_shape: "shape { answer: string, antithesis: string, debate_log: array of shape { role: one_of(\"thesis\", \"antithesis\", \"rebuttal\", \"synthesis\"), round: number, text: string }, rounds: number, synthesis: string, thesis: string }"
description: "Dialectical reasoning — thesis, antithesis, and synthesis for deeper analysis"
source: dmad/init.lua
generated: gen_docs (V0)
---

# dmad — Dialectical reasoning (thesis → antithesis → synthesis)

> Applies the Hegelian dialectic to LLM reasoning: first generates a thesis (initial position), then constructs the strongest possible antithesis (opposing position), and finally produces a synthesis that integrates valid points from both sides.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.gen_tokens` | number | optional | Max tokens per thesis/antithesis/rebuttal (default 500) |
| `ctx.rounds` | number | optional | Number of thesis–antithesis exchange rounds (default 1) |
| `ctx.synth_tokens` | number | optional | Max tokens for the final synthesis (default 600) |
| `ctx.task` | string | **required** | Task or question to analyze (required) |
