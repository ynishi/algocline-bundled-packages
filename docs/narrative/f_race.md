---
name: f_race
version: 0.1.0
category: selection
result_shape: "shape { alive_count: number, alpha_spending: boolean, best: string, best_index: number, best_score: number, candidates: array of string, delta: number, effective_delta: number, evaluations: number, kill_events: array of shape { best_candidate: number, best_rank_sum: number, block: number, blocks_used: number, candidate: number, chi2_critical: number, crit_diff: number, mean: number, n: number, q: number, rank_sum: number }, n_candidates: number, n_dimensions: number, ranking: array of shape { alive: boolean, index: number, mean: number, mean_rank?: number, n: number }, rounds: array of shape { candidate: number, dimension: number, dimension_name: string, iteration: number, n_after: number, score: number }, total_llm_calls: number }"
description: "Friedman race partial-data pruner with Nemenyi post-hoc elimination."
source: f_race/init.lua
generated: gen_docs (V0)
---

# f_race(FRace) — Friedman Race partial-data candidate pruner

> Given N candidate answers and a D-dimensional rubric, evaluates `(candidate × dimension)` pairs in block order (one rubric dimension at a time across all alive candidates), maintains a rank matrix, and eliminates candidates whose mean rank is significantly worse than the best survivor by a Friedman + Nemenyi post-hoc test.

## Contents

- [Usage](#usage)
- [Algorithm](#algorithm)
- [Caveats](#caveats)
- [Empirical validation](#empirical-validation)
- [Comparison with related packages](#comparison-with-related-packages)
- [References](#references)
- [Parameters](#parameters)
- [Result](#result)

## Usage {#usage}

```lua
local f_race = require("f_race")
return f_race.run(ctx)
```

## Algorithm {#algorithm}

1. Generate N candidates.
2. For each rubric dimension `k = 1..D` (one block):
   - Query the judge in parallel for every alive candidate's score on
     `k`. Score `∈ [0, 1]` (PASS/FAIL or numeric).
   - Rank the alive candidates within the block (average ranks on
     ties; highest score gets rank `N_alive`).
   - Append the rank vector to the history.
   - If `B >= min_blocks_before_race`, compute Friedman `Q`. If
     `Q > χ²_{N_alive - 1, 1-δ}`, eliminate every candidate whose
     rank-sum is more than the Nemenyi critical difference below the
     best.
3. Return ranking by mean rank (alive first, then eliminated).

## Caveats {#caveats}

F-Race operates on ranks, not raw scores. At the operating point of
this codebase (`N≈6`, `D≈20`), Empirical-Bernstein Confidence
Sequences (`cs_pruner`) cannot fire: their variance-independent floor
`radius_floor(t=20) ≈ 0.43` makes a kill impossible for any mean gap
below 0.86.

Detection power depends on whether scores are continuous or binary.
For binary PASS/FAIL the per-block pairwise rank gap is exactly 3
when one PASSes and the other FAILs:

```math
E[R_i - R_j | one block]  = 3 · (p_i - p_j) = 3·Δ
Var[R_i - R_j | one block] ≤ 9
```

The Nemenyi post-hoc requires
`Σ_blocks (R_i - R_j) > c · √(B·N(N+1)/6)` with
`c = q_{∞,6,0.05}/√2 = 2.850`, giving `B > (2.514 / Δ)² ≈ 6.32 / Δ²`.
A PASS/FAIL rubric at `N=6` can therefore only resolve PASS-rate gaps
`Δ ≥ 0.7` within the default `D=20` dimensions; smaller gaps need
more dimensions or a finer rubric. Use the bundled
`f_race.LIKERT5_RUBRIC` for finer discrimination.

Each elimination event resets `rank_history` (because the alive set
changes and the Friedman statistic must be computed over a uniform
set). After a reset the algorithm re-accumulates
`min_blocks_before_race` blocks before the next race check can fire,
so the maximum number of race rounds within `D` dimensions is roughly
`⌊D / min_blocks_before_race⌋` (at most 4 with defaults).

The Nemenyi critical difference absorbs pairwise FWER via the
Studentized range distribution, so no extra Bonferroni is needed at a
single time point. However the implementation tests at every block
beyond `min_blocks_before_race`, which is repeated testing and
inflates time-aggregated Type I error above the nominal δ. This is
not anytime-valid in the formal Howard (2021) sense. Inflation is
bounded by `≈ ⌊D/min_blocks⌋ + resets`, so with `D=20`,
`min_blocks=5` the effective α is at most a small constant multiple
of δ. Tighten `delta` (e.g. 0.01) if strict δ control is required, or
enable `alpha_spending`.

## Empirical validation {#empirical-validation}

50 trials × 6 gap scenarios with a deterministic Bernoulli mock judge
(`N=6`, `D=20`, `min_blocks=5`, `δ=0.05`, binary rubric):

```text
Δ      Fire rate   Avg kills   First kill    Avg evals   Saving
0.8    100%        2.58        block  7.7     96.4       19.7%
0.7    100%        2.02        block  8.4    102.6       14.5%
0.5     84%        1.10        block 13.2    113.1        5.8%
0.3     22%        0.24        block 13.9    118.6        1.2%
0.1      6%        0.06        block 17.7    119.9        0.1%
0.0      0%        0.00        —             120.0        0.0%
```

`Δ=0` produced zero spurious kills across 50 trials, consistent with
δ=0.05 Type I control under repeated testing.

## Comparison with related packages {#comparison-with-related-packages}

- `cs_pruner` — anytime-valid CS, requires `t` in the hundreds.
- `gumbel_search` — Sequential Halving, batched.
- `listwise_rank` — post-hoc full ranking, no early stop.
- `pairwise_rank` — pairwise tournament, no statistical test.
- `f_race` — block-by-block ranks + Friedman + Nemenyi post-hoc.
  Sequential (not anytime-valid); see Caveats.

## References {#references}

- Friedman, M. (1937). "The use of ranks to avoid the assumption of
  normality implicit in the analysis of variance". J. Am. Stat.
  Assoc. 32(200): 675-701.
- Birattari, M., Stützle, T., Paquete, L., Varrentrapp, K. (2002).
  "A racing algorithm for configuring metaheuristics". GECCO §3.
- Nemenyi, P. B. (1963). "Distribution-free Multiple Comparisons".
  PhD thesis, Princeton University.
- Demšar, J. (2006). "Statistical Comparisons of Classifiers over
  Multiple Data Sets". JMLR 7:1-30.

## Parameters {#parameters}

| key | type | required | description |
|---|---|---|---|
| `ctx.alpha_spending` | boolean | optional | Bonferroni sequential correction (default: false) |
| `ctx.delta` | number | optional | Significance level (default: 0.05); resolved to largest tabulated α ≤ delta |
| `ctx.gen_tokens` | number | optional | Max tokens per candidate generation (default: 400) |
| `ctx.min_blocks_before_race` | number | optional | Warmup block count before elimination (default: 5) |
| `ctx.n_candidates` | number | optional | Number of candidates (default: 6) |
| `ctx.rubric` | array of shape { criterion: string, name: string } | optional | Rubric dimensions (default: 20-dim binary) |
| `ctx.rubric_type` | string | optional | "binary" \| "likert5" (default: "binary") |
| `ctx.score_domain` | shape { max: number, min: number } | optional | Score range for clipping (default: {min=0,max=1}) |
| `ctx.task` | string | **required** | Problem statement |

## Result {#result}

Returns:

| key | type | optional | description |
|---|---|---|---|
| `alive_count` | number | — | Number of survivors at termination |
| `alpha_spending` | boolean | — | Whether Bonferroni sequential correction was applied |
| `best` | string | — | Text of the best surviving candidate |
| `best_index` | number | — | 1-based index of the winner |
| `best_score` | number | — | Empirical mean score of the winner |
| `candidates` | array of string | — | All generated candidate texts |
| `delta` | number | — | User-requested significance level |
| `effective_delta` | number | — | Resolved tabulated α (possibly Bonferroni-tightened) |
| `evaluations` | number | — | Number of per-dimension evaluations performed |
| `kill_events` | array of shape { best_candidate: number, best_rank_sum: number, block: number, blocks_used: number, candidate: number, chi2_critical: number, crit_diff: number, mean: number, n: number, q: number, rank_sum: number } | — | Elimination events triggered by Friedman+Nemenyi |
| `n_candidates` | number | — |  |
| `n_dimensions` | number | — |  |
| `ranking` | array of shape { alive: boolean, index: number, mean: number, mean_rank?: number, n: number } | — | All candidates sorted by alive+mean_rank/mean descending |
| `rounds` | array of shape { candidate: number, dimension: number, dimension_name: string, iteration: number, n_after: number, score: number } | — | Per-evaluation trace |
| `total_llm_calls` | number | — | Candidate generation + evaluation calls |
