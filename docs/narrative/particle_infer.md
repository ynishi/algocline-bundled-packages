---
name: particle_infer
version: 0.1.0
category: selection
result_shape: particle_inferred
description: "Particle-filter inference-time scaling with PRM-guided softmax resampling."
source: particle_infer/init.lua
generated: gen_docs (V0)
---

# particle_infer(ParticleInfer) — particle-filter inference-time scaling for LLMs

> Implements the paper's §3.1 Algorithm 1 single-chain Particle Filter under a State-Space-Model formulation of LLM generation. N rollouts (particles) are advanced one step at a time; a caller-injected Process Reward Model (PRM) scores each step; the particles are resampled at every step via `softmax(w)`; an optional Outcome Reward Model (ORM) picks the final answer.

## Contents

- [Usage](#usage)
- [Theoretical foundations](#theoretical-foundations)
- [Injection points](#injection-points)
- [Caveats](#caveats)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)

## Usage {#usage}

```lua
local pi = require("particle_infer")
return pi.run({
    task     = "Solve: ...",
    prm_fn   = function(partial, task)
        return my_prm(partial, task)  -- Bernoulli prob of "on track"
    end,
    orm_fn   = function(final, task)
        return my_orm(final, task)    -- final-answer quality scalar
    end,
    -- weight_scheme = "logit_replace"  -- opt-in for its_hub compat
})
```

## Theoretical foundations {#theoretical-foundations}

Paper-faithful core formulas (§2 + §3.1 Alg.1 + Theorem 1):

```math
p̂_M(x_{1:T}, o_{1:T} | c)
  ∝ ∏_t p_M(x_t | c, x_{<t}) · ∏_t p̂(o_t | c, x_{<t})
p̂(o_t | c, x_{<t}) = Bern(o_t; r̂(c, x_{<t}))
w  = [r̂(x_{1:t}^(1)), …, r̂(x_{1:t}^(N))]
θ_t = softmax(w) = r̂_i / Σ_j r̂_j
{j_t⁽ⁱ⁾} ~ Multinomial(θ_t); particles ← {x_{1:t}⁽ʲₜ⁽ⁱ⁾⁾}
w_t⁽ⁱ⁾ ∝ w_{t-1}⁽ⁱ⁾ · r̂(c, x_{<t}⁽ⁱ⁾)
p̂_M(x_{1:T}|c, o_{1:T}=1) ∝ ∏_t p_M(x_t|…) · ∏_t r̂_t
î = argmax_i ORM(x_{1:T}⁽ⁱ⁾, c)
```

Under every-step resampling, weights reset to uniform, reducing the
accumulated form to `w_t ∝ r̂_t`. Under `softmax(log r̂_t)` this
gives `θ_i = r̂_i / Σ_j r̂_j`, matching Theorem 1's target. This is
the default `weight_scheme = "log_linear"`.

The reference implementation (its_hub `particle_gibbs.py`) instead
uses `logit(r̂) = log(r̂/(1-r̂))` and `softmax(logit(r̂)) =
(r̂/(1-r̂)) / Σ` — the odds-normalized distribution, not `r̂/Σr̂`.
This is a different target distribution; Theorem 1's unbiasedness
proof does not cover it. The sharp "kill-the-runt" concentration in
paper Figure 4 (N=4..128) arises from the odds divergence
(`r̂ → 1 ⇒ logit → ∞`), not from the SSM posterior. Exposed as
opt-in `weight_scheme = "logit_replace"` for ref-impl compatibility.

## Injection points {#injection-points}

Paper-faithful defaults (paper §3.1 Alg.1):

- Weight scheme `log_linear` (`w_t = log r̂_t`, `θ ∝ r̂_t`).
- Resampling every step (`ess_threshold = 0.0`).
- Softmax temperature `T = 1`.
- LLM temperature `0.8` (paper §4.5 ablation default).
- Aggregation `product` (paper §3.2 default).
- Final selection `orm` when `orm_fn` is provided.

REQUIRED:

- `prm_fn` — Process Reward Model. `fn(partial_answer, task) →
  r ∈ [0, 1]` (Bernoulli parameter, paper §2 emission). Called
  `N × steps` times. Non-number / NaN / out-of-range returns are
  fail-fast errors.

OPTIONAL paper-faithful:

- `orm_fn` — Outcome Reward Model for final selection (paper §3
  end). `fn(final_answer, task) → ℝ`. Absent: falls back to
  argmax-weight selection.
- `continue_fn` — per-particle stop predicate.
  `fn(partial_answer) → boolean`. Default: stop when `max_steps`
  reached.
- `aggregation` — `{"product","min","last","model"}` (paper §3.2).
  Affects only the reported `aggregated` scalar per particle, not
  resampling. `model` requires a full-prefix-capable PRM.
- `llm_temperature` / `gen_tokens_step` / `n_particles` /
  `max_steps` — budget / stochasticity knobs (paper §4 setups).

OPTIONAL non-paper-faithful:

- `weight_scheme = "logit_replace"` — its_hub ref-impl numerics.
  Theorem 1 unbiasedness proof does not cover this path.
- `ess_threshold > 0` — switch from every-step resample to
  ESS-triggered. Not in paper Alg.1.
- `final_selection = "weighted_vote"` — paper uses ORM-argmax; this
  path aggregates weights by answer. Useful when `orm_fn` is absent.
- `softmax_temp ≠ 1` — Alg.1 uses `T = 1`; other values are
  heuristic.

## Caveats {#caveats}

Out of scope for v1: Algorithm 2 (Particle Gibbs with pinned
reference particle), Algorithm 3 (Particle Gibbs + Parallel
Tempering across `M` chains), and full-prefix PRM auto-detection
(delegated to the caller's `prm_fn`).

v0.1.0 migration: default `weight_scheme` changed from effective
`logit_replace` (implicit) to `log_linear` (paper-faithful). Callers
relying on its_hub reference-impl numerics must add
`weight_scheme = "logit_replace"` explicitly.

## Comparison with related packages {#comparison-with-related-packages}

Category: selection (alongside `sc`, `smc_sample`, `gumbel_search`,
`mbr_select`, `ab_select`). Complements `smc_sample` (whole-answer
block-SMC) by occupying the step-wise trajectory tier.

## References {#references}

- Puri, ..., Sudalairaj, ..., Xu, ..., Srivastava, ... (2025).
  "A Probabilistic Inference Approach to Inference-Time Scaling of
  LLMs using Particle-Based Monte Carlo Methods" (Rollout Roulette).
  https://arxiv.org/abs/2502.01618
- Reference implementation:
  github.com/Red-Hat-AI-Innovation-Team/its_hub

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
| `ctx.weight_scheme` | one_of("log_linear", "logit_replace") | optional | Per-step weight formula. 'log_linear' (default, paper-faithful): w_t = log(r̂_t), θ ∝ r̂_t (paper §3.1 Alg.1 + Theorem 1). 'logit_replace' (NOT paper-faithful, its_hub ref-impl compat): w_t = logit(r̂_t), θ ∝ r̂_t/(1-r̂_t). |
