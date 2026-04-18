---
name: reflexion
version: 0.1.0
category: refinement
result_shape: "shape { answer: string, best_score: number, best_trial: number, passed: boolean, reflections: array of string, total_llm_calls: number, total_trials: number, trials: array of shape { attempt: string, feedback: string, passed: boolean, reflection?: string, score: number, trial: number } }"
description: "Episodic memory self-improvement — learns from failed attempts via verbal reinforcement. Each new attempt references accumulated reflections on past failures. reflect polishes; reflexion learns."
source: reflexion/init.lua
generated: gen_docs (V0)
---

# reflexion — Episodic Memory Self-Improvement

> Iteratively attempts a task, evaluates the result, generates a natural language "reflection" from failures, and stores it in episodic memory. Subsequent attempts reference accumulated reflections to avoid repeating the same mistakes.

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.evaluator` | string | optional | Custom evaluation prompt |
| `ctx.gen_tokens` | number | optional | Max tokens per attempt (default: 500) |
| `ctx.max_trials` | number | optional | Maximum number of attempts (default: 3) |
| `ctx.reflect_tokens` | number | optional | Max tokens per reflection (default: 300) |
| `ctx.success_threshold` | number | optional | Score threshold to accept, 1-10 scale (default: 8) |
| `ctx.task` | string | **required** | The task to solve |
