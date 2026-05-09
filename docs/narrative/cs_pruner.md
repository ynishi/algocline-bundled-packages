---
name: cs_pruner
version: 0.1.0
category: selection
result_shape: "shape { alive_count: number, alpha_per_side: number, best: string, best_index: number, best_score: number, candidates: array of string, cs_variant: string, delta: number, evaluations: number, kill_events: array of shape { candidate: number, mean: number, n: number }, n_candidates: number, n_dimensions: number, protect_events: array of shape { candidate: number, mean: number, n: number }, ranking: array of shape { alive: boolean, index: number, lcb: number, mean: number, n: number, radius: number, ucb: number, v_hat: number }, rounds: array of shape { candidate: number, dimension: number, dimension_name: string, iteration: number, mean_after: number, n_after: number, score: number, v_hat_after: number }, total_llm_calls: number }"
description: "Anytime-valid candidate pruning via empirical-Bernstein confidence sequences."
source: cs_pruner/init.lua
generated: gen_docs (V0)
---

# cs_pruner(CSPruner) — confidence-sequence partial-data candidate pruner

> Given N candidate answers and a D-dimensional rubric, the package evaluates `(candidate × dimension)` pairs incrementally and kills candidates whose anytime-valid upper confidence bound drops below the best surviving candidate's lower confidence bound.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [Theoretical foundations](#theoretical-foundations)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local cs_pruner = require("cs_pruner")
return cs_pruner.run(ctx)
```

## Algorithm {#algorithm}

1. Generate N candidates.
2. Round-robin over the D rubric dimensions. For each dimension `k`,
   for each alive candidate `i`, ask the judge to evaluate `i` on `k`
   and receive score `x ∈ [0, 1]`. Update `i`'s confidence sequence.
   After each update, recompute `best_lcb` and kill any candidate
   whose `ucb < best_lcb`.
3. Return the ranking of alive candidates by empirical mean.

## Caveats {#caveats}

Empirical-Bernstein Confidence Sequences are designed for sample
sizes in the hundreds to thousands (Howard et al. 2021 tune their
experiments at `t=500`). At small `N×D` scale (`N≈6`, `D≈20`) the
closed-form variants cannot separate even strong candidates due to a
variance-independent floor term in the radius:

```math
radius_floor(t) ≈ c·k₂·log(ζ/(α·log^s η)) / t
                 ≈ 0.43 at t=20 with N=6, δ=0.05
```

This means a mean gap of less than 0.86 (on a `[0, 1]` scale) is
mathematically impossible to detect at `t=20` with the
polynomial-stitched variant. Practical guidance:

- Small scale (`N×D ≤ 200`, `D ≤ 30`): set `layer2_halving=true` and
  rely on Successive Halving as the primary kill mechanism. CS acts
  only as a safety net that almost never fires.
- Medium scale (`N ≤ 10`, `D ∈ [30, 100]`): try `cs_variant="betting"`
  — the predictable plug-in EB CS is measurably tighter than the
  stitched variant in this region.
- Large scale (`D ≥ 100`): `polynomial_stitched` is appropriate;
  CS-driven kills become realistic.

## Theoretical foundations {#theoretical-foundations}

Three CS variants are bundled:

- `polynomial_stitched` — Howard, Ramdas, McAuliffe, Sekhon (2021),
  Theorem 1 eq.(10). Closed-form, robust, requires `t` in the
  hundreds to fire.
- `hoeffding` — canonical sub-Gaussian stitched form (Howard 2021
  eq.(10) with `c=0`), using worst-case variance `σ² = c²/4`.
  Strictly looser baseline.
- `betting` — predictable plug-in empirical-Bernstein CS from
  Waudby-Smith & Ramdas (JRSSB 2024), Theorem 2 eq.(13)-(15). Uses
  regularized predictable mean `μ̂_t = (1/2 + ΣX)/(t+1)` and
  `α = δ/N` (the Thm 2 bound is already two-sided).
- `kl` — Kaufmann-Cappé style KL-LUCB bounds.

Why confidence sequences rather than fixed-`n` CIs: the pruner judges
"kill or keep" on the fly while rubric scores arrive one dimension at
a time. A confidence sequence is time-uniform — it remains valid at
every stopping time without pre-committing to a horizon — so early
stop does not corrupt the error guarantee.

Why closed-form variants only: zero external dependencies. The full
hedged-capital betting CS (W-S&R Algorithm 1) is tighter still but
requires 1D root finding to invert the wealth process; the
predictable plug-in form sacrifices ~10-20% width for a closed form.

## Comparison with related packages {#comparison-with-related-packages}

- `ab_select` — no mid-flight kill. Thompson Sampling starves
  low-posterior candidates implicitly; explicitly avoids kill because
  fixed credible-bound thresholds are depth-dependent.
- `gumbel_search` — Sequential Halving (kill bottom half at fixed
  checkpoints). Batch, not anytime.
- `listwise_rank` — post-hoc full ranking, no early stop.
- `cs_pruner` — anytime-valid per-candidate kill via empirical
  Bernstein CS. Respects statistical guarantees on the kill
  probability uniformly over time.

## References {#references}

- Howard, S. R., Ramdas, A., McAuliffe, J., Sekhon, J. (2021).
  "Time-uniform, nonparametric, nonasymptotic confidence sequences".
  Annals of Statistics 49(2):1055-1080. https://arxiv.org/abs/1810.08240
- Waudby-Smith, I., Ramdas, A. (2024). "Estimating means of bounded
  random variables by betting". JRSS-B 86(1):1-27.
  https://arxiv.org/abs/2010.09686

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.aggregation` | string | optional | Only "scalarize" supported in v0.1 |
| `ctx.betting_lambda_max` | number | optional | Betting λ truncation (default: 0.5) |
| `ctx.betting_prior_var` | number | optional | Betting σ̂² prior (default: 0.25) |
| `ctx.bootstrap_m` | number | optional | Howard 2021 eq.(10) bootstrap time (default: 1.0) |
| `ctx.cs_variant` | string | optional | "polynomial_stitched" \| "hoeffding" \| "betting" \| "kl" (default: polynomial_stitched) |
| `ctx.delta` | number | optional | Overall error probability (default: 0.05) |
| `ctx.gen_tokens` | number | optional | Max tokens per candidate generation (default: 400) |
| `ctx.halving_checkpoints` | array of number | optional | Checkpoint n-values for layer-2 halving (default: {5,10,15}) |
| `ctx.halving_keep_ratio` | number | optional | Fraction kept at each halving (default: 0.5) |
| `ctx.halving_min_gap` | number | optional | Gap guard around the median (default: 0) |
| `ctx.layer2_halving` | boolean | optional | Enable Successive Halving as primary kill mechanism (default: false) |
| `ctx.min_n_before_kill` | number | optional | Warmup minimum before kills are considered |
| `ctx.n_candidates` | number | optional | Number of candidates (default: 6) |
| `ctx.rubric` | array of shape { criterion: string, name: string } | optional | Rubric dimensions (default: 20-dim binary) |
| `ctx.score_domain` | shape { max: number, min: number } | optional | Score range (default: {min=0,max=1}) |
| `ctx.stitching_eta` | number | optional | Howard 2021 eq.(10) epoch ratio (default: 2.0) |
| `ctx.stitching_s` | number | optional | Howard 2021 eq.(10) exponent (default: 1.4) |
| `ctx.task` | string | **required** | Problem statement |
| `ctx.weights` | array of number | optional | Per-dimension weights (default: uniform) |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `alive_count` | number | — |  |
| `alpha_per_side` | number | — | δ/(2N) for stitched/hoeffding/kl; δ/N for betting |
| `best` | string | — | Text of the best surviving candidate |
| `best_index` | number | — | 1-based index of the winner |
| `best_score` | number | — | Empirical mean of the winner |
| `candidates` | array of string | — | All generated candidate texts |
| `cs_variant` | string | — |  |
| `delta` | number | — |  |
| `evaluations` | number | — | Per-dimension evaluations performed |
| `kill_events` | array of shape { candidate: number, mean: number, n: number } | — | Elimination events (open shape; CS and layer2 events share candidate/n/mean) |
| `n_candidates` | number | — |  |
| `n_dimensions` | number | — |  |
| `protect_events` | array of shape { candidate: number, mean: number, n: number } | — | Layer-2 gap-guard protections (open shape) |
| `ranking` | array of shape { alive: boolean, index: number, lcb: number, mean: number, n: number, radius: number, ucb: number, v_hat: number } | — | All candidates sorted by alive, then mean descending |
| `rounds` | array of shape { candidate: number, dimension: number, dimension_name: string, iteration: number, mean_after: number, n_after: number, score: number, v_hat_after: number } | — | Per-evaluation trace |
| `total_llm_calls` | number | — |  |
