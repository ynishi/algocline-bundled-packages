--- slm_mux — Pure Computation pkg for orchestrating Small Language
--- Models via complementarity-driven K-subset selection.
---
--- Based on:
---   Wang, Wan, Kang, Chen, Xie, Krishna, Reddi, Du
---   "SLM-MUX: Orchestrating Small Language Models for Reasoning"
---   (arXiv:2510.05077, 2025-10-06; ICLR 2026 Poster)
---
--- Implements paper §3.1 Algorithm 1 (inference-time confidence
--- selection) and §3.2 𝒪(S) = UnionAcc(S) − λ · Contradiction(S) with
--- exhaustive K-subset search.
---
--- Core formulas (paper §3.1, §3.2):
---
---   Per-model confidence (Algorithm 1, Lines 6-7):
---     f_i(y) = (1/k) · Σ_{j=1}^{k} 𝟙(y_i^(j) = y)
---     y_i*   = argmax_y f_i(y)
---     s_i    = f_i(y_i*)
---
---   Inference-time selection (Algorithm 1, Lines 9-13):
---     S_max = max_{i ∈ S} s_i
---     I*    = { i ∈ S : s_i = S_max }
---     return y_{i*}*  where i* = (|I*|=1 ? unique : argmax_{i ∈ I*} a_i)
---
---   Subset objective (§3.2):
---     UnionAcc(S)      = (1/|𝒟|) · Σ_x 𝟙{ ∃ m ∈ S : m(x) is correct }
---     Contradiction(S) = (1/|𝒟|) · Σ_x 𝟙{ ∃ m_1 ∈ S consistently wrong on x
---                                          ∧ ∃ m_2 ∈ S correct on x }
---     𝒪(S)            = UnionAcc(S) − λ · Contradiction(S)
---
---   K-subset selection (§3.2):
---     argmax_{S ⊆ pool, |S|=K} 𝒪(S)  via exhaustive enumeration.
---
---   Inference-time confidence concentration (out-of-paper reference;
---   not stated in arXiv:2510.05077, derived from standard Hoeffding
---   union bound on Bernoulli sample-mean concentration of s_i):
---     Pr( î = i* ) ≥ 1 − 2(K−1) · exp( −N · γ² / 2 )
---     where N = sample count per model used to estimate s_i,
---           K = subset size,
---           p_i = population argmax frequency of model i
---                 (s_i is its sample-based estimate),
---           γ = p_{i*} − max_{j ≠ i*} p_j > 0  (true confidence gap).
---     Sample-size guidance reference only — the paper itself does not
---     derive a concentration bound on Algorithm 1's selection event.
---
--- ═══ PAPER FIDELITY & INJECTION POINTS ═══════════════════════════════
--- Paper-faithful defaults:
---   * λ = 1.0                        (paper §4.3)
---   * search_method = "exhaustive"   (paper §3.2 explicit)
---   * consistency_threshold = 0.0    (= "y_star is wrong only" Contradiction)
---   * s_tie_break = "validation_accuracy"  (paper §3.1 Algorithm 1)
---
--- REQUIRED injection points:
---   * profiles  — REQUIRED. Array of N SLM profiles, each shaped
---                 { samples = string[][M][k], correct = string[M],
---                   validation_accuracy? = number ∈ [0,1] }.
---                 Caller pre-computes the calibration tensor (paper §4.3
---                 uses 500 questions). pkg never calls alc.llm.
---   * k         — REQUIRED. Subset size 1 ≤ k ≤ N for select_subset/run.
---
--- OPTIONAL paper-faithful injection points:
---   * lambda                — Contradiction weight (default 1.0, §4.3).
---   * tie_break_yi          — argmax_y f_i(y) tie-break:
---                             "lexicographic" (default) | "first_in_samples"
---                             | "uniform_random". Paper §3.1 does not
---                             numerically fix this; defaults remain
---                             paper-faithful.
---   * subset_tie_break      — 𝒪(S) tie across subsets:
---                             "first_found" (default) | "smaller_K"
---                             | "lexicographic_on_indices". Paper §3.2
---                             does not specify.
---                             NOTE: select_subset enumerates fixed K
---                             only, so "smaller_K" is a no-op in the
---                             current API; preserved in the enum for
---                             consistency with future variable-K APIs.
---   * s_tie_break           — s_i tie at inference: "validation_accuracy"
---                             (default, paper-faithful) is the only safe
---                             value; any other choice breaks Algorithm 1.
---
--- OPTIONAL non-paper-faithful injection points (caller must accept the
---                                                  loss of paper guarantees):
---   * search_method = "greedy_forward" | "greedy_backward"
---                       — Forward / backward greedy K-subset search.
---                         **NOT paper-faithful**: §3.2 explicitly uses
---                         exhaustive search. Loses globally-optimal
---                         guarantee on 𝒪(S). Practical fallback when
---                         C(N, K) becomes prohibitive (caller's call).
---                         Per-step 𝒪 ties are resolved via the same
---                         `subset_tie_break` mode as exhaustive search,
---                         under eps-tolerant comparison.
---   * consistency_threshold > 0.0
---                       — Treat m as "consistently wrong" only when its
---                         most-common-wrong answer dominates with
---                         frequency s_i ≥ τ.
---                         **NOT paper-faithful**: §3.2's formal
---                         Contradiction does not use a frequency
---                         threshold. Provided for sensitivity analysis.
---   * partial_coverage  — Behaviour when a profile is missing entries on
---                         some calibration questions. Default "error"
---                         (fail-fast) is paper-faithful (paper assumes
---                         full coverage). "skip_missing" /
---                         "treat_as_wrong" are NOT paper-faithful research
---                         knobs.
---
--- NOT IN v1 (documented shortfalls):
---   * Online inference orchestration (the test-time inference loop
---     that wires Algorithm 1 to a real LLM). slm_mux exposes
---     subset selection and per-model confidence as pure primitives;
---     callers drive test-time inference with sc / panel / smc_sample /
---     particle_infer, etc.
---   * Calibration data resampling / cross-validation. Caller-side.
---   * Auto-tuning of λ. Caller chooses λ per their dataset / use case.
--- ═══════════════════════════════════════════════════════════════════════
---
--- Usage:
---
---   local mux = require("slm_mux")
---
---   -- One per SLM in the pool:
---   local profiles = {
---     { samples = { {"A","A","A"}, {"B","C","B"}, ... },
---       correct = { "A", "B", ... } },
---     { samples = { ... }, correct = { ... } },
---     ...
---   }
---
---   local r = mux.run(profiles, 2)        -- best 2-subset by 𝒪(S)
---   -- r.selected_indices = { 1, 3 }       (e.g.)
---   -- r.objective        = 0.62
---   -- r.union_acc / r.contradiction / r.search_log / ...
---
---   -- Per-model primitive:
---   local c = mux.confidence({"A","A","B"})   -- → { y_star="A", s=2/3 }
---
--- Category: selection.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "slm_mux",
    version = "0.1.0",
    description = "Complementarity-driven K-subset selection over a "
        .. "pool of small language models. Implements Wang et al. "
        .. "(arXiv:2510.05077, ICLR 2026 Poster) §3.1 Algorithm 1 "
        .. "(confidence-based inference selection) and §3.2 "
        .. "𝒪(S) = UnionAcc(S) − λ · Contradiction(S) with exhaustive "
        .. "search. Pure Computation pkg — no alc.llm calls; caller "
        .. "drives test-time inference. Fills selection-axis gap not "
        .. "covered by router_*/cascade (single-best routing) or "
        .. "ab_select/mbr_select (single-best selection): N→K subset "
        .. "complementarity over a pre-computed calibration tensor.",
    category = "selection",
}

-- Paper-faithful defaults; magic numbers live here so no entry hard-codes.
-- See Lines 47-56 above for paper § references.
M._defaults = {
    lambda                = 1.0,         -- §4.3
    search_method         = "exhaustive",-- §3.2 explicit
    tie_break_yi          = "lexicographic",
    subset_tie_break      = "first_found",
    s_tie_break           = "validation_accuracy",  -- §3.1 Alg.1
    consistency_threshold = 0.0,         -- paper-faithful Contradiction
    partial_coverage      = "error",     -- paper assumes full coverage
}

-- ─── Shape definitions (local) ───

local profile_shape = T.shape({
    samples = T.array_of(T.array_of(T.string))
        :describe("samples[m][j] = j-th sampled answer for calibration "
            .. "question m. Length M (calibration set size); inner "
            .. "length k (paper §4.2 default 3)."),
    correct = T.array_of(T.string)
        :describe("correct[m] = ground-truth answer for question m. "
            .. "Length M, must align with samples."),
    validation_accuracy = T.number:is_optional()
        :describe("a_i ∈ [0,1] used for s_i tie-break (paper §3.1 "
            .. "Algorithm 1). If nil, computed internally from "
            .. "samples + correct."),
}, { open = true })

local confidence_input_shape = T.array_of(T.string)

local confidence_opts_shape = T.shape({
    tie_break_yi = T.one_of({ "lexicographic", "first_in_samples", "uniform_random" })
        :is_optional()
        :describe("argmax_y f_i(y) tie-break (default 'lexicographic')"),
    rng = T.any:is_optional()
        :describe("Optional rng function () → number ∈ [0,1) for 'uniform_random'"),
}, { open = true })

local confidence_result_shape = T.shape({
    y_star = T.string:describe("argmax_y f_i(y) — most common sample"),
    s      = T.number:describe("f_i(y_star) ∈ [0,1] — fraction of samples equal to y_star"),
    k      = T.number:describe("Sample count used for f_i (= #samples)"),
}, { open = true })

local score_subset_opts_shape = T.shape({
    lambda                = T.number:is_optional(),
    tie_break_yi          = T.one_of({ "lexicographic", "first_in_samples", "uniform_random" }):is_optional(),
    consistency_threshold = T.number:is_optional()
        :describe("0.0 (paper-faithful) | > 0 NOT paper-faithful"),
    partial_coverage      = T.one_of({ "error", "skip_missing", "treat_as_wrong" }):is_optional()
        :describe("'error' (default, paper-faithful) | NOT paper-faithful alternates"),
}, { open = true })

local score_subset_result_shape = T.shape({
    union_acc     = T.number,
    contradiction = T.number,
    objective     = T.number,
}, { open = true })

local select_subset_opts_shape = T.shape({
    lambda                = T.number:is_optional(),
    search_method         = T.one_of({ "exhaustive", "greedy_forward", "greedy_backward" }):is_optional(),
    tie_break_yi          = T.one_of({ "lexicographic", "first_in_samples", "uniform_random" }):is_optional(),
    subset_tie_break      = T.one_of({ "first_found", "smaller_K", "lexicographic_on_indices" }):is_optional(),
    consistency_threshold = T.number:is_optional(),
    partial_coverage      = T.one_of({ "error", "skip_missing", "treat_as_wrong" }):is_optional(),
}, { open = true })

local per_model_confidence_shape = T.shape({
    y_star              = T.string,
    s                   = T.number,
    validation_accuracy = T.number:is_optional(),
}, { open = true })

local inference_select_opts_shape = T.shape({
    s_tie_break = T.one_of({ "validation_accuracy", "first_found", "lexicographic_on_indices" }):is_optional(),
}, { open = true })

local inference_select_result_shape = T.shape({
    selected_model_idx = T.number,
    selected_y         = T.string,
    s                  = T.number:describe("s_{selected} value at selection time"),
    tie_size           = T.number:describe("|I*| (= 1 when no tie)"),
    tie_break_used     = T.string
        :describe("Which tie-break path actually ran: 'no_tie' "
            .. "(|I*|=1) | 'validation_accuracy' (paper §3.1 Algorithm 1) "
            .. "| 'first_found' | 'lexicographic_on_indices' "
            .. "| 'first_found_fallback_no_validation_accuracy' "
            .. "(s_tb='validation_accuracy' but no tied candidate has "
            .. "validation_accuracy — paper guarantee not met; caller "
            .. "should provide validation_accuracy to recover)"),
}, { open = true })

local run_opts_shape = T.shape({
    lambda                = T.number:is_optional(),
    search_method         = T.one_of({ "exhaustive", "greedy_forward", "greedy_backward" }):is_optional(),
    tie_break_yi          = T.one_of({ "lexicographic", "first_in_samples", "uniform_random" }):is_optional(),
    subset_tie_break      = T.one_of({ "first_found", "smaller_K", "lexicographic_on_indices" }):is_optional(),
    consistency_threshold = T.number:is_optional(),
    partial_coverage      = T.one_of({ "error", "skip_missing", "treat_as_wrong" }):is_optional(),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        confidence = {
            args   = { confidence_input_shape, confidence_opts_shape:is_optional() },
            result = confidence_result_shape,
        },
        score_subset = {
            args   = { T.array_of(profile_shape), T.array_of(T.number), score_subset_opts_shape:is_optional() },
            result = score_subset_result_shape,
        },
        select_subset = {
            args   = { T.array_of(profile_shape), T.number, select_subset_opts_shape:is_optional() },
            result = "slm_muxed",
        },
        inference_select = {
            args   = { T.array_of(per_model_confidence_shape), inference_select_opts_shape:is_optional() },
            result = inference_select_result_shape,
        },
        run = {
            args   = { T.array_of(profile_shape), T.number, run_opts_shape:is_optional() },
            result = "slm_muxed",
        },
    },
}

-- ─── Validation helpers ───

local function check_string_array(arr, label, entry)
    if type(arr) ~= "table" then
        error(string.format(
            "slm_mux.%s: %s must be an array of strings, got %s",
            entry, label, type(arr)), 3)
    end
    local n = 0
    for k, _ in pairs(arr) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            error(string.format(
                "slm_mux.%s: %s must be a 1-based dense array",
                entry, label), 3)
        end
        if k > n then n = k end
    end
    for i = 1, n do
        if type(arr[i]) ~= "string" then
            error(string.format(
                "slm_mux.%s: %s[%d] must be a string, got %s",
                entry, label, i, type(arr[i])), 3)
        end
    end
    return n
end

local function check_lambda(lambda, entry)
    if type(lambda) ~= "number" then
        error(string.format(
            "slm_mux.%s: lambda must be a number, got %s",
            entry, type(lambda)), 3)
    end
    if lambda < 0 then
        error(string.format(
            "slm_mux.%s: lambda must be >= 0, got %s",
            entry, tostring(lambda)), 3)
    end
end

local function check_consistency_threshold(threshold, entry)
    if type(threshold) ~= "number" then
        error(string.format(
            "slm_mux.%s: consistency_threshold must be a number, got %s",
            entry, type(threshold)), 3)
    end
    if threshold < 0 or threshold > 1 then
        error(string.format(
            "slm_mux.%s: consistency_threshold must be in [0, 1], got %s",
            entry, tostring(threshold)), 3)
    end
end

local function check_profile(p, idx, entry)
    if type(p) ~= "table" then
        error(string.format(
            "slm_mux.%s: profiles[%d] must be a table, got %s",
            entry, idx, type(p)), 3)
    end
    if type(p.samples) ~= "table" then
        error(string.format(
            "slm_mux.%s: profiles[%d].samples must be an array, got %s",
            entry, idx, type(p.samples)), 3)
    end
    if type(p.correct) ~= "table" then
        error(string.format(
            "slm_mux.%s: profiles[%d].correct must be an array, got %s",
            entry, idx, type(p.correct)), 3)
    end
end

local function array_length(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) == "number" and k >= 1 and k == math.floor(k) and k > n then
            n = k
        end
    end
    return n
end

local function check_profiles(profiles, entry)
    if type(profiles) ~= "table" then
        error(string.format(
            "slm_mux.%s: profiles must be an array, got %s",
            entry, type(profiles)), 3)
    end
    local n = array_length(profiles)
    if n == 0 then
        error(string.format(
            "slm_mux.%s: profiles must be non-empty",
            entry), 3)
    end
    local m_ref
    for i = 1, n do
        check_profile(profiles[i], i, entry)
        local m_samples = array_length(profiles[i].samples)
        local m_correct = array_length(profiles[i].correct)
        if m_samples ~= m_correct then
            error(string.format(
                "slm_mux.%s: profiles[%d].samples (len %d) must align with .correct (len %d)",
                entry, i, m_samples, m_correct), 3)
        end
        if m_ref == nil then
            m_ref = m_samples
        elseif m_ref ~= m_samples then
            error(string.format(
                "slm_mux.%s: profiles[%d] has %d cal questions, expected %d (must match profiles[1])",
                entry, i, m_samples, m_ref), 3)
        end
    end
    return n, m_ref
end

local function check_subset_indices(subset, n, entry)
    if type(subset) ~= "table" then
        error(string.format(
            "slm_mux.%s: subset_indices must be an array, got %s",
            entry, type(subset)), 3)
    end
    local len = array_length(subset)
    if len == 0 then
        error(string.format(
            "slm_mux.%s: subset_indices must be non-empty",
            entry), 3)
    end
    local seen = {}
    for i = 1, len do
        local idx = subset[i]
        if type(idx) ~= "number" or idx < 1 or idx > n or idx ~= math.floor(idx) then
            error(string.format(
                "slm_mux.%s: subset_indices[%d]=%s out of range [1,%d]",
                entry, i, tostring(idx), n), 3)
        end
        if seen[idx] then
            error(string.format(
                "slm_mux.%s: subset_indices contains duplicate %d",
                entry, idx), 3)
        end
        seen[idx] = true
    end
    return len
end

local function check_k(k, n, entry)
    if type(k) ~= "number" or k ~= math.floor(k) then
        error(string.format(
            "slm_mux.%s: k must be a positive integer, got %s",
            entry, tostring(k)), 3)
    end
    if k < 1 or k > n then
        error(string.format(
            "slm_mux.%s: k=%d must satisfy 1 <= k <= N (N=%d)",
            entry, k, n), 3)
    end
end

-- ─── Pure helpers (paper §3.1, §3.2) ───

-- Floating-point eps for 𝒪(S) tie collection. Subsets with objectives
-- closer than this are treated as a tie (deterministic enumeration of
-- the §3.2 argmax set under bit-rounding noise).
local OBJ_EPS = 1e-12

local function obj_eq(a, b)
    return math.abs(a - b) <= OBJ_EPS
end

local function obj_gt(a, b)
    return (a - b) > OBJ_EPS
end

-- frequency table: (samples, n) → { [string] = count }, n_unique
local function frequencies(samples, n)
    local freq = {}
    local nu = 0
    for i = 1, n do
        local y = samples[i]
        if freq[y] == nil then
            freq[y] = 1
            nu = nu + 1
        else
            freq[y] = freq[y] + 1
        end
    end
    return freq, nu
end

-- argmax_y f_i(y) with tie-break.
-- Returns y_star, max_count.
local function argmax_y(freq, samples_array, n, tie_break, rng)
    local max_count = -1
    local ties = {}        -- list of strings tied at max_count
    for y, c in pairs(freq) do
        if c > max_count then
            max_count = c
            ties = { y }
        elseif c == max_count then
            ties[#ties + 1] = y
        end
    end
    if #ties == 1 then
        return ties[1], max_count
    end
    -- tie-break
    if tie_break == "first_in_samples" then
        local seen = {}
        for _, y in ipairs(ties) do seen[y] = true end
        for i = 1, n do
            if seen[samples_array[i]] then
                return samples_array[i], max_count
            end
        end
        -- unreachable: ties came from these samples
        return ties[1], max_count
    elseif tie_break == "uniform_random" then
        local r = rng or math.random
        -- Prefer rng() when caller passes a function, fallback to math.random.
        local pick
        if type(r) == "function" then
            pick = math.floor(r() * #ties) + 1
            if pick > #ties then pick = #ties end
            if pick < 1 then pick = 1 end
        else
            pick = math.random(#ties)
        end
        return ties[pick], max_count
    else  -- "lexicographic" (default)
        table.sort(ties)
        return ties[1], max_count
    end
end

-- Public-shape helpers wrap the same primitive.
local function confidence_of(samples, opts, entry)
    entry = entry or "confidence"
    local n = check_string_array(samples, "samples", entry)
    if n == 0 then
        error(string.format(
            "slm_mux.%s: samples must be non-empty",
            entry), 3)
    end
    opts = opts or {}
    local tie_break = opts.tie_break_yi or M._defaults.tie_break_yi
    local rng = opts.rng
    local freq = frequencies(samples, n)
    local y_star, max_count = argmax_y(freq, samples, n, tie_break, rng)
    return {
        y_star = y_star,
        s      = max_count / n,
        k      = n,
    }
end

-- Compute most-common answer for profile p at question m.
-- Returns (y_star, s, missing) where missing=true only when
-- partial_coverage="treat_as_wrong" and the entry was absent.
-- Returns (nil, nil, false) for "skip_missing" path.
local function profile_y_star(profile, m, tie_break, rng, partial_coverage, entry)
    local samples_m = profile.samples[m]
    if type(samples_m) ~= "table" or array_length(samples_m) == 0 then
        if partial_coverage == "skip_missing" then
            return nil, nil, false
        elseif partial_coverage == "treat_as_wrong" then
            return nil, 0, true   -- missing = true; no magic string
        else  -- "error"
            error(string.format(
                "slm_mux.%s: profile.samples[%d] missing or empty (use opts.partial_coverage to override)",
                entry, m), 3)
        end
    end
    local n = array_length(samples_m)
    -- assume already validated as string array at higher level for run paths
    local freq = frequencies(samples_m, n)
    local y_star, max_count = argmax_y(freq, samples_m, n, tie_break, rng)
    return y_star, max_count / n, false
end

-- §3.2 indicator: model m correct on question x.
-- "m(x) is correct" ≡ argmax_y f_m(y) = correct[x].
local function is_correct(profile, m, tie_break, rng, partial_coverage, entry)
    local y_star, _, missing = profile_y_star(profile, m, tie_break, rng, partial_coverage, entry)
    if missing then return false end           -- treat_as_wrong path
    if y_star == nil then return nil end       -- skip_missing path
    return y_star == profile.correct[m]
end

-- §3.2 indicator: model m consistently wrong on question x.
-- Default (paper-faithful, threshold = 0): y_star ≠ correct.
-- Threshold > 0 (NOT paper-faithful): also require s ≥ threshold.
local function is_consistently_wrong(profile, m, tie_break, rng, threshold, partial_coverage, entry)
    local y_star, s, missing = profile_y_star(profile, m, tie_break, rng, partial_coverage, entry)
    if missing then return true end            -- treat_as_wrong → consistently wrong
    if y_star == nil then return nil end       -- skip_missing path
    if y_star == profile.correct[m] then return false end
    if (threshold or 0) > 0 and (s or 0) < threshold then
        return false
    end
    return true
end

-- §3.2: UnionAcc(S).
local function union_acc(profiles, subset_indices, opts, entry)
    entry = entry or "score_subset"
    opts = opts or {}
    local tie_break = opts.tie_break_yi or M._defaults.tie_break_yi
    local partial   = opts.partial_coverage or M._defaults.partial_coverage
    local rng       = opts.rng
    local k_subset  = #subset_indices
    local m_count   = array_length(profiles[1].correct)
    if m_count == 0 then
        error(string.format(
            "slm_mux.%s: profiles have empty calibration set",
            entry), 3)
    end
    local hits = 0
    local effective_M = 0
    for x = 1, m_count do
        local any_correct = false
        local any_skipped = true   -- becomes false if at least one model is observed
        for j = 1, k_subset do
            local r = is_correct(profiles[subset_indices[j]], x, tie_break, rng, partial, entry)
            if r ~= nil then
                any_skipped = false
                if r then any_correct = true end
            end
        end
        if not any_skipped then
            effective_M = effective_M + 1
            if any_correct then hits = hits + 1 end
        end
    end
    if effective_M == 0 then
        error(string.format(
            "slm_mux.%s: no calibration question has any observed sample after partial_coverage filter",
            entry), 3)
    end
    return hits / effective_M, effective_M
end

-- §3.2: Contradiction(S).
local function contradiction(profiles, subset_indices, opts, entry)
    entry = entry or "score_subset"
    opts = opts or {}
    local tie_break = opts.tie_break_yi or M._defaults.tie_break_yi
    local threshold = opts.consistency_threshold or M._defaults.consistency_threshold
    local partial   = opts.partial_coverage or M._defaults.partial_coverage
    local rng       = opts.rng
    local k_subset  = #subset_indices
    local m_count   = array_length(profiles[1].correct)
    local hits = 0
    local effective_M = 0
    for x = 1, m_count do
        local any_wrong_consistent = false
        local any_correct = false
        local any_observed = false
        for j = 1, k_subset do
            local p = profiles[subset_indices[j]]
            local cw = is_consistently_wrong(p, x, tie_break, rng, threshold, partial, entry)
            local co = is_correct(p, x, tie_break, rng, partial, entry)
            if cw ~= nil then any_observed = true end
            if cw then any_wrong_consistent = true end
            if co then any_correct = true end
        end
        if any_observed then
            effective_M = effective_M + 1
            if any_wrong_consistent and any_correct then
                hits = hits + 1
            end
        end
    end
    if effective_M == 0 then
        -- Symmetric with union_acc: if no calibration question has any
        -- observed sample (after partial_coverage filter), the §3.2
        -- Contradiction rate is undefined. Fail-fast instead of
        -- silently returning 0 (the public path always reaches
        -- union_acc first, which raises the same way; this guards the
        -- _internal.contradiction test hook against silent 0).
        error(string.format(
            "slm_mux.%s: no calibration question has any observed sample after partial_coverage filter",
            entry), 3)
    end
    return hits / effective_M, effective_M
end

-- §3.2: 𝒪(S).
local function objective_of(profiles, subset_indices, opts, entry)
    entry = entry or "score_subset"
    opts = opts or {}
    local lambda = opts.lambda or M._defaults.lambda
    local ua, _ = union_acc(profiles, subset_indices, opts, entry)
    local cn, _ = contradiction(profiles, subset_indices, opts, entry)
    return {
        union_acc     = ua,
        contradiction = cn,
        objective     = ua - lambda * cn,
    }
end

-- Iterator over k-subsets of {1..n} in lexicographic order.
local function enumerate_subsets(n, k)
    local idx = {}
    for i = 1, k do idx[i] = i end
    local started = false
    return function()
        if not started then
            started = true
            -- copy
            local out = {}
            for i = 1, k do out[i] = idx[i] end
            return out
        end
        -- bump rightmost movable index
        local i = k
        while i >= 1 do
            if idx[i] < n - (k - i) then
                idx[i] = idx[i] + 1
                for j = i + 1, k do idx[j] = idx[j - 1] + 1 end
                local out = {}
                for j = 1, k do out[j] = idx[j] end
                return out
            end
            i = i - 1
        end
        return nil
    end
end

-- Tie-break across multiple subsets sharing the same 𝒪.
-- candidates: array of { subset_indices, objective, union_acc, contradiction }
-- mode: "first_found" | "smaller_K" | "lexicographic_on_indices".
local function tie_break_subset(candidates, mode)
    if #candidates == 1 then return candidates[1] end
    if mode == "smaller_K" then
        local best = candidates[1]
        for i = 2, #candidates do
            if #candidates[i].subset_indices < #best.subset_indices then
                best = candidates[i]
            end
        end
        return best
    elseif mode == "lexicographic_on_indices" then
        local best = candidates[1]
        for i = 2, #candidates do
            local a, b = candidates[i].subset_indices, best.subset_indices
            local na, nb = #a, #b
            local lim = na < nb and na or nb
            local cmp = 0
            for j = 1, lim do
                if a[j] < b[j] then cmp = -1; break
                elseif a[j] > b[j] then cmp = 1; break
                end
            end
            if cmp == 0 and na < nb then cmp = -1
            elseif cmp == 0 and na > nb then cmp = 1
            end
            if cmp < 0 then best = candidates[i] end
        end
        return best
    else  -- "first_found"
        return candidates[1]
    end
end

-- Forward-greedy K-subset search (NOT paper-faithful).
-- Start empty, add the index that maximises 𝒪(S ∪ {i}) at each step.
-- Per-step ties on the incremental 𝒪 are resolved with the same
-- subset_tie_break mode used by exhaustive search; passing through eps-
-- tolerant comparison so caller-visible behaviour matches the
-- exhaustive path on degenerate fixtures.
local function greedy_forward_search(profiles, k, opts)
    local n = array_length(profiles)
    local selected = {}
    local available = {}
    for i = 1, n do available[i] = true end
    local subset_tb = (opts and opts.subset_tie_break) or M._defaults.subset_tie_break
    local search_log = {}
    while #selected < k do
        local best_obj = -math.huge
        local ties = {}
        local trials_by_i = {}    -- struct keyed by candidate i (for available[] update)
        for i = 1, n do
            if available[i] then
                local trial = {}
                for j = 1, #selected do trial[j] = selected[j] end
                trial[#trial + 1] = i
                table.sort(trial)
                local r = objective_of(profiles, trial, opts, "select_subset")
                local entry_struct = {
                    subset_indices = trial, objective = r.objective,
                    union_acc = r.union_acc, contradiction = r.contradiction,
                    _added = i,
                }
                if obj_gt(r.objective, best_obj) then
                    best_obj = r.objective
                    ties = { entry_struct }
                elseif obj_eq(r.objective, best_obj) then
                    ties[#ties + 1] = entry_struct
                end
                trials_by_i[i] = entry_struct
            end
        end
        if #ties == 0 then break end
        local picked = tie_break_subset(ties, subset_tb)
        selected = picked.subset_indices
        available[picked._added] = false
        picked._added = nil
        search_log[#search_log + 1] = picked
    end
    return search_log[#search_log], search_log
end

-- Backward-greedy K-subset search (NOT paper-faithful).
-- Start with all N, remove the index whose removal maximises 𝒪 until K remain.
-- Per-step ties on 𝒪 after removal use the same subset_tie_break mode.
local function greedy_backward_search(profiles, k, opts)
    local n = array_length(profiles)
    local current = {}
    for i = 1, n do current[i] = i end
    local subset_tb = (opts and opts.subset_tie_break) or M._defaults.subset_tie_break
    local search_log = {}
    -- log initial
    local r0 = objective_of(profiles, current, opts, "select_subset")
    local current_copy = {}
    for i = 1, #current do current_copy[i] = current[i] end
    search_log[#search_log + 1] = { subset_indices = current_copy,
        objective = r0.objective, union_acc = r0.union_acc, contradiction = r0.contradiction }
    while #current > k do
        local best_obj = -math.huge
        local ties = {}
        for pos = 1, #current do
            local trial = {}
            for i = 1, #current do
                if i ~= pos then trial[#trial + 1] = current[i] end
            end
            local r = objective_of(profiles, trial, opts, "select_subset")
            local entry_struct = {
                subset_indices = trial, objective = r.objective,
                union_acc = r.union_acc, contradiction = r.contradiction,
            }
            if obj_gt(r.objective, best_obj) then
                best_obj = r.objective
                ties = { entry_struct }
            elseif obj_eq(r.objective, best_obj) then
                ties[#ties + 1] = entry_struct
            end
        end
        if #ties == 0 then break end
        local picked = tie_break_subset(ties, subset_tb)
        current = picked.subset_indices
        search_log[#search_log + 1] = picked
    end
    return search_log[#search_log], search_log
end

-- Compute (or echo) validation_accuracy a_i for a profile.
local function compute_validation_accuracy(profile, tie_break, partial, rng)
    if type(profile.validation_accuracy) == "number" then
        return profile.validation_accuracy
    end
    local m_count = array_length(profile.correct)
    if m_count == 0 then return 0 end
    local hits = 0
    local denom = 0
    for x = 1, m_count do
        local r = is_correct(profile, x, tie_break, rng, partial, "compute_validation_accuracy")
        if r ~= nil then
            denom = denom + 1
            if r then hits = hits + 1 end
        end
    end
    if denom == 0 then return 0 end
    return hits / denom
end

-- ─── Public entries ───

function M.confidence(samples, opts)
    return confidence_of(samples, opts, "confidence")
end

function M.score_subset(profiles, subset_indices, opts)
    local n, _ = check_profiles(profiles, "score_subset")
    check_subset_indices(subset_indices, n, "score_subset")
    opts = opts or {}
    if opts.lambda ~= nil then check_lambda(opts.lambda, "score_subset") end
    if opts.consistency_threshold ~= nil then
        check_consistency_threshold(opts.consistency_threshold, "score_subset")
    end
    return objective_of(profiles, subset_indices, opts, "score_subset")
end

function M.select_subset(profiles, k, opts)
    local n, _ = check_profiles(profiles, "select_subset")
    check_k(k, n, "select_subset")
    opts = opts or {}
    if opts.lambda ~= nil then check_lambda(opts.lambda, "select_subset") end
    if opts.consistency_threshold ~= nil then
        check_consistency_threshold(opts.consistency_threshold, "select_subset")
    end
    local lambda = opts.lambda or M._defaults.lambda
    local search_method = opts.search_method or M._defaults.search_method
    local subset_tb     = opts.subset_tie_break or M._defaults.subset_tie_break

    local best, search_log

    if search_method == "exhaustive" then
        local best_obj = -math.huge
        local ties = {}
        search_log = {}
        for subset in enumerate_subsets(n, k) do
            local r = objective_of(profiles, subset, opts, "select_subset")
            local entry_struct = {
                subset_indices = subset, objective = r.objective,
                union_acc = r.union_acc, contradiction = r.contradiction,
            }
            search_log[#search_log + 1] = entry_struct
            if obj_gt(r.objective, best_obj) then
                best_obj = r.objective
                ties = { entry_struct }
            elseif obj_eq(r.objective, best_obj) then
                ties[#ties + 1] = entry_struct
            end
        end
        best = tie_break_subset(ties, subset_tb)
    elseif search_method == "greedy_forward" then
        best, search_log = greedy_forward_search(profiles, k, opts)
    elseif search_method == "greedy_backward" then
        best, search_log = greedy_backward_search(profiles, k, opts)
    else
        error(string.format(
            "slm_mux.select_subset: unknown search_method '%s' (expected 'exhaustive' | 'greedy_forward' | 'greedy_backward')",
            tostring(search_method)), 2)
    end
    return {
        selected_indices = best.subset_indices,
        objective        = best.objective,
        union_acc        = best.union_acc,
        contradiction    = best.contradiction,
        lambda           = lambda,
        search_method    = search_method,
        search_log       = search_log,
    }
end

function M.inference_select(per_model_confidences, opts)
    if type(per_model_confidences) ~= "table" then
        error(string.format(
            "slm_mux.inference_select: per_model_confidences must be an array, got %s",
            type(per_model_confidences)), 2)
    end
    local n = array_length(per_model_confidences)
    if n == 0 then
        error("slm_mux.inference_select: per_model_confidences must be non-empty", 2)
    end
    opts = opts or {}
    local s_tb = opts.s_tie_break or M._defaults.s_tie_break

    local s_max = -math.huge
    local idx_winners = {}
    for i = 1, n do
        local c = per_model_confidences[i]
        if type(c) ~= "table" or type(c.s) ~= "number" or type(c.y_star) ~= "string" then
            error(string.format(
                "slm_mux.inference_select: per_model_confidences[%d] must have numeric s and string y_star",
                i), 2)
        end
        if c.validation_accuracy ~= nil then
            if type(c.validation_accuracy) ~= "number"
                or c.validation_accuracy ~= c.validation_accuracy   -- NaN
                or c.validation_accuracy < 0
                or c.validation_accuracy > 1 then
                error(string.format(
                    "slm_mux.inference_select: per_model_confidences[%d].validation_accuracy "
                    .. "must satisfy a_i ∈ [0, 1] (paper §3.1 Algorithm 1), got %s",
                    i, tostring(c.validation_accuracy)), 2)
            end
        end
        if c.s > s_max then
            s_max = c.s
            idx_winners = { i }
        elseif c.s == s_max then
            idx_winners[#idx_winners + 1] = i
        end
    end
    local pick_idx
    local tie_break_used
    if #idx_winners == 1 then
        pick_idx = idx_winners[1]
        tie_break_used = "no_tie"
    elseif s_tb == "validation_accuracy" then
        local any_a = false
        for _, i in ipairs(idx_winners) do
            if type(per_model_confidences[i].validation_accuracy) == "number" then
                any_a = true
                break
            end
        end
        if not any_a then
            -- Paper §3.1 Algorithm 1 assumes a_i is available at tie time.
            -- Surface the fallback explicitly instead of silent degradation.
            pick_idx = idx_winners[1]
            tie_break_used = "first_found_fallback_no_validation_accuracy"
        else
            local best_a = -math.huge
            for _, i in ipairs(idx_winners) do
                local a = per_model_confidences[i].validation_accuracy or 0
                if a > best_a then
                    best_a = a
                    pick_idx = i
                end
            end
            tie_break_used = "validation_accuracy"
        end
    elseif s_tb == "lexicographic_on_indices" then
        pick_idx = idx_winners[1]    -- already smallest by enumeration order
        tie_break_used = "lexicographic_on_indices"
    else  -- "first_found"
        pick_idx = idx_winners[1]
        tie_break_used = "first_found"
    end
    return {
        selected_model_idx = pick_idx,
        selected_y         = per_model_confidences[pick_idx].y_star,
        s                  = per_model_confidences[pick_idx].s,
        tie_size           = #idx_winners,
        tie_break_used     = tie_break_used,
    }
end

function M.run(profiles, k, opts)
    -- run is a thin alias of select_subset that pre-validates and
    -- returns the same slm_muxed shape. Kept as a separate entry so
    -- recipes / orch can address the standard "selection step" without
    -- knowing the entry breakdown.
    return M.select_subset(profiles, k, opts)
end

-- ─── Test hooks ───
M._internal = {
    frequencies                  = frequencies,
    argmax_y                     = argmax_y,
    confidence_of                = confidence_of,
    profile_y_star               = profile_y_star,
    is_correct                   = is_correct,
    is_consistently_wrong        = is_consistently_wrong,
    union_acc                    = union_acc,
    contradiction                = contradiction,
    objective_of                 = objective_of,
    enumerate_subsets            = enumerate_subsets,
    tie_break_subset             = tie_break_subset,
    greedy_forward_search        = greedy_forward_search,
    greedy_backward_search       = greedy_backward_search,
    compute_validation_accuracy  = compute_validation_accuracy,
    array_length                 = array_length,
}

-- ─── Malli-style self-decoration (per-entry) ───
M.confidence       = S.instrument(M, "confidence")
M.score_subset     = S.instrument(M, "score_subset")
M.select_subset    = S.instrument(M, "select_subset")
M.inference_select = S.instrument(M, "inference_select")
M.run              = S.instrument(M, "run")

return M
