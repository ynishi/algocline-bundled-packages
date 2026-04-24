---
name: particle_infer
version: 0.1.0
category: selection
result_shape: particle_inferred
description: "Particle-Filter inference-time scaling (Puri et al. 2025, arXiv:2502.01618). State-Space formulation of LLM generation with PRM-guided every-step softmax resampling and ORM-based final selection. N step-wise rollouts; caller-injected prm_fn (Process Reward Model) and optional orm_fn (Outcome Reward Model) drive Theorem-1 unbiased posterior sampling. Qwen2.5-Math-1.5B + 4 particles > GPT-4o (paper §4.2). Default (N=8, max_steps=8) issues up to N·max_steps LLM calls and N·max_steps PRM calls."
source: particle_infer/init.lua
generated: gen_docs (V0)
---

# particle_infer — Particle-Filter inference-time scaling for LLMs.

> Based on: Puri, Sudalairaj, Xu, Xu, Srivastava   "A Probabilistic Inference Approach to Inference-Time Scaling    of LLMs using Particle-Based Monte Carlo Methods"   (aka Rollout Roulette, arXiv:2502.01618, 2025-02).

## Contents

- [Parameters](#parameters)

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.aggregation` | one_of("product", "min", "last", "model") | optional | PRM step→scalar reduction (§3.2). Default 'product'. |
| `ctx.auto_card` | boolean | optional | Emit a Card on completion (default false) |
| `ctx.card_pkg` | string | optional | Card pkg.name override (default 'particle_infer_<task_hash>') |
| `ctx.continue_fn` | any | optional | OPTIONAL. Per-particle stop predicate. fn(partial_answer) → boolean. Default: max_steps-only termination. |
| `ctx.ess_threshold` | number | optional | 0.0 (default) = every-step resample (paper-faithful). > 0 switches to ESS-triggered resample (NOT paper-faithful). |
| `ctx.final_selection` | one_of("orm", "argmax_weight", "weighted_vote") | optional | Paper uses 'orm'. 'weighted_vote' is NOT paper-faithful. |
| `ctx.gen_tokens_step` | number | optional | Tokens per step LLM call (default 200) |
| `ctx.llm_temperature` | number | optional | LLM sampling temperature (default 0.8) |
| `ctx.max_steps` | number | optional | T cap (default 8) |
| `ctx.n_particles` | number | optional | N (default 8, paper §4.4) |
| `ctx.orm_fn` | any | optional | OPTIONAL. Outcome Reward Model for final selection (paper §3 end). fn(final_answer, task) → ℝ. Falls back to argmax-weight selection when nil. |
| `ctx.prm_fn` | any | **required** | REQUIRED. Process Reward Model. fn(partial_answer, task) → r ∈ [0, 1]. Called N × max_steps times. Runtime type-checked. |
| `ctx.scenario_name` | string | optional | Explicit scenario name for emitted Card |
| `ctx.softmax_temp` | number | optional | Softmax temperature T in softmax(w/T). Paper Alg.1 default 1.0. |
| `ctx.task` | string | **required** | Problem statement fed to LLM + prm_fn + orm_fn |
