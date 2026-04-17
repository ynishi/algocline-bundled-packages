---
name: f_race
version: 0.1.0
category: selection
description: "Friedman race partial-data pruner. Block-wise ranking of candidates over rubric dimensions; eliminates candidates whose mean rank is significantly worse than the best by a Friedman + Nemenyi post-hoc test. Designed for small N (≤10) × D (≤30) where Empirical-Bernstein CS cannot fire."
source: f_race/init.lua
generated: gen_docs (V0)
---

# f_race — Friedman Race Partial-Data Pruner

> Given N candidate answers and a D-dimensional rubric, this package evaluates (candidate × dimension) pairs in BLOCK order (one rubric dimension at a time across all alive candidates), maintains a rank matrix, and ELIMINATES candidates whose mean rank is significantly worse than the best survivor by a Friedman + Nemenyi post-hoc test.

## Contents

  - [Why F-Race for this scale](#why-f-race-for-this-scale)
  - [Detection power — read this before choosing the rubric type](#detection-power-read-this-before-choosing-the-rubric-type)
  - [Empirical validation (N=6, D=20, min_blocks=5, δ=0.05, binary rubric)](#empirical-validation-n-6-d-20-min-blocks-5-0-05-binary-rubric)
  - [Theoretical foundations](#theoretical-foundations)
  - [Kill rate limit (important)](#kill-rate-limit-important)
  - [Post-hoc multiplicity and sequential testing](#post-hoc-multiplicity-and-sequential-testing)

### Why F-Race for this scale {#why-f-race-for-this-scale}

At the operating point of this codebase (N≈6 candidates, D≈20 rubric
dimensions), Empirical-Bernstein Confidence Sequences (cs_pruner)
cannot fire: their variance-independent floor radius_floor(t=20) ≈
0.43 makes a kill mathematically impossible for any mean-gap < 0.86.
See workspace/cs_pruner_root_cause.md for the derivation.

F-Race operates on RANKS, not raw scores. The Friedman χ² statistic

    Q = (12 / (B·N(N+1))) · Σ_j R_j²  -  3·B·(N+1)

with B = blocks observed and R_j = rank-sum of cand j, lets the
Nemenyi post-hoc reject a pairwise difference iff

    |R_i - R_j| > (q_{∞,N,α}/√2) · √(B·N(N+1)/6)

where q_{∞,N,α} is the Studentized range quantile (Tukey). For N=6,
α=0.05 the constant is q/√2 ≈ 2.850 (NOT the normal z=1.96 — see
the implementation note in nemenyi_critical_diff for the history).

### Detection power — read this before choosing the rubric type {#detection-power-read-this-before-choosing-the-rubric-type}

The detection power depends critically on whether scores are CONTINUOUS
or BINARY (PASS/FAIL). Both regimes are analyzed below for N=6, δ=0.05
using the correct Studentized-range constant c = q_{∞,6,0.05}/√2 = 2.850.

#### A. Continuous scores in [0, 1] (Likert ≥ 5 levels recommended)

Under a normal-approximation model the required block count to detect
a true mean-gap Δ between two candidates scales as

    B_continuous(Δ)  ~  c² · (N(N+1)/6) · σ_block² / Δ²

where σ_block² is the per-block variance of the pairwise rank gap
(depends on the rubric distribution; ≤ N²/12 ≈ 3 in the worst case).
This is a rough envelope only — exact values depend on the score
distribution and should be measured empirically per task.

#### B. Binary PASS/FAIL scores

With binary scores in each block the pairwise rank gap is exactly 3
when one PASSes and the other FAILs, and 0 otherwise:

    E[R_i - R_j | one block]  =  3 · (p_i - p_j)  =  3·Δ
    Var[R_i - R_j | one block]  ≤  9

where Δ = p_i - p_j is the true PASS-rate gap. The Nemenyi post-hoc
requires Σ_blocks (R_i - R_j) > c · √(B·N(N+1)/6) = c·√(7B) with
c = 2.850 at N=6, δ=0.05:

    3·B·Δ  >  2.850 · √(7B)
    ⇒  B  >  (2.514 / Δ)²  ≈  6.32 / Δ²

    Δ        Required B
    0.7      13     ← detectable within D=20
    0.5      26     ← NOT detectable at D=20
    0.4      40     ← NOT detectable at D=20
    0.3      71     ← NOT detectable at D=20

**PASS/FAIL rubrics at N=6 can only resolve PASS-rate gaps Δ ≥ 0.7
within the default D=20 dimensions.** Smaller gaps require more
dimensions, a finer-grained rubric, or fewer candidates.

#### Recommendation

For the small-N×D regime targeted by this package, use a Likert rubric
(3 or 5 levels). This package exposes `f_race.LIKERT5_RUBRIC` as a
ready-to-use 5-level template. Pass it via `ctx.rubric` to enable
finer discrimination at the cost of a slightly more complex evaluator
prompt.

The PASS/FAIL `DEFAULT_RUBRIC` is retained for backwards compatibility
and for cases where the score gap is large (Δ ≥ 0.4).

### Empirical validation (N=6, D=20, min_blocks=5, δ=0.05, binary rubric) {#empirical-validation-n-6-d-20-min-blocks-5-0-05-binary-rubric}

50 trials × 6 gap scenarios with a deterministic Bernoulli mock judge
(candidates drawn as Bernoulli(p_i) per block):

    Δ      Fire rate   Avg kills   First kill    Avg evals   Saving
    0.8    100%        2.58        block  7.7     96.4       19.7%
    0.7    100%        2.02        block  8.4    102.6       14.5%
    0.5     84%        1.10        block 13.2    113.1        5.8%
    0.3     22%        0.24        block 13.9    118.6        1.2%
    0.1      6%        0.06        block 17.7    119.9        0.1%
    0.0      0%        0.00        —             120.0        0.0%

Δ=0 produced ZERO spurious kills across 50 trials, consistent with
δ=0.05 Type I control under repeated testing. Observed first-kill
blocks are EARLIER than the expected-value lower bound
B_min ≈ 6.32/Δ² because the bound ignores variance-driven upside
fluctuations — treat B_min as a pessimistic floor, not a point
prediction. At Δ=0.5 the bound says B=26 > D=20 (nominally
"undetectable") yet 84% of trials still fire thanks to variance.

The package complements cs_pruner: use cs_pruner.layer2 (Successive
Halving) for coarse drops, and f_race when fine discrimination is
needed at the small-N×D scale.

### Theoretical foundations {#theoretical-foundations}

  Friedman, M. (1937) "The use of ranks to avoid the assumption of
    normality implicit in the analysis of variance," J. Am. Stat.
    Assoc. 32(200): 675–701.
  Birattari, Stützle, Paquete, Varrentrapp (2002) "A racing algorithm
    for configuring metaheuristics," GECCO, §3 — original F-Race.
  Nemenyi, P. B. (1963) "Distribution-free Multiple Comparisons,"
    PhD thesis, Princeton University — post-hoc pairwise comparison
    after Friedman (normal-approximation z form used here).
  Demšar, J. (2006) "Statistical Comparisons of Classifiers over
    Multiple Data Sets," JMLR 7:1–30 — modern reference for the
    Friedman + Nemenyi pipeline as implemented here.

Algorithm:
  1. Generate N candidates.
  2. For each rubric dimension k = 1..D (= one block):
       a. Query the judge in parallel for every alive candidate's
          score on dimension k. Score ∈ [0, 1] (PASS/FAIL or numeric).
       b. Rank the alive candidates within this block (average ranks
          on ties; lower-is-worse, so highest score gets rank N_alive).
       c. Append the rank vector to the history.
       d. If B >= min_blocks_before_race, compute Friedman Q. If
          Q > χ²_{N_alive - 1, 1-δ}, eliminate every candidate whose
          rank-sum is more than the Nemenyi critical difference below
          the best.
  3. Return ranking by mean rank (alive first, then eliminated).

Usage:
  local f_race = require("f_race")
  return f_race.run(ctx)

### Kill rate limit (important) {#kill-rate-limit-important}

Each elimination event resets `rank_history` (because the alive set
changes and the Friedman statistic must be computed over a uniform
set of candidates). After a reset the algorithm must re-accumulate
`min_blocks_before_race` blocks before the next race check can fire.

⇒ The maximum number of race rounds within D dimensions is roughly
    ⌊D / min_blocks_before_race⌋.

With the defaults (D=20, min_blocks_before_race=5) this caps the
algorithm at **at most 4 elimination rounds**. If you need more
aggressive pruning, lower `min_blocks_before_race` (at the cost of
less stable Friedman estimates) or increase D.

### Post-hoc multiplicity and sequential testing {#post-hoc-multiplicity-and-sequential-testing}

The Nemenyi critical difference already absorbs the pairwise FWER
via the Studentized range distribution (q_{∞,k,α}/√2), so no extra
Bonferroni step is needed at a single time point. The Friedman global
test gates the post-hoc as in Demšar (2006).

However, this implementation applies the test at every block beyond
`min_blocks_before_race`, which is REPEATED testing of the same null
and inflates the time-aggregated Type I error above the nominal δ.
This is NOT corrected by the warmup window and is NOT anytime-valid
in the formal Howard 2021 sense. The inflation is bounded by the
number of look-ahead opportunities (≈ ⌊D/min_blocks⌋ + resets), so
in practice with D=20, min_blocks=5 the effective α is at most a
small constant multiple of δ. Tighten `delta` (e.g. 0.01) if strict
δ control is required.

Parameters:
  ctx.task (required)              Problem statement
  ctx.n_candidates (default 6)     Number of candidates
  ctx.rubric (default 20-dim)      List of {name, criterion}
  ctx.delta (default 0.05)         Significance level for Friedman test.
                                   Resolved to the largest tabulated α
                                   that is ≤ delta. Tabulated levels:
                                   0.05, 0.025, 0.0125, 0.01, 0.005,
                                   0.0025, 0.001 (conservative rounding).
  ctx.min_blocks_before_race (5)   Warmup: no elimination before this B
  ctx.score_domain (default {0,1}) Used only for clipping
  ctx.gen_tokens (default 400)     Max tokens per candidate generation
  ctx.on_kill                      function(candidate_index, state)
  ctx.on_survive                   function(candidate_index, state)
  ctx.alpha_spending (default false)
                                   Opt-in sequential testing correction.
                                   When true, the Friedman test is gated
                                   to fixed checkpoints spaced
                                   `min_blocks_before_race` apart, and
                                   the internal δ is downgraded one
                                   table step (0.05 → 0.01) whenever
                                   the per-segment look budget K_max =
                                   ⌊D/min_blocks⌋ ≥ 2. Coarse Bonferroni-
                                   via-table-step; recommended whenever
                                   strict δ control matters.

Comparison with related packages:
  cs_pruner       — anytime-valid CS, requires t in the hundreds.
  gumbel_search   — Sequential Halving, batched.
  listwise_rank   — post-hoc full ranking, no early stop.
  pairwise_rank   — pairwise tournament, no statistical test.
  f_race          — block-by-block ranks + Friedman + Nemenyi
                    post-hoc. Sequential (NOT anytime-valid); see
                    "Post-hoc multiplicity and sequential testing"
                    above for the caveat on repeated testing.
