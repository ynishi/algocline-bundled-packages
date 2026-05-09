---
name: reflexion
version: 0.1.0
category: refinement
result_shape: "shape { answer: string, best_score: number, best_trial: number, passed: boolean, reflections: array of string, total_llm_calls: number, total_trials: number, trials: array of shape { attempt: string, feedback: string, passed: boolean, reflection?: string, score: number, trial: number } }"
description: "Episodic memory self-improvement — learns from failed attempts via verbal reinforcement. Each new attempt references accumulated reflections on past failures. reflect polishes; reflexion learns."
source: reflexion/init.lua
generated: gen_docs (V0)
---

# reflexion(Reflexion) — episodic-memory self-improvement

> Iteratively attempts a task, evaluates the result, generates a natural-language "reflection" from failures, and stores it in episodic memory. Subsequent attempts reference accumulated reflections to avoid repeating the same mistakes.

## Contents

- [Usage](#usage)
- [Comparison with related packages](#comparison-with-related-packages)
- [Empirical validation](#empirical-validation)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local rfx = require("reflexion")
return rfx.run(ctx)
```

## Comparison with related packages {#comparison-with-related-packages}

- `reflect` — Generate → Critique → Revise within a single attempt;
  each round improves the current draft, no cross-attempt memory.
  Metaphor: proofreading and editing a paper.
- `reflexion` — multiple independent attempts, each informed by
  reflections on previous failures stored in episodic memory.
  Metaphor: retaking an exam after studying your mistakes.

`reflect` polishes a single output (local optimization);
`reflexion` explores fundamentally different approaches informed by
past failures (global search with memory).

## Empirical validation {#empirical-validation}

- HumanEval: 67% → 91%.
- AlfWorld: 134/134 tasks.

## References {#references}

- Shinn, N. et al. (2023). "Reflexion: Language Agents with Verbal
  Reinforcement Learning". NeurIPS 2023.
  https://arxiv.org/abs/2303.11366
ctx.reflect_tokens: Max tokens per reflection (default: 300)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.evaluator` | string | optional | Custom evaluation prompt |
| `ctx.gen_tokens` | number | optional | Max tokens per attempt (default: 500) |
| `ctx.max_trials` | number | optional | Maximum number of attempts (default: 3) |
| `ctx.reflect_tokens` | number | optional | Max tokens per reflection (default: 300) |
| `ctx.success_threshold` | number | optional | Score threshold to accept, 1-10 scale (default: 8) |
| `ctx.task` | string | **required** | The task to solve |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `answer` | string | — | Best attempt across all trials |
| `best_score` | number | — | Score of the best-scoring attempt |
| `best_trial` | number | — | 1-based index of the best trial |
| `passed` | boolean | — | Whether the final trial passed the threshold |
| `reflections` | array of string | — | Accumulated episodic memory (one per failed trial except the last) |
| `total_llm_calls` | number | — | Total alc.llm invocations across trials |
| `total_trials` | number | — | Number of trials executed |
| `trials` | array of shape { attempt: string, feedback: string, passed: boolean, reflection?: string, score: number, trial: number } | — | Ordered trial records with score, feedback, and optional reflection |
