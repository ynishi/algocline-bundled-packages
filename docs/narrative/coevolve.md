---
name: coevolve
version: 0.1.0
category: exploration
result_shape: "shape { all_results: array of shape { answer: string, problem: shape { difficulty: string, round: number, text: string }, reason?: string, round: number, verdict: string }, answer: string, round_stats: array of shape { correct: number, difficulty_hint: string, problems: number, round: number, success_rate: number }, total_correct: number, total_partial: number, total_problems: number, total_wrong: number }"
description: "Challenger-Solver co-evolution self-play that auto-expands the search space."
source: coevolve/init.lua
generated: gen_docs (V0)
---

# coevolve(Coevolve) — challenger-solver co-evolution self-play

> Two LLM roles evolve together: the Challenger generates problems at the edge of the Solver's ability and the Solver attempts to solve them. As the Solver improves, the Challenger generates harder problems. The adversarial co-evolution automatically expands the exploration space, unlike cooperative methods (`panel`, `rstar`) that work within a fixed scope.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local coevolve = require("coevolve")
return coevolve.run(ctx)
```

## Algorithm {#algorithm}

1. Seed an initial problem set (provided or auto-generated).
2. For each of `rounds`:
   - Solve each problem with the Solver.
   - Analyze success and failure patterns.
   - Challenger generates new problems targeting weaknesses.
   - Calibrate difficulty based on the success rate.
3. Solver answers the original task using accumulated skill.

## References {#references}

- Singh, ... et al. (2025). "Self-Play for LLM Reasoning:
  Challenger-Solver Co-evolution". https://arxiv.org/abs/2510.27072
- Faldor, M. et al. (2025). "OMNI-EPIC: Open-endedness via Models of
  human Notions of Interestingness". ICLR 2025.
  https://arxiv.org/abs/2405.15568
- Sukhbaatar, S. et al. (2018). "Intrinsic Motivation and Automatic
  Curricula via Asymmetric Self-Play". ICLR 2018.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.difficulty_target` | number | optional | Target success rate for calibration (default 0.5) |
| `ctx.problems_per_round` | number | optional | Problems Challenger generates per round (default 3) |
| `ctx.rounds` | number | optional | Co-evolution rounds (default 4) |
| `ctx.seed_problems` | array of string | optional | Initial problem set; if nil, LLM generates problems_per_round seeds |
| `ctx.solver_tokens` | number | optional | Max tokens for Solver responses (default 400) |
| `ctx.task` | string | **required** | The domain / problem to explore (required) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `all_results` | array of shape { answer: string, problem: shape { difficulty: string, round: number, text: string }, reason?: string, round: number, verdict: string } | — | Full trace of every solve attempt |
| `answer` | string | — | Final synthesis answer using accumulated skill from all rounds |
| `round_stats` | array of shape { correct: number, difficulty_hint: string, problems: number, round: number, success_rate: number } | — | Per-round statistics (length = rounds) |
| `total_correct` | number | — | Total CORRECT verdicts |
| `total_partial` | number | — | Total PARTIAL verdicts |
| `total_problems` | number | — | Total problems attempted across all rounds |
| `total_wrong` | number | — | Total WRONG verdicts |
