---
name: reflect
version: 0.1.0
category: refinement
result_shape: "shape { converged: boolean, output: string, rounds: array of shape { converged: boolean, critique: string, round: number }, total_rounds: number }"
description: "Self-critique loop — generate, critique, revise until convergence"
source: reflect/init.lua
generated: gen_docs (V0)
---

# Reflect — self-critique and iterative refinement

> Generate → Critique → Revise loop. The same LLM critiques its own output and refines until convergence or max rounds.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.critique_tokens` | number | optional | Max tokens for critique (default: 300) |
| `ctx.gen_tokens` | number | optional | Max tokens for generation (default: 500) |
| `ctx.initial_draft` | string | optional | Pre-generated draft to refine (skips initial LLM generation) |
| `ctx.max_rounds` | number | optional | Maximum critique-revise cycles (default: 3) |
| `ctx.stop_when` | string | optional | Stop condition: 'no_major_issues' or 'no_issues' (default: 'no_major_issues') |
| `ctx.task` | string | **required** | The task to perform |
