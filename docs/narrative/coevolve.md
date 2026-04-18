---
name: coevolve
version: 0.1.0
category: exploration
result_shape: "shape { all_results: array of shape { answer: string, problem: shape { difficulty: string, round: number, text: string }, reason?: string, round: number, verdict: string }, answer: string, round_stats: array of shape { correct: number, difficulty_hint: string, problems: number, round: number, success_rate: number }, total_correct: number, total_partial: number, total_problems: number, total_wrong: number }"
description: "Challenger-Solver Co-evolution — adversarial self-play where Challenger generates problems at Solver's ability boundary and Solver evolves to solve them. Automatic search space expansion."
source: coevolve/init.lua
generated: gen_docs (V0)
---

# coevolve — Challenger-Solver Co-evolution

> Two LLM roles evolve together: Challenger generates problems at the edge of Solver's ability, Solver attempts to solve them. As Solver improves, Challenger generates harder problems. This adversarial co-evolution automatically expands the exploration space — unlike cooperative methods (panel, rstar) that work within a fixed problem scope.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.difficulty_target` | number | optional | Target success rate for calibration (default 0.5) |
| `ctx.problems_per_round` | number | optional | Problems Challenger generates per round (default 3) |
| `ctx.rounds` | number | optional | Co-evolution rounds (default 4) |
| `ctx.seed_problems` | array of string | optional | Initial problem set; if nil, LLM generates problems_per_round seeds |
| `ctx.solver_tokens` | number | optional | Max tokens for Solver responses (default 400) |
| `ctx.task` | string | **required** | The domain / problem to explore (required) |
