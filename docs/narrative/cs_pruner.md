---
name: cs_pruner
version: 0.1.0
category: selection
description: "Confidence-sequence partial-data pruner. Anytime-valid per-candidate kill using empirical-Bernstein CS (Howard et al. 2021). Evaluates candidates across a multi-dimensional rubric and kills each one as soon as its upper confidence bound drops below the best survivor's lower bound. Strategic/Injectable — every parameter is overridable."
source: cs_pruner/init.lua
generated: gen_docs (V0)
---

# cs_pruner — Confidence-Sequence Partial-Data Pruner

> Given N candidate answers and a D-dimensional rubric, this package evaluates (candidate × dimension) pairs incrementally and KILLS candidates whose anytime-valid upper confidence bound drops below the best surviving candidate's lower confidence bound.

## Contents

  - [Operating regime — READ FIRST](#operating-regime-read-first)
  - [Theoretical foundations](#theoretical-foundations)

### Operating regime — READ FIRST {#operating-regime-read-first}

Empirical-Bernstein Confidence Sequences are designed for sample
sizes in the **hundreds to thousands** (Howard et al. 2021 tune their
experiments at t=500). At small N×D scale (N≈6, D≈20) the closed-form
variants here CANNOT separate even strong candidates due to a
variance-independent floor term in the radius:

  radius_floor(t) ≈ c·k₂·log(ζ/(α·log^s η)) / t
                  ≈ 0.43 at t=20 with N=6, δ=0.05

This means a mean-gap of < 0.86 (on a [0,1] scale) is mathematically
impossible to detect at t=20 with the polynomial-stitched variant.
See workspace/cs_pruner_root_cause.md for the full derivation and
workspace/cs_pruner_firing_run{1,2}.md for empirical confirmation.

Practical guidance:
  * **Small scale (N×D ≤ 200, D ≤ 30):** Set layer2_halving=true and
    rely on Successive Halving as the primary kill mechanism. CS acts
    only as a safety net that almost never fires.
  * **Medium scale (N≤10, D∈[30,100]):** Try cs_variant="betting" —
    the predictable plug-in EB CS (Waudby-Smith & Ramdas 2024) is
    measurably tighter than the stitched variant in this region.
  * **Large scale (D≥100):** polynomial_stitched is appropriate;
    CS-driven kills become realistic.

### Theoretical foundations {#theoretical-foundations}

Three CS variants are bundled:

  "polynomial_stitched"  Howard, Ramdas, McAuliffe, Sekhon 2021,
                         Theorem 1 eq.(10). Closed-form, robust,
                         requires t in the hundreds to fire.
  "hoeffding"            Canonical sub-Gaussian stitched form
                         (Howard 2021 eq.(10) with c=0), using
                         worst-case variance σ²=c²/4. Strictly
                         looser baseline.
  "betting"              Predictable plug-in empirical-Bernstein CS
                         from Waudby-Smith & Ramdas (JRSSB 2024,
                         arXiv:2010.09686, Theorem 2 eq.(13)-(15)).
                         Uses regularized predictable mean
                         μ̂_t = (1/2+ΣX)/(t+1) and α = δ/N (the
                         Thm2 bound is already two-sided).
  "kl"                   Kaufmann-Cappé style KL-LUCB bounds.

Why confidence sequences rather than fixed-n CIs:
  The pruner judges "kill or keep" on-the-fly while rubric scores
  arrive one dimension at a time. A confidence sequence is
  time-uniform — it remains valid at every stopping time without
  pre-committing to a horizon — so early-stop without corrupting
  the error guarantee.

Why closed-form variants only: zero external dependencies. The full
hedged-capital betting CS (W-S&R Algorithm 1) is tighter still but
requires 1D root finding to invert the wealth process; the
predictable plug-in form sacrifices ~10-20% width for closed form.

Key difference from ab_select / gumbel_search / listwise_rank:
  ab_select      — NO mid-flight kill. Thompson sampling starves
                   low-posterior candidates implicitly. Explicitly
                   avoids kill because fixed credible-bound thresholds
                   are depth-dependent.
  gumbel_search  — Sequential Halving: "kill bottom half at fixed
                   checkpoints". Batch, not anytime.
  listwise_rank  — post-hoc full ranking, no early stop.
  cs_pruner      — anytime-valid per-candidate kill via empirical
                   Bernstein CS. Respects statistical guarantees on
                   the kill probability uniformly over time.

Algorithm:
  1. Generate N candidates.
  2. Round-robin over D rubric dimensions. For each dimension k:
     for each alive candidate i, ask the judge to evaluate
     candidate i on dimension k and receive score x ∈ [0, 1].
     Update candidate i's CS. After each update, recompute
     best_lcb and kill any candidate whose ucb < best_lcb.
  3. Return ranking of alive candidates by empirical mean.

Usage:
  local cs_pruner = require("cs_pruner")
  return cs_pruner.run(ctx)

Parameters (all Strategic / Injectable):
  ctx.task (required)              Problem statement
  ctx.n_candidates (default 6)     Number of candidates
  ctx.rubric (default 20-dim)      List of {name, criterion} dimensions
  ctx.delta (default 0.05)         Overall error probability upper bound
  ctx.cs_variant                   "polynomial_stitched" | "hoeffding"
                                   | "betting" | "kl"
                                   (default "polynomial_stitched")
                                   See "Operating regime" above.
  ctx.betting_lambda_max           Betting λ truncation (default 0.5,
                                   WSR 2024 §B "reasonable default 1/2 or 3/4").
  ctx.betting_prior_var            Betting σ̂² prior (default 0.25 = 1/4,
                                   worst-case variance on [0,1]).
  ctx.score_domain                 { min, max } (default { 0, 1 })
  ctx.stitching_s (default 1.4)    Howard 2021 eq.(10) exponent
  ctx.stitching_eta (default 2.0)  Howard 2021 eq.(10) epoch ratio
  ctx.bootstrap_m (default 1.0)    Howard 2021 eq.(10) bootstrap time
  ctx.aggregation (default         Only "scalarize" is supported.
                  "scalarize")     Any other value is rejected at run time.
  ctx.weights (default nil)        Per-dimension weights, nil = uniform
  ctx.eval_order                   "round_robin" | "sequential" |
                                   function(state) -> (cand_i, dim_k)
                                   (default "round_robin")
  ctx.layer2_halving               true | false (default false)
  ctx.halving_checkpoints          list of n values (default {5, 10, 15})
  ctx.halving_keep_ratio (0.5)     Fraction kept at each halving
  ctx.halving_min_gap (0)          Gap guard. A candidate in the bottom
                                   slice is PROTECTED (not killed) if its
                                   mean is within min_gap of the median
                                   of alive candidates. Mitigates the
                                   noise-driven false-kill failure mode at
                                   low n. Recommended: 0.1-0.2 on a [0,1]
                                   scale. See workspace/cs_pruner_firing_run2.md.
  ctx.on_kill                      function(candidate_index, state)
  ctx.on_survive                   function(candidate_index, state)
  ctx.gen_tokens (default 400)     Max tokens per candidate generation
  ctx.min_n_before_kill            Warmup minimum (default 3 for
                                   stitched/hoeffding/betting, 5 for
                                   cs_variant="kl"). KL bounds can
                                   fire spuriously at n≤4 with binary
                                   PASS/FAIL scores.

Based on:
  Howard, Ramdas, McAuliffe, Sekhon (2021)
    "Time-uniform, nonparametric, nonasymptotic confidence sequences"
    Annals of Statistics 49(2):1055-1080. arXiv:1810.08240
  Waudby-Smith & Ramdas (2024)
    "Estimating means of bounded random variables by betting"
    JRSS-B 86(1):1-27. arXiv:2010.09686 (Theorem 2, predictable
    plug-in empirical-Bernstein CS)
