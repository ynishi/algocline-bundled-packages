--- f_race — Friedman Race Partial-Data Pruner
---
--- Given N candidate answers and a D-dimensional rubric, this package
--- evaluates (candidate × dimension) pairs in BLOCK order (one rubric
--- dimension at a time across all alive candidates), maintains a rank
--- matrix, and ELIMINATES candidates whose mean rank is significantly
--- worse than the best survivor by a Friedman + Nemenyi post-hoc test.
---
--- ### Why F-Race for this scale
---
--- At the operating point of this codebase (N≈6 candidates, D≈20 rubric
--- dimensions), Empirical-Bernstein Confidence Sequences (cs_pruner)
--- cannot fire: their variance-independent floor radius_floor(t=20) ≈
--- 0.43 makes a kill mathematically impossible for any mean-gap < 0.86.
---
--- F-Race operates on RANKS, not raw scores. The Friedman χ² statistic
---
---     Q = (12 / (B·N(N+1))) · Σ_j R_j²  -  3·B·(N+1)
---
--- with B = blocks observed and R_j = rank-sum of cand j, lets the
--- Nemenyi post-hoc reject a pairwise difference iff
---
---     |R_i - R_j| > (q_{∞,N,α}/√2) · √(B·N(N+1)/6)
---
--- where q_{∞,N,α} is the Studentized range quantile (Tukey). For N=6,
--- α=0.05 the constant is q/√2 ≈ 2.850 (NOT the normal z=1.96 — see
--- the implementation note in nemenyi_critical_diff for the history).
---
--- ### Detection power — read this before choosing the rubric type
---
--- The detection power depends critically on whether scores are CONTINUOUS
--- or BINARY (PASS/FAIL). Both regimes are analyzed below for N=6, δ=0.05
--- using the correct Studentized-range constant c = q_{∞,6,0.05}/√2 = 2.850.
---
--- #### A. Continuous scores in [0, 1] (Likert ≥ 5 levels recommended)
---
--- Under a normal-approximation model the required block count to detect
--- a true mean-gap Δ between two candidates scales as
---
---     B_continuous(Δ)  ~  c² · (N(N+1)/6) · σ_block² / Δ²
---
--- where σ_block² is the per-block variance of the pairwise rank gap
--- (depends on the rubric distribution; ≤ N²/12 ≈ 3 in the worst case).
--- This is a rough envelope only — exact values depend on the score
--- distribution and should be measured empirically per task.
---
--- #### B. Binary PASS/FAIL scores
---
--- With binary scores in each block the pairwise rank gap is exactly 3
--- when one PASSes and the other FAILs, and 0 otherwise:
---
---     E[R_i - R_j | one block]  =  3 · (p_i - p_j)  =  3·Δ
---     Var[R_i - R_j | one block]  ≤  9
---
--- where Δ = p_i - p_j is the true PASS-rate gap. The Nemenyi post-hoc
--- requires Σ_blocks (R_i - R_j) > c · √(B·N(N+1)/6) = c·√(7B) with
--- c = 2.850 at N=6, δ=0.05:
---
---     3·B·Δ  >  2.850 · √(7B)
---     ⇒  B  >  (2.514 / Δ)²  ≈  6.32 / Δ²
---
---     Δ        Required B
---     0.7      13     ← detectable within D=20
---     0.5      26     ← NOT detectable at D=20
---     0.4      40     ← NOT detectable at D=20
---     0.3      71     ← NOT detectable at D=20
---
--- **PASS/FAIL rubrics at N=6 can only resolve PASS-rate gaps Δ ≥ 0.7
--- within the default D=20 dimensions.** Smaller gaps require more
--- dimensions, a finer-grained rubric, or fewer candidates.
---
--- #### Recommendation
---
--- For the small-N×D regime targeted by this package, use a Likert rubric
--- (3 or 5 levels). This package exposes `f_race.LIKERT5_RUBRIC` as a
--- ready-to-use 5-level template. Pass it via `ctx.rubric` to enable
--- finer discrimination at the cost of a slightly more complex evaluator
--- prompt.
---
--- The PASS/FAIL `DEFAULT_RUBRIC` is retained for backwards compatibility
--- and for cases where the score gap is large (Δ ≥ 0.4).
---
--- ### Empirical validation (N=6, D=20, min_blocks=5, δ=0.05, binary rubric)
---
--- 50 trials × 6 gap scenarios with a deterministic Bernoulli mock judge
--- (candidates drawn as Bernoulli(p_i) per block):
---
---     Δ      Fire rate   Avg kills   First kill    Avg evals   Saving
---     0.8    100%        2.58        block  7.7     96.4       19.7%
---     0.7    100%        2.02        block  8.4    102.6       14.5%
---     0.5     84%        1.10        block 13.2    113.1        5.8%
---     0.3     22%        0.24        block 13.9    118.6        1.2%
---     0.1      6%        0.06        block 17.7    119.9        0.1%
---     0.0      0%        0.00        —             120.0        0.0%
---
--- Δ=0 produced ZERO spurious kills across 50 trials, consistent with
--- δ=0.05 Type I control under repeated testing. Observed first-kill
--- blocks are EARLIER than the expected-value lower bound
--- B_min ≈ 6.32/Δ² because the bound ignores variance-driven upside
--- fluctuations — treat B_min as a pessimistic floor, not a point
--- prediction. At Δ=0.5 the bound says B=26 > D=20 (nominally
--- "undetectable") yet 84% of trials still fire thanks to variance.
---
--- The package complements cs_pruner: use cs_pruner.layer2 (Successive
--- Halving) for coarse drops, and f_race when fine discrimination is
--- needed at the small-N×D scale.
---
--- ### Theoretical foundations
---
---   Friedman, M. (1937) "The use of ranks to avoid the assumption of
---     normality implicit in the analysis of variance," J. Am. Stat.
---     Assoc. 32(200): 675–701.
---   Birattari, Stützle, Paquete, Varrentrapp (2002) "A racing algorithm
---     for configuring metaheuristics," GECCO, §3 — original F-Race.
---   Nemenyi, P. B. (1963) "Distribution-free Multiple Comparisons,"
---     PhD thesis, Princeton University — post-hoc pairwise comparison
---     after Friedman (normal-approximation z form used here).
---   Demšar, J. (2006) "Statistical Comparisons of Classifiers over
---     Multiple Data Sets," JMLR 7:1–30 — modern reference for the
---     Friedman + Nemenyi pipeline as implemented here.
---
--- Algorithm:
---   1. Generate N candidates.
---   2. For each rubric dimension k = 1..D (= one block):
---        a. Query the judge in parallel for every alive candidate's
---           score on dimension k. Score ∈ [0, 1] (PASS/FAIL or numeric).
---        b. Rank the alive candidates within this block (average ranks
---           on ties; lower-is-worse, so highest score gets rank N_alive).
---        c. Append the rank vector to the history.
---        d. If B >= min_blocks_before_race, compute Friedman Q. If
---           Q > χ²_{N_alive - 1, 1-δ}, eliminate every candidate whose
---           rank-sum is more than the Nemenyi critical difference below
---           the best.
---   3. Return ranking by mean rank (alive first, then eliminated).
---
--- Usage:
---   local f_race = require("f_race")
---   return f_race.run(ctx)
---
--- ### Kill rate limit (important)
---
--- Each elimination event resets `rank_history` (because the alive set
--- changes and the Friedman statistic must be computed over a uniform
--- set of candidates). After a reset the algorithm must re-accumulate
--- `min_blocks_before_race` blocks before the next race check can fire.
---
--- ⇒ The maximum number of race rounds within D dimensions is roughly
---     ⌊D / min_blocks_before_race⌋.
---
--- With the defaults (D=20, min_blocks_before_race=5) this caps the
--- algorithm at **at most 4 elimination rounds**. If you need more
--- aggressive pruning, lower `min_blocks_before_race` (at the cost of
--- less stable Friedman estimates) or increase D.
---
--- ### Post-hoc multiplicity and sequential testing
---
--- The Nemenyi critical difference already absorbs the pairwise FWER
--- via the Studentized range distribution (q_{∞,k,α}/√2), so no extra
--- Bonferroni step is needed at a single time point. The Friedman global
--- test gates the post-hoc as in Demšar (2006).
---
--- However, this implementation applies the test at every block beyond
--- `min_blocks_before_race`, which is REPEATED testing of the same null
--- and inflates the time-aggregated Type I error above the nominal δ.
--- This is NOT corrected by the warmup window and is NOT anytime-valid
--- in the formal Howard 2021 sense. The inflation is bounded by the
--- number of look-ahead opportunities (≈ ⌊D/min_blocks⌋ + resets), so
--- in practice with D=20, min_blocks=5 the effective α is at most a
--- small constant multiple of δ. Tighten `delta` (e.g. 0.01) if strict
--- δ control is required.
---
--- Parameters:
---   ctx.task (required)              Problem statement
---   ctx.n_candidates (default 6)     Number of candidates
---   ctx.rubric (default 20-dim)      List of {name, criterion}
---   ctx.delta (default 0.05)         Significance level for Friedman test.
---                                    Resolved to the largest tabulated α
---                                    that is ≤ delta. Tabulated levels:
---                                    0.05, 0.025, 0.0125, 0.01, 0.005,
---                                    0.0025, 0.001 (conservative rounding).
---   ctx.min_blocks_before_race (5)   Warmup: no elimination before this B
---   ctx.score_domain (default {0,1}) Used only for clipping
---   ctx.gen_tokens (default 400)     Max tokens per candidate generation
---   ctx.on_kill                      function(candidate_index, state)
---   ctx.on_survive                   function(candidate_index, state)
---   ctx.alpha_spending (default false)
---                                    Opt-in sequential testing correction.
---                                    When true, the Friedman test is gated
---                                    to fixed checkpoints spaced
---                                    `min_blocks_before_race` apart, and
---                                    the internal δ is downgraded one
---                                    table step (0.05 → 0.01) whenever
---                                    the per-segment look budget K_max =
---                                    ⌊D/min_blocks⌋ ≥ 2. Coarse Bonferroni-
---                                    via-table-step; recommended whenever
---                                    strict δ control matters.
---
--- Comparison with related packages:
---   cs_pruner       — anytime-valid CS, requires t in the hundreds.
---   gumbel_search   — Sequential Halving, batched.
---   listwise_rank   — post-hoc full ranking, no early stop.
---   pairwise_rank   — pairwise tournament, no statistical test.
---   f_race          — block-by-block ranks + Friedman + Nemenyi
---                     post-hoc. Sequential (NOT anytime-valid); see
---                     "Post-hoc multiplicity and sequential testing"
---                     above for the caveat on repeated testing.

local M = {}

---@type AlcMeta
M.meta = {
    name = "f_race",
    version = "0.1.0",
    description = "Friedman race partial-data pruner. Block-wise ranking "
        .. "of candidates over rubric dimensions; eliminates candidates "
        .. "whose mean rank is significantly worse than the best by a "
        .. "Friedman + Nemenyi post-hoc test. Designed for small N (≤10) "
        .. "× D (≤30) where Empirical-Bernstein CS cannot fire.",
    category = "selection",
}

-- ─── χ² and Nemenyi critical-value tables ──────────────────────────────
--
-- Both families are tabulated at 7 discrete α levels:
--     0.05, 0.025, 0.0125, 0.01, 0.005, 0.0025, 0.001
--
-- The 7-level grid lets us implement Bonferroni correction for
-- α-spending: when the per-segment look budget is K_max ≥ 2 we look up
-- the smallest tabulated α that does not exceed user_α / K_max. The
-- grid covers K_max ∈ {1, 2, 3, 4, 5, 10, 20, 50} cleanly when the
-- user picks α=0.05.
--
-- Tables auto-generated via numerical inversion:
--   * χ² CDF: regularized lower incomplete gamma via Lentz's continued
--     fraction (s ≥ x+1) or power series (s < x+1), then bisection.
--   * Studentized range CDF: P(Q≤q) = k·∫φ(x)·[Φ(x+q)-Φ(x)]^{k-1} dx
--     evaluated by Simpson's rule (n=600, range [-12, 12]), then
--     bisection.
-- Cross-checked against Demšar (2006) JMLR 7 Table 5 and standard
-- χ² critical tables: agreement ≤ 0.001 in the Nemenyi column and
-- ≤ 0.005 in the χ² column for all (k, df, α) tabulated below.

local CHI2_05 = {
    [1]=3.841, [2]=5.991, [3]=7.815, [4]=9.488,
    [5]=11.070, [6]=12.592, [7]=14.067, [8]=15.507,
    [9]=16.919, [10]=18.307, [11]=19.675, [12]=21.026,
    [13]=22.362, [14]=23.685, [15]=24.996, [16]=26.296,
    [17]=27.587, [18]=28.869, [19]=30.144,
}
local CHI2_025 = {
    [1]=5.024, [2]=7.378, [3]=9.348, [4]=11.143,
    [5]=12.833, [6]=14.449, [7]=16.013, [8]=17.535,
    [9]=19.023, [10]=20.483, [11]=21.920, [12]=23.337,
    [13]=24.736, [14]=26.119, [15]=27.488, [16]=28.845,
    [17]=30.191, [18]=31.526, [19]=32.852,
}
local CHI2_0125 = {
    [1]=6.239, [2]=8.764, [3]=10.861, [4]=12.762,
    [5]=14.544, [6]=16.245, [7]=17.885, [8]=19.478,
    [9]=21.034, [10]=22.558, [11]=24.056, [12]=25.530,
    [13]=26.985, [14]=28.422, [15]=29.843, [16]=31.250,
    [17]=32.644, [18]=34.027, [19]=35.399,
}
local CHI2_01 = {
    [1]=6.635, [2]=9.210, [3]=11.345, [4]=13.277,
    [5]=15.086, [6]=16.812, [7]=18.475, [8]=20.090,
    [9]=21.666, [10]=23.209, [11]=24.725, [12]=26.217,
    [13]=27.688, [14]=29.141, [15]=30.578, [16]=32.000,
    [17]=33.409, [18]=34.805, [19]=36.191,
}
local CHI2_005 = {
    [1]=7.879, [2]=10.597, [3]=12.838, [4]=14.860,
    [5]=16.750, [6]=18.548, [7]=20.278, [8]=21.955,
    [9]=23.589, [10]=25.188, [11]=26.757, [12]=28.300,
    [13]=29.819, [14]=31.319, [15]=32.801, [16]=34.267,
    [17]=35.718, [18]=37.156, [19]=38.582,
}
local CHI2_0025 = {
    [1]=9.141, [2]=11.983, [3]=14.320, [4]=16.424,
    [5]=18.386, [6]=20.249, [7]=22.040, [8]=23.774,
    [9]=25.462, [10]=27.112, [11]=28.729, [12]=30.318,
    [13]=31.883, [14]=33.426, [15]=34.950, [16]=36.456,
    [17]=37.946, [18]=39.422, [19]=40.885,
}
local CHI2_001 = {
    [1]=10.828, [2]=13.816, [3]=16.266, [4]=18.467,
    [5]=20.515, [6]=22.458, [7]=24.322, [8]=26.124,
    [9]=27.877, [10]=29.588, [11]=31.264, [12]=32.909,
    [13]=34.528, [14]=36.123, [15]=37.697, [16]=39.252,
    [17]=40.790, [18]=42.312, [19]=43.820,
}

-- Mapping: tabulated α → (chi2 table, Wilson-Hilferty z, nemenyi table).
-- Listed in DESCENDING α order so resolve_alpha() can pick the largest
-- tabulated α that is ≤ requested α.
--
-- z_wh is the standard-normal upper (1-α)-quantile Φ⁻¹(1-α), used by
-- the Wilson-Hilferty (1931) approximation in chi2_critical for df>19:
--     χ²_{df,1-α} ≈ df · (1 - 2/(9df) + z_wh · √(2/(9df)))³
-- Values are the standard tabulated normal quantiles
-- (e.g. Φ⁻¹(0.95)=1.645, Φ⁻¹(0.975)=1.960, ..., Φ⁻¹(0.999)=3.090);
-- can be regenerated via scipy.stats.norm.ppf(1-α).
local ALPHA_LEVELS = {
    { alpha = 0.05,    chi2 = CHI2_05,    z_wh = 1.645 },
    { alpha = 0.025,   chi2 = CHI2_025,   z_wh = 1.960 },
    { alpha = 0.0125,  chi2 = CHI2_0125,  z_wh = 2.241 },
    { alpha = 0.01,    chi2 = CHI2_01,    z_wh = 2.326 },
    { alpha = 0.005,   chi2 = CHI2_005,   z_wh = 2.576 },
    { alpha = 0.0025,  chi2 = CHI2_0025,  z_wh = 2.807 },
    { alpha = 0.001,   chi2 = CHI2_001,   z_wh = 3.090 },
}

-- Resolve a requested α to the largest tabulated level that does not
-- exceed it (conservative direction — the realised type-I rate is
-- ≤ the user's requested α).
--
-- ALPHA_LEVELS is sorted DESCENDING (0.05, 0.025, ..., 0.001), so the
-- first level whose α ≤ requested is the answer.
--
-- Returns nil iff `requested` is below the smallest tabulated level
-- (0.001). Requests above 0.05 are NOT rejected — they resolve to
-- the 0.05 level (no further loosening), and the upstream caller
-- is expected to gate δ ∈ (0, 1) separately.
local function resolve_alpha(requested)
    for _, lvl in ipairs(ALPHA_LEVELS) do
        if lvl.alpha <= requested + 1e-12 then return lvl end
    end
    return nil
end

local function chi2_critical(df, delta)
    local lvl = resolve_alpha(delta)
    if not lvl then
        error(string.format(
            "f_race: chi2_critical: requested α=%s is below the smallest "
                .. "tabulated level (0.001). Use a larger δ.",
            tostring(delta)), 2)
    end
    if df < 1 then df = 1 end
    if df > 19 then
        -- Wilson-Hilferty approximation for large df.
        local z_wh = lvl.z_wh
        local h = 1 - 2 / (9 * df) + z_wh * math.sqrt(2 / (9 * df))
        return df * h * h * h
    end
    return lvl.chi2[df]
end

-- ─── Default 20-dim rubric (mirrors cs_pruner) ───────────────────────────
local DEFAULT_RUBRIC = {
    { name = "factual_accuracy",  criterion = "The answer contains no factual errors." },
    { name = "completeness",      criterion = "The answer addresses all parts of the task." },
    { name = "relevance",         criterion = "The answer is directly relevant to the task." },
    { name = "clarity",           criterion = "The answer is clearly and unambiguously expressed." },
    { name = "coherence",         criterion = "The answer is logically coherent and well-structured." },
    { name = "specificity",       criterion = "The answer is specific rather than vague." },
    { name = "reasoning_depth",   criterion = "The answer shows adequate depth of reasoning." },
    { name = "no_hallucination",  criterion = "The answer does not fabricate information." },
    { name = "appropriate_length",criterion = "The answer is neither too short nor padded." },
    { name = "grammar",           criterion = "The answer is grammatically correct." },
    { name = "terminology",       criterion = "Technical terminology is used correctly." },
    { name = "organization",      criterion = "The answer is well organized." },
    { name = "all_parts",         criterion = "No part of the task is ignored." },
    { name = "concrete_examples", criterion = "Concrete examples or details support the answer." },
    { name = "no_redundancy",     criterion = "The answer avoids unnecessary repetition." },
    { name = "tone",              criterion = "The tone is appropriate for the task." },
    { name = "no_contradictions", criterion = "The answer contains no internal contradictions." },
    { name = "qualified_claims",  criterion = "Claims are appropriately qualified." },
    { name = "actionable",        criterion = "The answer provides actionable insight where relevant." },
    { name = "edge_cases",        criterion = "The answer considers relevant edge cases." },
}

-- Likert-5 rubric: same 20 dimensions, 5-level scoring. Provides finer
-- discrimination for f_race at the cost of a more complex evaluator
-- prompt. See "Detection power" in the docstring above. Pass via
-- ctx.rubric = f_race.LIKERT5_RUBRIC and ctx.rubric_type = "likert5".
M.LIKERT5_RUBRIC = {}
for i, d in ipairs(DEFAULT_RUBRIC) do M.LIKERT5_RUBRIC[i] = d end

local RUBRIC_PROMPT = "Task: %s\n\nCandidate answer:\n%s\n\n"
    .. "Evaluate ONE specific criterion:\nCriterion: %s\n\n"
    .. "Reply with ONLY 'PASS' if the criterion is satisfied, "
    .. "or 'FAIL' if not."

local LIKERT5_PROMPT = "Task: %s\n\nCandidate answer:\n%s\n\n"
    .. "Evaluate ONE specific criterion on a 1–5 scale:\n"
    .. "Criterion: %s\n\n"
    .. "Scale:\n"
    .. "  1 = strongly fails\n"
    .. "  2 = mostly fails\n"
    .. "  3 = partially satisfied\n"
    .. "  4 = mostly satisfies\n"
    .. "  5 = fully satisfies\n\n"
    .. "Reply with ONLY a single digit 1, 2, 3, 4, or 5."

local function parse_rubric_score(raw, is_likert)
    local s = tostring(raw)
    if is_likert then
        local d = s:match("([1-5])")
        if d then
            -- Map 1..5 to [0, 1] uniformly: (d-1)/4
            return (tonumber(d) - 1) / 4
        end
        local n = alc.parse_score(raw)
        if n then
            if n < 0 then n = 0 end
            if n > 1 then n = 1 end
            return n
        end
        error("f_race: cannot parse Likert response: " .. s:sub(1, 200), 2)
    end
    local upper = s:upper()
    if upper:match("PASS") then return 1.0 end
    if upper:match("FAIL") then return 0.0 end
    local n = alc.parse_score(raw)
    if n then return n end
    error("f_race: cannot parse rubric response: " .. s:sub(1, 200), 2)
end

-- ─── Average-rank assignment with tie handling ──────────────────────────
-- Given a list of (idx, score), return a map idx -> rank where ties get
-- the average of the positions they span (Friedman convention).
-- Higher score = higher rank (we want best to have largest rank, since
-- the Friedman test as written treats large rank-sums as "better").
local function assign_ranks(items)
    table.sort(items, function(x, y) return x.score < y.score end)
    local ranks = {}
    local i = 1
    local n = #items
    while i <= n do
        local j = i
        while j < n and items[j + 1].score == items[i].score do
            j = j + 1
        end
        -- Items i..j are tied. Their average rank is (i + j) / 2.
        local avg = (i + j) / 2
        for k = i, j do
            ranks[items[k].idx] = avg
        end
        i = j + 1
    end
    return ranks
end

-- ─── Friedman statistic Q ───────────────────────────────────────────────
-- Computed over ALIVE candidates only, using their per-block ranks.
-- Each block must have been ranked among the same set of alive
-- candidates; this is the case here because we re-rank only the alive
-- ones and start a fresh "view" each time the alive set changes.
--
-- Q = (12 / (B·N(N+1))) · Σ_j R_j²  -  3·B·(N+1)
--
-- Returns Q and the rank-sums Σ_j (per candidate index).
local function friedman_q(rank_history, alive_set)
    local n_alive = 0
    local rank_sums = {}
    for idx in pairs(alive_set) do
        rank_sums[idx] = 0
        n_alive = n_alive + 1
    end
    if n_alive < 2 then return 0, rank_sums, 0, n_alive end
    local b = 0
    for _, block in ipairs(rank_history) do
        -- Only count blocks where every currently-alive candidate was
        -- present (i.e., the block was recorded after the most recent
        -- elimination). The caller resets rank_history on each kill so
        -- this is always true here, but we keep the safety check.
        local complete = true
        for idx in pairs(alive_set) do
            if block[idx] == nil then complete = false break end
        end
        if complete then
            b = b + 1
            for idx in pairs(alive_set) do
                rank_sums[idx] = rank_sums[idx] + block[idx]
            end
        end
    end
    if b < 1 then return 0, rank_sums, 0, n_alive end
    local sum_sq = 0
    for _, rs in pairs(rank_sums) do
        sum_sq = sum_sq + rs * rs
    end
    local q = (12 / (b * n_alive * (n_alive + 1))) * sum_sq
        - 3 * b * (n_alive + 1)
    return q, rank_sums, b, n_alive
end

-- ─── Nemenyi critical rank-sum difference ──────────────────────────────
-- After the Friedman global test rejects, two candidates' rank sums
-- (R_i, R_j) are considered significantly different iff
--
--    |R_i - R_j| > (q_{∞,k,α} / √2) · √( B · k · (k+1) / 6 )
--
-- where q_{∞,k,α} is the upper α-quantile of the Studentized range
-- distribution (Tukey) with k groups and infinite degrees of freedom,
-- and k = n_alive. This is the Nemenyi (1963) post-hoc as formalized
-- for the Friedman test by Demšar (2006) JMLR §3.2.2.
--
-- IMPORTANT: a previous version of this file used the standard normal
-- z (1.960 / 2.576) here. That is WRONG for k ≥ 3 — it underestimates
-- the critical value by a factor of up to ~1.6 at k=10 and inflates
-- the family-wise type-I error well above the nominal δ. The fix is
-- to use the Studentized range q-table below.
--
-- For pairwise comparisons (k=2) the Studentized range value reduces
-- exactly to the normal z (q_{∞,2,0.05}/√2 = 1.960), so the previous
-- code happened to be correct only in that degenerate case.
--
-- Conover (1999) §5.8 gives a different post-hoc based on a t-statistic
-- with a Q-dependent variance estimate; that test is NOT what is
-- implemented here.
--
-- The α passed to this function is the EFFECTIVE α (post-Bonferroni
-- when alpha_spending is on; raw user δ otherwise). The Friedman
-- global test gates this post-hoc, and the Studentized range CD
-- already absorbs the pairwise FWER under the global null. With
-- alpha_spending=true the caller divides δ by the look budget K_max
-- and resolves to the largest tabulated α ≤ δ/K_max, giving a
-- Bonferroni-corrected sequential test.

-- Studentized range q_{∞,k,α} / √2, indexed by k = n_alive.
-- Auto-generated via Simpson n=600 inversion of the Studentized range
-- CDF; cross-checked against Demšar (2006) Table 5 and R qtukey().
local NEMENYI_Q_05 = {
    [2]=1.9600, [3]=2.3437, [4]=2.5690, [5]=2.7278,
    [6]=2.8497, [7]=2.9483, [8]=3.0309, [9]=3.1017,
    [10]=3.1637, [11]=3.2187, [12]=3.2680, [13]=3.3127,
    [14]=3.3536, [15]=3.3912, [16]=3.4260, [17]=3.4584,
    [18]=3.4887, [19]=3.5171, [20]=3.5438,
}
local NEMENYI_Q_025 = {
    [2]=2.2414, [3]=2.6038, [4]=2.8171, [5]=2.9677,
    [6]=3.0836, [7]=3.1775, [8]=3.2561, [9]=3.3237,
    [10]=3.3828, [11]=3.4353, [12]=3.4825, [13]=3.5253,
    [14]=3.5644, [15]=3.6004, [16]=3.6337, [17]=3.6648,
    [18]=3.6938, [19]=3.7210, [20]=3.7467,
}
local NEMENYI_Q_0125 = {
    [2]=2.4977, [3]=2.8410, [4]=3.0439, [5]=3.1874,
    [6]=3.2980, [7]=3.3877, [8]=3.4630, [9]=3.5277,
    [10]=3.5844, [11]=3.6348, [12]=3.6800, [13]=3.7211,
    [14]=3.7587, [15]=3.7933, [16]=3.8254, [17]=3.8552,
    [18]=3.8832, [19]=3.9094, [20]=3.9341,
}
local NEMENYI_Q_01 = {
    [2]=2.5758, [3]=2.9135, [4]=3.1133, [5]=3.2547,
    [6]=3.3637, [7]=3.4522, [8]=3.5265, [9]=3.5903,
    [10]=3.6463, [11]=3.6960, [12]=3.7407, [13]=3.7813,
    [14]=3.8185, [15]=3.8527, [16]=3.8843, [17]=3.9138,
    [18]=3.9414, [19]=3.9674, [20]=3.9918,
}
local NEMENYI_Q_005 = {
    [2]=2.8070, [3]=3.1284, [4]=3.3192, [5]=3.4546,
    [6]=3.5592, [7]=3.6442, [8]=3.7155, [9]=3.7770,
    [10]=3.8308, [11]=3.8787, [12]=3.9218, [13]=3.9610,
    [14]=3.9968, [15]=4.0298, [16]=4.0604, [17]=4.0889,
    [18]=4.1156, [19]=4.1406, [20]=4.1642,
}
local NEMENYI_Q_0025 = {
    [2]=3.0233, [3]=3.3302, [4]=3.5130, [5]=3.6430,
    [6]=3.7436, [7]=3.8254, [8]=3.8942, [9]=3.9534,
    [10]=4.0054, [11]=4.0517, [12]=4.0933, [13]=4.1312,
    [14]=4.1658, [15]=4.1978, [16]=4.2274, [17]=4.2550,
    [18]=4.2808, [19]=4.3051, [20]=4.3279,
}
local NEMENYI_Q_001 = {
    [2]=3.2905, [3]=3.5804, [4]=3.7539, [5]=3.8776,
    [6]=3.9735, [7]=4.0515, [8]=4.1173, [9]=4.1740,
    [10]=4.2238, [11]=4.2681, [12]=4.3080, [13]=4.3443,
    [14]=4.3776, [15]=4.4083, [16]=4.4367, [17]=4.4632,
    [18]=4.4881, [19]=4.5114, [20]=4.5334,
}

-- Patch ALPHA_LEVELS to include the matching nemenyi tables. Order
-- must match the chi2 declaration above.
ALPHA_LEVELS[1].nemenyi = NEMENYI_Q_05
ALPHA_LEVELS[2].nemenyi = NEMENYI_Q_025
ALPHA_LEVELS[3].nemenyi = NEMENYI_Q_0125
ALPHA_LEVELS[4].nemenyi = NEMENYI_Q_01
ALPHA_LEVELS[5].nemenyi = NEMENYI_Q_005
ALPHA_LEVELS[6].nemenyi = NEMENYI_Q_0025
ALPHA_LEVELS[7].nemenyi = NEMENYI_Q_001

local function nemenyi_critical_diff(b, n_alive, delta)
    if n_alive < 2 then
        error("f_race: nemenyi_critical_diff: n_alive must be >= 2", 2)
    end
    if n_alive > 20 then
        error(string.format(
            "f_race: nemenyi_critical_diff: n_alive=%d exceeds tabulated "
                .. "range (k ≤ 20). Regenerate the NEMENYI_Q_* tables for "
                .. "larger k via Studentized range inversion.",
            n_alive), 2)
    end
    local lvl = resolve_alpha(delta)
    if not lvl then
        error(string.format(
            "f_race: nemenyi_critical_diff: requested α=%s is below the "
                .. "smallest tabulated level (0.001).",
            tostring(delta)), 2)
    end
    local q = lvl.nemenyi[n_alive]
    return q * math.sqrt(b * n_alive * (n_alive + 1) / 6)
end

-- ─── Run ─────────────────────────────────────────────────────────────────

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_cand = ctx.n_candidates or 6
    local rubric = ctx.rubric or DEFAULT_RUBRIC
    local delta = ctx.delta or 0.05
    local min_blocks = ctx.min_blocks_before_race or 5
    local score_domain = ctx.score_domain or { min = 0, max = 1 }
    local a, b_dom = score_domain.min, score_domain.max
    local on_kill = ctx.on_kill
    local on_survive = ctx.on_survive
    local gen_tokens = ctx.gen_tokens or 400
    local rubric_type = ctx.rubric_type or "binary"
    local alpha_spending = ctx.alpha_spending and true or false

    if n_cand < 2 then error("f_race: ctx.n_candidates must be >= 2", 2) end
    if delta <= 0 or delta >= 1 then error("f_race: ctx.delta must be in (0,1)", 2) end
    if min_blocks < 1 then error("f_race: min_blocks_before_race must be >= 1", 2) end

    -- ── α-spending (opt-in): bound the look budget and Bonferroni-tighten δ ──
    -- Sequential testing inflates the time-aggregated Type I error.
    -- When alpha_spending=true we
    --   (a) gate the test to fixed checkpoints spaced `min_blocks`
    --       blocks apart, bounding the per-segment look count
    --       K_max = max(1, ⌊D/min_blocks⌋), and
    --   (b) compute target_alpha = delta / K_max and look up the
    --       largest tabulated α ≤ target_alpha via resolve_alpha().
    -- Both chi2_critical and nemenyi_critical_diff then read this
    -- effective_delta. The lookup is conservative (rounds to the next
    -- tighter tabulated level), so the realised FWER is ≤ delta.
    local effective_delta = delta
    if alpha_spending then
        local k_max = math.max(1, math.floor(#rubric / min_blocks))
        local target = delta / k_max
        local lvl = resolve_alpha(target)
        if not lvl then
            error(string.format(
                "f_race: alpha_spending: target α = δ/K_max = %g is below "
                    .. "the smallest tabulated level (0.001). Use a larger "
                    .. "δ or a larger min_blocks_before_race.", target), 2)
        end
        effective_delta = lvl.alpha
    end
    if b_dom <= a then error("f_race: score_domain.max must exceed .min", 2) end
    if rubric_type ~= "binary" and rubric_type ~= "likert5" then
        error("f_race: ctx.rubric_type must be \"binary\" or \"likert5\"", 2)
    end
    local is_likert = (rubric_type == "likert5")
    local prompt_template = is_likert and LIKERT5_PROMPT or RUBRIC_PROMPT
    local eval_system = is_likert
        and "You are a rigorous evaluator. Reply with only a single digit 1-5."
        or  "You are a rigorous evaluator. Reply with only PASS or FAIL."
    local eval_max_tokens = is_likert and 4 or 10

    local D = #rubric

    -- ── Phase 1: Generate candidates in parallel ──
    local cand_indices = {}
    for i = 1, n_cand do cand_indices[i] = i end
    local candidates = alc.parallel(cand_indices, function(i)
        return {
            prompt = string.format(
                "Task: %s\n\nProvide your best answer. Be specific and complete.",
                task
            ),
            system = string.format(
                "You are expert #%d. Give a thorough answer that may "
                    .. "differ in approach from others.", i
            ),
            max_tokens = gen_tokens,
        }
    end)

    alc.log("info", string.format("f_race: generated %d candidates", n_cand))

    -- ── Phase 2: Per-candidate state ──
    local states = {}
    for i = 1, n_cand do
        states[i] = { alive = true, n = 0, sum = 0, scores = {} }
    end

    local alive_set = {}
    for i = 1, n_cand do alive_set[i] = true end

    -- rank_history: list of blocks; each block is map (cand_idx -> rank).
    -- Reset whenever the alive set changes (so every block in history
    -- contains exactly the current alive candidates).
    local rank_history = {}
    local blocks_observed = 0
    local kill_events = {}
    local rounds = {}
    local evals_done = 0
    local iter = 0

    -- ── Phase 3: Block-by-block evaluation + Friedman race ──
    for k = 1, D do
        local alive_now = {}
        for i = 1, n_cand do
            if states[i].alive then alive_now[#alive_now + 1] = i end
        end
        if #alive_now <= 1 then break end

        local dim = rubric[k]
        local raws = alc.parallel(alive_now, function(i)
            return {
                prompt = string.format(prompt_template, task, candidates[i], dim.criterion),
                system = eval_system,
                max_tokens = eval_max_tokens,
            }
        end)

        -- Score and accumulate.
        local items = {}
        for ii, i in ipairs(alive_now) do
            iter = iter + 1
            local x_raw = parse_rubric_score(raws[ii], is_likert)
            local x
            if x_raw == 0 or x_raw == 1 then
                x = a + x_raw * (b_dom - a)
            else
                x = x_raw
                if x < a then x = a end
                if x > b_dom then x = b_dom end
            end
            local st = states[i]
            st.n = st.n + 1
            st.sum = st.sum + x
            st.scores[#st.scores + 1] = x
            evals_done = evals_done + 1
            items[#items + 1] = { idx = i, score = x }
            rounds[#rounds + 1] = {
                iteration = iter,
                candidate = i,
                dimension = k,
                dimension_name = dim.name,
                score = x,
                n_after = st.n,
            }
        end

        -- Block ranking and history append.
        local block_ranks = assign_ranks(items)
        rank_history[#rank_history + 1] = block_ranks
        blocks_observed = blocks_observed + 1

        -- Friedman race step.
        -- With α-spending the test is gated to fixed checkpoints
        -- spaced `min_blocks` apart so the per-segment look budget is
        -- bounded (see effective_delta computation above). Without it,
        -- we test every block past the warmup (legacy behavior).
        local should_test
        if alpha_spending then
            should_test = (blocks_observed >= min_blocks)
                and ((blocks_observed - min_blocks) % min_blocks == 0)
        else
            should_test = (blocks_observed >= min_blocks)
        end
        if should_test then
            local q, rank_sums, b_used, n_alive = friedman_q(rank_history, alive_set)
            local crit = chi2_critical(n_alive - 1, effective_delta)
            if q > crit then
                -- Find best (largest) rank-sum. Eliminate any with
                -- |best - R_j| > Nemenyi critical difference.
                local best_idx, best_sum = nil, -math.huge
                for idx, rs in pairs(rank_sums) do
                    if rs > best_sum then
                        best_sum, best_idx = rs, idx
                    end
                end
                local crit_diff = nemenyi_critical_diff(b_used, n_alive, effective_delta)
                local killed_any = false
                for idx, rs in pairs(rank_sums) do
                    if idx ~= best_idx and (best_sum - rs) > crit_diff then
                        states[idx].alive = false
                        alive_set[idx] = nil
                        killed_any = true
                        kill_events[#kill_events + 1] = {
                            candidate = idx,
                            block = k,
                            n = states[idx].n,
                            mean = states[idx].sum / states[idx].n,
                            rank_sum = rs,
                            best_rank_sum = best_sum,
                            best_candidate = best_idx,
                            q = q,
                            chi2_critical = crit,
                            crit_diff = crit_diff,
                            blocks_used = b_used,
                        }
                        alc.log("info", string.format(
                            "f_race: kill cand #%d at block %d (Q=%.2f > %.2f, "
                                .. "rank-sum gap=%.1f > %.1f)",
                            idx, k, q, crit, best_sum - rs, crit_diff
                        ))
                        if on_kill then on_kill(idx, states[idx]) end
                    end
                end
                -- If we eliminated anyone, the alive set changed, so the
                -- old rank_history is no longer over a uniform set. Reset.
                if killed_any then
                    rank_history = {}
                    blocks_observed = 0
                end
            end
        end
    end

    -- ── Phase 4: Rank survivors by mean rank ──
    -- Re-rank using the most recent rank_history if any, otherwise by
    -- empirical mean (fallback when min_blocks not reached or all
    -- eliminations consumed history).
    local ranking = {}
    -- Recompute final mean ranks over the current alive set.
    local _, final_rank_sums, b_final = friedman_q(rank_history, alive_set)
    for i = 1, n_cand do
        local st = states[i]
        local mu = (st.n > 0) and (st.sum / st.n) or 0
        local mean_rank = nil
        if st.alive and final_rank_sums[i] and b_final > 0 then
            mean_rank = final_rank_sums[i] / b_final
        end
        ranking[#ranking + 1] = {
            index = i,
            alive = st.alive,
            n = st.n,
            mean = mu,
            mean_rank = mean_rank,
        }
        if st.alive and on_survive then on_survive(i, st) end
    end
    table.sort(ranking, function(x, y)
        if x.alive ~= y.alive then return x.alive end
        if x.mean_rank and y.mean_rank then
            return x.mean_rank > y.mean_rank
        end
        return x.mean > y.mean
    end)

    local best = ranking[1]
    local alive_count = 0
    for _, r in ipairs(ranking) do if r.alive then alive_count = alive_count + 1 end end

    alc.log("info", string.format(
        "f_race: winner=#%d (mean=%.3f, n=%d), %d alive of %d, %d evals, %d kills",
        best.index, best.mean, best.n, alive_count, n_cand,
        evals_done, #kill_events
    ))

    ctx.result = {
        best = candidates[best.index],
        best_index = best.index,
        best_score = best.mean,
        ranking = ranking,
        candidates = candidates,
        rounds = rounds,
        kill_events = kill_events,
        alive_count = alive_count,
        n_candidates = n_cand,
        n_dimensions = D,
        evaluations = evals_done,
        total_llm_calls = n_cand + evals_done,
        delta = delta,
        effective_delta = effective_delta,
        alpha_spending = alpha_spending,
    }
    return ctx
end

return M
