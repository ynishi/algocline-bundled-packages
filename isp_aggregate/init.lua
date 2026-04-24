--- isp_aggregate — LLM Aggregation via Higher-Order Information.
---
--- Based on: Zhang, Yan, Perron, Wong, Kong
---   "Beyond Majority Voting: LLM Aggregation by Leveraging Higher-
---    Order Information" (arXiv:2510.01499, 2025-10)
---
--- Implements three paper-faithful aggregators from §3 (OW) and §4.2
--- (ISP) plus a non-paper-faithful SP-inspired online path
--- (`meta_prompt_sp`) for environments without a calibration tensor.
---
--- Core formulas (paper §3, §4.2):
---
---   σ_K(x) = exp(x) / (K - 1 + exp(x))                                  (§3)
---   σ_K⁻¹(y) = ln( y (K - 1) / (1 - y) )                                (§3 inverse)
---
---   OW:    f_OW(a_1,...,a_N) = argmax_{s} Σ_i σ_K⁻¹(x_i) · 1{a_i = s}   (Alg.1)
---
---   ISP:   f_ISP(a_1,...,a_N) = argmax_{s} [ Σ_i 1{a_i = s}
---                                          − Σ_i S_ISP(s, i; a) ]       (Eq.5-6)
---
---   S_ISP(s, i; a) = (1/(N-1)) Σ_{j∈[N]\{i}}
---                      (1/(K-1)) Σ_{a' ∈ S, a' ≠ a_j} P(A_i=s | A_j=a')  (Eq.5)
---
---   Empirical estimator (paper §4.3 Thm.3):
---     P̂(A_i=s | A_j=a) = #{A_i^m=s, A_j^m=a} / #{A_j^m=a}   over m=1..M
---
---   OW-L (paper §5.2 Eq.7): x_i estimated by OLS whose target is the
---     empirical 2nd-order conditional tensor P̂(A_i=s|A_j=a) and whose
---     parametric model derives P(A_i=s|A_j=a) from (x_1..x_N) via the
---     Alg.1 generative process. Expanded form is in §E.2 and was NOT
---     reproducible from the extracted sections in v1 — see NOT IN v1.
---
---   OW-I (paper §5.2 Eq.7 直後): x̂_i = #{ f_ISP(a_1..a_N) = a_i } / M.
---     *Name is misleading* — this is NOT isotonic regression.
---     It is a self-labeling accuracy estimate that treats f_ISP's
---     output as the pseudo-ground-truth.
---
--- ═══ PAPER FIDELITY & INJECTION POINTS ════════════════════════════
--- Implementation follows paper §3 Alg.1 (OW), §4.2-4.3 (ISP), and
--- §5.2 Eq.(7) (OW-I). All deviations from the paper default are
--- opt-in via explicit `ctx` knobs — the default path is paper-
--- faithful. This prioritizes correctness over convenience and keeps
--- optimizations / online approximations discoverable.
---
--- Paper-faithful defaults:
---   * `method = "isp"` — default aggregator (paper's primary novelty).
---   * `calibration` — REQUIRED for method ∈ {isp, ow_l, ow_i}.
---     Produced by `M.calibrate` from an M×N answer tensor (M reference
---     questions × N agents, each cell = option label). This mirrors
---     conformal_vote's calibrate/run split — §4.3 Thm.3 gives the
---     finite-sample convergence Õ(√(log(1/δ)/M)) for the S_ISP kernel.
---   * Online round: N agents each answer the 1st-order question once.
---     No meta-prompt ("predict others") by default. The joint pairwise
---     statistics come from the calibration tensor, not from a single
---     question's 2nd-order LLM chatter.
---   * Tie-break: first-match in `ctx.options` order (deterministic).
---     Paper §E.1 uses uniform-random for MV; callers needing that
---     must pass `tie_break = "uniform_random"` explicitly.
---
--- Injection points (stable, documented caller overrides):
---
---   REQUIRED for paper-faithful methods (isp / ow_l / ow_i):
---   * `calibration` — OUTPUT of `M.calibrate(cfg)` pinned into run.
---                     Method MUST match the value used by calibrate.
---
---   REQUIRED for method="ow":
---   * `x_direct`   — N-array of accuracies x_i ∈ (ε, 1-ε). Bypasses
---                     the 2nd-order estimator; the aggregator is then
---                     purely paper §3 Alg.1 with caller-provided x.
---
---   OPTIONAL paper-faithful:
---   * `agents`     — Array of per-agent prompt specs. Each entry is
---                     either a prompt string or a table
---                     { prompt, system?, model?, temperature?, max_tokens? }.
---                     Default: `M._defaults.agents_builder(n)` generates
---                     N diversity-hinted prompts. Follows conformal_vote's
---                     polymorphism pattern (conformal_vote.lua:134-161).
---   * `n`          — Number of agents when `agents` is nil (default 5).
---   * `tie_break`  — "first_in_options" (default, deterministic) or
---                     "uniform_random" (paper §E.1 MV style).
---   * `gen_tokens` — Max tokens per 1st-order LLM call (default 200).
---
---   OPTIONAL non-paper-faithful (CAUTION — documented deviation):
---   * `method = "meta_prompt_sp"`  — **NOT paper-faithful**.
---       Uses per-agent 2nd-order meta-prompt ("predict other agents'
---       answer distribution") to produce a marginal predicted
---       frequency, then aggregates with a LINEAR (additive)
---       Surprisingly-Popular extension inspired by Prelec-Seung-McCoy
---       2017:  score(s) = c1(s) − Σ_i π_i(s).
---       Note: Prelec 2017 originally scores via a LOG-RATIO form
---       log(vote_share(s) / predict_share(s)). This impl substitutes
---       the linear/additive variant because it is scale-stable for
---       small N and does not need per-option log arithmetic. So this
---       is SP-*inspired*, not Prelec 2017 verbatim, and explicitly not
---       Zhang 2025 ISP. Use when (a) no calibration tensor is
---       available, and (b) you accept a single-query heuristic
---       instead of finite-sample guarantees. See NOT IN v1 below for
---       why Zhang 2025's ISP cannot be correctly computed from a
---       single online query.
---
--- NOT IN v1 (documented shortfalls):
---   * `method = "ow_l"` is STUB. The §5.2 Eq.(7) expanded parametric
---     form lives in §E.2 which could not be verbatim-extracted from
---     the HTML / PDF in the review cycle. Attempting to fit x_i
---     against the empirical 2nd-order tensor requires the exact
---     parametric map (x_1..x_N) ↦ P(A_i=s|A_j=a) from Alg.1's
---     generative process; implementing it from a guessed form would
---     hallucinate the regression target. Calling `M.calibrate` with
---     method="ow_l" raises an explicit paper-reference error.
---   * 1-query online variant of ISP / OW is NOT provided by the
---     paper (§4.3 Thm.3 is batch over M i.i.d. questions). The
---     `meta_prompt_sp` INJECT is a documented approximation, not a
---     theoretically-backed substitute.
---   * Paper §E.3 "Additional details and prompts" could not be
---     verbatim-extracted; the online prompt here is a convention
---     (conformal_vote-style) and may differ from the paper's author
---     prompts.
--- ═══════════════════════════════════════════════════════════════════
---
--- Usage (paper-faithful ISP):
---   local isp = require("isp_aggregate")
---   local cal = isp.calibrate({
---       calibration_tensor = {  -- M rows × N cols of option labels
---           { "A", "A", "B", "A" },
---           { "B", "B", "B", "C" },
---           ...
---       },
---       options = { "A", "B", "C" },
---       method  = "isp",
---   })
---   return isp.run({
---       task        = "Which of the following...?",
---       options     = { "A", "B", "C" },
---       calibration = cal,
---       method      = "isp",
---   })
---
--- Usage (non-paper-faithful single-query SP-style):
---   return isp.run({
---       task    = "...",
---       options = { "A", "B", "C" },
---       method  = "meta_prompt_sp",
---       n       = 5,
---   })
---
--- Category: aggregation.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name        = "isp_aggregate",
    version     = "0.2.0",
    description = "LLM aggregation via higher-order information "
        .. "(Zhang et al. 2025, arXiv:2510.01499). Paper-faithful "
        .. "ISP (inverse surprising popularity) and OW (optimal "
        .. "weight) aggregators with a calibration/run split mirror "
        .. "of conformal_vote. Non-paper-faithful meta-prompt SP "
        .. "path is an explicit opt-in for calibration-free settings.",
    category    = "aggregation",
}

-- Centralized defaults. Keep magic numbers here so no entry hard-codes
-- its own copy. Values annotated with paper location; "paper not fixed"
-- marks knobs the paper leaves to the implementer (caller override
-- recommended per dataset — see `.claude/CLAUDE.md §論文実装 pkg §2`).
M._defaults = {
    -- Number of online agents when `ctx.agents` is nil. Paper §5.1 uses
    -- N=4 for simulations and 2-8 for real-LLM rooms (§5.3). 5 is a
    -- neutral default balancing diversity and cost; paper not fixed for
    -- Lua deployments.
    n          = 5,
    -- Max tokens per 1st-order LLM call. Paper not fixed; 200 matches
    -- a short-answer regime (option label + short justification).
    gen_tokens = 200,
    -- Default aggregator. Paper's primary novelty is ISP (§4.2); OW
    -- (§3 Alg.1) is presented first but requires ground-truth x_i.
    method     = "isp",
    -- Tie-break. "first_in_options" is deterministic and round-trip-
    -- stable for tests; paper §E.1 uses "uniform_random" for MV. The
    -- paper does NOT fix a tie-break rule for ISP / OW beyond this
    -- MV reference.
    tie_break  = "first_in_options",
    -- Numerical floor/ceiling for accuracy x_i before inversion by
    -- σ_K⁻¹ (avoids log(0) / log(∞) blowup). Paper not fixed; 1e-6
    -- is conservative at double precision.
    x_eps      = 1e-6,
    -- Non-paper-faithful INJECT only. 2nd-order meta-prompt path uses
    -- this. Paper not applicable.
    second_order_gen_tokens = 400,
}

-- Option diversity hints for the default agents_builder. Matches the
-- pattern in Prelec-family SP aggregators; not prescribed by Zhang 2025.
local DIVERSITY_HINTS = {
    "Think step by step carefully.",
    "Approach this from first principles.",
    "Consider an alternative perspective.",
    "Work backwards from the expected outcome.",
    "Break this into smaller sub-problems.",
    "Use an analogy to reason about this.",
    "Consider edge cases and exceptions first.",
}

-- ═══════════════════════════════════════════════════════════════════
-- Pure helpers (LLM-independent, testable)
-- ═══════════════════════════════════════════════════════════════════

local function clean_answer(s)
    if type(s) ~= "string" then return "" end
    local t = s:gsub("^%s+", ""):gsub("%s+$", "")
    t = t:gsub("%s+", " ")
    t = t:gsub("[%.%!%?%,%;%:]+$", "")
    return t
end

local function normalize(s)
    return clean_answer(s):lower()
end

-- Build a normalized → original option lookup.
local function build_opt_lookup(options)
    local lookup = {}
    for _, opt in ipairs(options) do
        lookup[normalize(opt)] = opt
    end
    return lookup
end

-- σ_K(x) = exp(x) / (K - 1 + exp(x))
-- Exported via _internal for tests; not a public pkg entry.
local function sigma_k(x, K)
    if type(x) ~= "number" then
        error("isp_aggregate.sigma_k: x must be number", 2)
    end
    if type(K) ~= "number" or K < 2 or K ~= math.floor(K) then
        error("isp_aggregate.sigma_k: K must be integer >= 2, got "
            .. tostring(K), 2)
    end
    -- Max-shift guard against overflow (exp(x) for large x).
    if x >= 0 then
        local e = math.exp(-x)
        return 1 / ((K - 1) * e + 1)
    else
        local e = math.exp(x)
        return e / ((K - 1) + e)
    end
end

-- σ_K⁻¹(y) = ln( y (K - 1) / (1 - y) )
-- Callers must clamp y to (eps, 1-eps) beforehand; this helper errors
-- on out-of-range input rather than silently saturating.
local function sigma_k_inv(y, K)
    if type(y) ~= "number" then
        error("isp_aggregate.sigma_k_inv: y must be number", 2)
    end
    if type(K) ~= "number" or K < 2 or K ~= math.floor(K) then
        error("isp_aggregate.sigma_k_inv: K must be integer >= 2, got "
            .. tostring(K), 2)
    end
    if y <= 0 or y >= 1 then
        error(string.format(
            "isp_aggregate.sigma_k_inv: y must be in (0, 1), got %s "
                .. "(caller should clamp with x_eps first)", tostring(y)), 2)
    end
    return math.log(y * (K - 1) / (1 - y))
end

-- ω_i = σ_K⁻¹(x_i) for each i, with clamping to (eps, 1-eps).
-- Returns a fresh array.
local function ow_weights(x_vec, K, x_eps)
    if type(x_vec) ~= "table" then
        error("isp_aggregate.ow_weights: x_vec must be table", 2)
    end
    local n = #x_vec
    if n == 0 then
        error("isp_aggregate.ow_weights: x_vec must be non-empty", 2)
    end
    x_eps = x_eps or M._defaults.x_eps
    local w = {}
    for i = 1, n do
        local xi = x_vec[i]
        if type(xi) ~= "number" then
            error(string.format(
                "isp_aggregate.ow_weights: x_vec[%d] must be number, got %s",
                i, type(xi)), 2)
        end
        local yi = math.max(x_eps, math.min(1 - x_eps, xi))
        w[i] = sigma_k_inv(yi, K)
    end
    return w
end

-- Tally 1st-order answers (array of strings) into per-option counts.
-- Unrecognized answers are silently dropped (caller should surface
-- via the `votes` array in the result shape for observability).
local function count_votes(answers, options)
    local lookup = build_opt_lookup(options)
    local counts = {}
    for _, opt in ipairs(options) do counts[opt] = 0 end
    for _, a in ipairs(answers) do
        local orig = lookup[normalize(a)]
        if orig then counts[orig] = counts[orig] + 1 end
    end
    return counts
end

-- Argmax over options with deterministic tie-break.
-- `tie_break` ∈ { "first_in_options", "uniform_random" }. For
-- "uniform_random" the caller's RNG is math.random (not re-seeded).
local function argmax_options(scores, options, tie_break)
    local best_opt, best_score
    local ties = {}
    for _, opt in ipairs(options) do
        local s = scores[opt]
        if s == nil then s = -math.huge end
        if best_score == nil or s > best_score then
            best_score = s
            best_opt   = opt
            ties       = { opt }
        elseif s == best_score then
            ties[#ties + 1] = opt
        end
    end
    if tie_break == "uniform_random" and #ties > 1 then
        return ties[math.random(#ties)], best_score
    end
    return best_opt, best_score
end

-- OW aggregator: argmax_s Σ_i ω_i · 1{a_i = s}. Paper §3 Alg.1.
local function aggregate_ow(answers, weights, options, tie_break)
    if #answers ~= #weights then
        error(string.format(
            "isp_aggregate.aggregate_ow: #answers (%d) != #weights (%d)",
            #answers, #weights), 2)
    end
    local lookup = build_opt_lookup(options)
    local scores = {}
    for _, opt in ipairs(options) do scores[opt] = 0 end
    for i = 1, #answers do
        local orig = lookup[normalize(answers[i])]
        if orig then
            scores[orig] = scores[orig] + weights[i]
        end
    end
    local best, best_score = argmax_options(scores, options, tie_break)
    return best, scores, best_score
end

-- Helper for ISP scoring: compute S_ISP(s, i; a_vec).
-- kernel[i][j][a][s] = P̂(A_i=s | A_j=a).
-- Returns nil for s when any (j≠i, a' ≠ a_j) cell is missing; caller
-- substitutes a fallback (uniform 1/K by default).
local function s_isp_value(i, s, a_vec, kernel, options)
    local N = #a_vec
    local K = #options
    if N < 2 then return 0 end
    if K < 2 then return 0 end
    local acc_j = 0
    local count_j = 0
    for j = 1, N do
        if j ~= i then
            local a_j = a_vec[j]
            local kij = kernel[i] and kernel[i][j]
            -- Paper §4.2 Eq.5 requires a_j ∈ S; when a_j is nil
            -- (caller-provided unrecognized option), `a' ≠ a_j` would
            -- evaluate true for all K options and produce a K-term sum
            -- instead of the paper-required K-1. Skip such j entirely
            -- so count_j reflects only paper-valid outer terms.
            if kij and a_j ~= nil then
                local inner_acc = 0
                local inner_count = 0
                for _, a_prime in ipairs(options) do
                    if a_prime ~= a_j then
                        local cell = kij[a_prime]
                        if cell ~= nil then
                            local p = cell[s]
                            if type(p) == "number" then
                                inner_acc = inner_acc + p
                                inner_count = inner_count + 1
                            else
                                -- missing P̂(A_i=s|A_j=a_prime): fallback uniform
                                inner_acc = inner_acc + 1 / K
                                inner_count = inner_count + 1
                            end
                        else
                            -- missing cell entirely (no calibration rows
                            -- had A_j=a_prime): fallback uniform.
                            inner_acc = inner_acc + 1 / K
                            inner_count = inner_count + 1
                        end
                    end
                end
                if inner_count > 0 then
                    acc_j = acc_j + (inner_acc / inner_count)
                    count_j = count_j + 1
                end
            end
        end
    end
    if count_j == 0 then return 0 end
    return acc_j / count_j
end

-- ISP aggregator: argmax_s [ c1(s) - Σ_i S_ISP(s, i; a_vec) ]. Paper Eq.5-6.
local function aggregate_isp(answers, kernel, options, tie_break)
    local lookup = build_opt_lookup(options)
    -- Normalize observed answers to original casing (needed for kernel lookup).
    local a_vec = {}
    for i = 1, #answers do
        local orig = lookup[normalize(answers[i])]
        a_vec[i] = orig  -- may be nil if unrecognized
    end
    local counts = {}
    for _, opt in ipairs(options) do counts[opt] = 0 end
    for i = 1, #a_vec do
        if a_vec[i] ~= nil then
            counts[a_vec[i]] = counts[a_vec[i]] + 1
        end
    end
    local scores = {}
    for _, s in ipairs(options) do
        local subtract = 0
        for i = 1, #a_vec do
            if a_vec[i] ~= nil then
                subtract = subtract + s_isp_value(i, s, a_vec, kernel, options)
            end
        end
        scores[s] = counts[s] - subtract
    end
    local best, best_score = argmax_options(scores, options, tie_break)
    return best, scores, best_score
end

-- Compute the S_ISP kernel from a calibration tensor.
--   tensor[m][i] = observed answer of agent i on reference question m
--   kernel[i][j][a][s] = #{ m : tensor[m][i]=s AND tensor[m][j]=a }
--                        / #{ m : tensor[m][j]=a }
-- For cells where the denominator is 0 the entry is absent (s_isp_value
-- substitutes a uniform fallback at query time).
local function compute_s_isp_kernel(tensor, options)
    if type(tensor) ~= "table" then
        error("isp_aggregate.compute_s_isp_kernel: tensor must be a table", 2)
    end
    local M_ = #tensor
    if M_ == 0 then
        error("isp_aggregate.compute_s_isp_kernel: tensor must be non-empty", 2)
    end
    local N = #tensor[1]
    if N < 2 then
        error("isp_aggregate.compute_s_isp_kernel: tensor rows must have "
            .. "at least 2 agents per sample", 2)
    end
    local lookup = build_opt_lookup(options)

    -- Normalized tensor (original casing preserved via lookup); rows with
    -- inconsistent width are rejected.
    local norm = {}
    for m = 1, M_ do
        local row = tensor[m]
        if type(row) ~= "table" or #row ~= N then
            error(string.format(
                "isp_aggregate.compute_s_isp_kernel: tensor[%d] must be a "
                    .. "table of length %d (= N_agents), got %s",
                m, N, type(row) == "table" and tostring(#row) or type(row)), 2)
        end
        local nr = {}
        for i = 1, N do
            local orig = lookup[normalize(row[i])]
            nr[i] = orig
        end
        norm[m] = nr
    end

    -- Count #{A_j=a} and #{A_i=s, A_j=a} jointly in one pass.
    local denom = {}  -- denom[j][a] = #{m : norm[m][j] = a}
    local num   = {}  -- num[i][j][a][s] = #{m : norm[m][i]=s, norm[m][j]=a}
    for i = 1, N do
        num[i] = {}
        for j = 1, N do
            if j ~= i then
                num[i][j] = {}
                for _, a in ipairs(options) do num[i][j][a] = {} end
            end
        end
    end
    for j = 1, N do denom[j] = {} end
    for _, a in ipairs(options) do
        for j = 1, N do denom[j][a] = 0 end
    end

    for m = 1, M_ do
        local row = norm[m]
        for j = 1, N do
            local aj = row[j]
            if aj then
                denom[j][aj] = denom[j][aj] + 1
                for i = 1, N do
                    if i ~= j then
                        local si = row[i]
                        if si then
                            num[i][j][aj][si] = (num[i][j][aj][si] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    local kernel = {}
    for i = 1, N do
        kernel[i] = {}
        for j = 1, N do
            if j ~= i then
                kernel[i][j] = {}
                for _, a in ipairs(options) do
                    local d = denom[j][a]
                    if d and d > 0 then
                        local cell = {}
                        for _, s in ipairs(options) do
                            cell[s] = (num[i][j][a][s] or 0) / d
                        end
                        kernel[i][j][a] = cell
                    end
                    -- else: leave kernel[i][j][a] absent (uniform fallback)
                end
            end
        end
    end
    return kernel, M_
end

-- OW-I accuracy estimator (paper §5.2 Eq.7 直後):
--   x̂_i = #{ m : f_ISP(tensor[m]) = tensor[m][i] } / M
-- Note: this is NOT isotonic regression despite the "I" name; it is a
-- self-labeling accuracy count using ISP's output as the pseudo-label.
-- Data-reuse caveat: the S_ISP kernel passed in here is built from
-- the same tensor that we now evaluate f_ISP on, so each x̂_i
-- inherits a "training-set self-evaluation" bias (the pseudo-label
-- was informed by row m itself). Paper §5.2 Eq.(7) does not define
-- a leave-one-out variant and we stay paper-faithful here, but the
-- resulting x̂_i should not be read as a held-out accuracy estimate.
local function estimate_accuracy_owi(tensor, kernel, options, tie_break)
    local M_ = #tensor
    local N = #tensor[1]
    local lookup = build_opt_lookup(options)
    local hits = {}
    for i = 1, N do hits[i] = 0 end
    for m = 1, M_ do
        local row = tensor[m]
        local answers = {}
        for i = 1, N do answers[i] = row[i] end
        local predicted = aggregate_isp(answers, kernel, options, tie_break)
        for i = 1, N do
            local orig = lookup[normalize(row[i])]
            if orig ~= nil and predicted == orig then
                hits[i] = hits[i] + 1
            end
        end
    end
    local x = {}
    for i = 1, N do x[i] = hits[i] / M_ end
    return x
end

-- Meta-prompt 2nd-order parse (non-paper-faithful INJECT). Tolerant
-- parser mimicking conformal_vote.parse_probabilities: scans for
-- "LABEL: number" lines inside an optional <probs>...</probs> block,
-- fills missing labels with 0, L1-normalizes, uniform fallback on
-- total-zero. Returns (parsed_map, parse_failed_bool).
local function parse_probabilities(raw, options)
    local n = #options
    local option_set = build_opt_lookup(options)
    local body = type(raw) == "string" and raw or ""
    do
        local inner = body:match("<probs>%s*(.-)%s*</probs>")
        if inner then body = inner end
    end
    local parsed = {}
    local any = false
    for line in (body .. "\n"):gmatch("([^\n]+)\n") do
        local lbl, num = line:match("([%w%=_%-]+)%s*[:=]%s*([%d%.]+)")
        if lbl and num then
            local p = tonumber(num)
            if p ~= nil and p >= 0 then
                local key = option_set[normalize(lbl)]
                if key ~= nil and parsed[key] == nil then
                    parsed[key] = p
                    any = true
                end
            end
        end
    end
    if not any then
        local out = {}
        for i = 1, n do out[options[i]] = 1 / n end
        return out, true
    end
    local sum = 0
    for i = 1, n do
        if parsed[options[i]] == nil then parsed[options[i]] = 0 end
        sum = sum + parsed[options[i]]
    end
    if sum <= 0 then
        local out = {}
        for i = 1, n do out[options[i]] = 1 / n end
        return out, true
    end
    for i = 1, n do
        parsed[options[i]] = parsed[options[i]] / sum
    end
    return parsed, false
end

-- ═══════════════════════════════════════════════════════════════════
-- Input validation
-- ═══════════════════════════════════════════════════════════════════

local function validate_options(options, entry)
    if type(options) ~= "table" or #options == 0 then
        error(string.format(
            "isp_aggregate.%s: options must be a non-empty array of strings",
            entry), 3)
    end
    local seen = {}
    for i, o in ipairs(options) do
        if type(o) ~= "string" or o == "" then
            error(string.format(
                "isp_aggregate.%s: options[%d] must be a non-empty string",
                entry, i), 3)
        end
        local k = normalize(o)
        if seen[k] then
            error(string.format(
                "isp_aggregate.%s: options contains duplicate after "
                    .. "normalization (%q ~ %q)", entry, o, seen[k]), 3)
        end
        seen[k] = o
    end
end

local function validate_tensor(tensor, options, entry)
    if type(tensor) ~= "table" then
        error(string.format(
            "isp_aggregate.%s: calibration_tensor must be a table of rows",
            entry), 3)
    end
    local M_ = #tensor
    if M_ == 0 then
        error(string.format(
            "isp_aggregate.%s: calibration_tensor must be non-empty", entry), 3)
    end
    local N = nil
    for m = 1, M_ do
        local row = tensor[m]
        if type(row) ~= "table" or #row == 0 then
            error(string.format(
                "isp_aggregate.%s: calibration_tensor[%d] must be a "
                    .. "non-empty row", entry, m), 3)
        end
        if N == nil then N = #row end
        if #row ~= N then
            error(string.format(
                "isp_aggregate.%s: calibration_tensor[%d] has %d agents, "
                    .. "expected %d (must match row 1)",
                entry, m, #row, N), 3)
        end
        for i = 1, N do
            if type(row[i]) ~= "string" then
                error(string.format(
                    "isp_aggregate.%s: calibration_tensor[%d][%d] must be "
                        .. "a string label, got %s",
                    entry, m, i, type(row[i])), 3)
                end
        end
    end
    if N < 2 then
        error(string.format(
            "isp_aggregate.%s: calibration_tensor rows must have N >= 2 "
                .. "agents (got %d)", entry, N), 3)
    end
    return M_, N
end

local function validate_x_direct(x_vec, n_agents, entry)
    if type(x_vec) ~= "table" or #x_vec ~= n_agents then
        error(string.format(
            "isp_aggregate.%s: x_direct must be a table of length %d "
                .. "(got %s)", entry, n_agents,
            type(x_vec) == "table" and tostring(#x_vec) or type(x_vec)), 3)
    end
    for i = 1, n_agents do
        local xi = x_vec[i]
        if type(xi) ~= "number" or xi < 0 or xi > 1 then
            error(string.format(
                "isp_aggregate.%s: x_direct[%d] must be a number in [0,1], "
                    .. "got %s", entry, i, tostring(xi)), 3)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Shape definitions (local, for spec.entries)
-- ═══════════════════════════════════════════════════════════════════

local calibrate_input = T.shape({
    calibration_tensor = T.array_of(T.array_of(T.string))
        :describe("M × N array: rows = reference questions, cols = agents."),
    options            = T.array_of(T.string)
        :describe("Fixed option set; K = #options."),
    method             = T.one_of({ "isp", "ow_l", "ow_i" })
        :describe("Estimator to build. ow_l raises not-implemented in v1."),
    tie_break          = T.one_of({ "first_in_options", "uniform_random" })
        :is_optional()
        :describe("Tie-break used by OW-I internal aggregate calls (default first_in_options)"),
}, { open = true })

local run_input = T.shape({
    task        = T.string:describe("Question text presented to each agent"),
    options     = T.array_of(T.string):describe("Candidate labels"),
    method      = T.one_of({ "isp", "ow", "ow_l", "ow_i", "meta_prompt_sp" })
        :is_optional()
        :describe("Aggregator. Default 'isp'. 'meta_prompt_sp' is NOT paper-faithful."),
    calibration = T.any:is_optional()
        :describe("Output of M.calibrate. REQUIRED for method ∈ {isp, ow_l, ow_i}."),
    x_direct    = T.array_of(T.number):is_optional()
        :describe("REQUIRED for method='ow'. Length = #agents; each x_i ∈ [0,1]."),
    agents      = T.any:is_optional()
        :describe("Array of agent specs (string prompt | {prompt,system?,model?,temperature?,max_tokens?} table). Default: diversity-hinted builder of length n."),
    n           = T.number:is_optional()
        :describe("Agent count when `agents` is nil (default 5)."),
    gen_tokens  = T.number:is_optional()
        :describe("Max tokens per 1st-order LLM call (default 200)."),
    tie_break   = T.one_of({ "first_in_options", "uniform_random" })
        :is_optional()
        :describe("Score-tie rule (default 'first_in_options')."),
    x_eps       = T.number:is_optional()
        :describe("Clamp floor for σ_K⁻¹ input (default 1e-6)."),
    second_order_gen_tokens = T.number:is_optional()
        :describe("Only used with method='meta_prompt_sp' (default 400)."),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        calibrate = {
            input  = calibrate_input,
            result = "isp_calibrated",
        },
        run = {
            input  = run_input,
            result = "isp_voted",
        },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- Public: calibrate
-- ═══════════════════════════════════════════════════════════════════

--- Fit the estimator from a reference answer tensor.
---
--- The returned struct is pinned into `M.run` via `ctx.calibration` so
--- that online rounds reuse the exact kernel / accuracy estimates from
--- calibration — same pattern as conformal_vote's weight pinning.
---
--- method="isp"  : builds `s_isp_kernel` (nested map of pairwise
---                 empirical conditionals) per paper §4.3 Thm.3.
--- method="ow_i" : builds `s_isp_kernel` AND `x_estimated` (OW-I self-
---                 labeling accuracy via §5.2 Eq.7 直後).
--- method="ow_l" : NOT IMPLEMENTED in v1 — raises paper-reference error.
---
---@param cfg table
---@return table
function M.calibrate(cfg)
    if type(cfg) ~= "table" then
        error("isp_aggregate.calibrate: cfg must be a table", 2)
    end
    validate_options(cfg.options, "calibrate")
    local method = cfg.method
    if method == nil then
        error("isp_aggregate.calibrate: cfg.method is required "
            .. "(\"isp\" | \"ow_l\" | \"ow_i\")", 2)
    end
    if method == "ow_l" then
        error("isp_aggregate.calibrate: method='ow_l' is NOT implemented "
            .. "in v1. Paper §5.2 Eq.(7) expanded parametric form (§E.2) "
            .. "was not reproducible from the extracted sections; "
            .. "implementing it from a guessed form would hallucinate the "
            .. "regression target. Use method='ow_i' for a self-labeled "
            .. "accuracy estimate, or pass x_direct to M.run for "
            .. "method='ow' with externally-supplied accuracies.", 2)
    end
    if method ~= "isp" and method ~= "ow_i" then
        error(string.format(
            "isp_aggregate.calibrate: unknown method %q (expected "
                .. "\"isp\" | \"ow_i\")", tostring(method)), 2)
    end
    local M_, N = validate_tensor(cfg.calibration_tensor, cfg.options, "calibrate")
    local tie_break = cfg.tie_break or M._defaults.tie_break

    local kernel = compute_s_isp_kernel(cfg.calibration_tensor, cfg.options)
    local x_estimated
    if method == "ow_i" then
        x_estimated = estimate_accuracy_owi(
            cfg.calibration_tensor, kernel, cfg.options, tie_break
        )
    end

    return {
        method       = method,
        n_agents     = N,
        n_samples    = M_,
        options      = cfg.options,
        K            = #cfg.options,
        s_isp_kernel = kernel,
        x_estimated  = x_estimated,
    }
end

-- ═══════════════════════════════════════════════════════════════════
-- run helpers
-- ═══════════════════════════════════════════════════════════════════

local function warn(msg)
    if type(alc) == "table" and type(alc.log) == "table"
        and type(alc.log.warn) == "function"
    then
        alc.log.warn(msg); return
    end
    if type(alc) == "table" and type(alc.log) == "function" then
        local ok = pcall(alc.log, "warn", msg); if ok then return end
    end
    io.stderr:write("[isp_aggregate] " .. tostring(msg) .. "\n")
end

local function default_agents_builder(n_agents)
    local agents = {}
    for i = 1, n_agents do
        local hint = DIVERSITY_HINTS[((i - 1) % #DIVERSITY_HINTS) + 1]
        agents[i] = {
            prompt = hint,
            system = "You are a careful reasoner. Answer with only the "
                .. "option label.",
        }
    end
    return agents
end

local function build_first_order_prompt(agent_spec, task, options, gen_tokens)
    local agent_prompt, system, model, temperature, max_tokens
    if type(agent_spec) == "string" then
        agent_prompt = agent_spec
    elseif type(agent_spec) == "table" then
        agent_prompt = agent_spec.prompt
        system       = agent_spec.system
        model        = agent_spec.model
        temperature  = agent_spec.temperature
        max_tokens   = agent_spec.max_tokens
        if type(agent_prompt) ~= "string" then
            error("isp_aggregate.run: agents[i] table must set `prompt` string", 3)
        end
    else
        error("isp_aggregate.run: agents[i] must be a string or a table", 3)
    end
    local options_str = table.concat(options, ", ")
    local prompt = string.format(
        "%s\n\nQuestion: %s\nOptions: %s\n\n"
            .. "Pick ONE option. Answer with only the option label.",
        agent_prompt, task, options_str
    )
    local llm_opts = {
        system     = system
            or "You are a careful reasoner. Answer with only the option label.",
        max_tokens = max_tokens or gen_tokens,
    }
    if model ~= nil then llm_opts.model = model end
    if temperature ~= nil then llm_opts.temperature = temperature end
    return prompt, llm_opts
end

local function build_second_order_prompt(agent_spec, task, options,
                                         first_order, gen_tokens, n_agents)
    local base_prompt, base_system
    if type(agent_spec) == "string" then
        base_prompt = agent_spec
    elseif type(agent_spec) == "table" then
        base_prompt = agent_spec.prompt or ""
        base_system = agent_spec.system
    else
        base_prompt = ""
    end
    local options_str = table.concat(options, ", ")
    local probs_skeleton = {}
    for _, opt in ipairs(options) do
        probs_skeleton[#probs_skeleton + 1] = opt .. ": 0.XX"
    end
    local prompt = string.format(
        "%s\n\nQuestion: %s\nOptions: %s\n\n"
            .. "You just answered: %s.\n"
            .. "Now predict how the other %d agents will answer the same "
            .. "question. For each option, give your estimated probability "
            .. "of that option being chosen by the other agents "
            .. "(probabilities must sum to 1).\n"
            .. "Output format:\n<probs>\n%s\n</probs>",
        base_prompt, task, options_str, first_order,
        n_agents - 1, table.concat(probs_skeleton, "\n")
    )
    local llm_opts = {
        system = base_system
            or "You are predicting how other agents will answer. "
            .. "Output only the <probs> block.",
        max_tokens = gen_tokens,
    }
    return prompt, llm_opts
end

-- ═══════════════════════════════════════════════════════════════════
-- Public: run
-- ═══════════════════════════════════════════════════════════════════

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    if type(ctx) ~= "table" then
        error("isp_aggregate.run: ctx must be a table", 2)
    end
    if type(ctx.task) ~= "string" or ctx.task == "" then
        error("isp_aggregate.run: ctx.task is required (non-empty string)", 2)
    end
    validate_options(ctx.options, "run")

    local method     = ctx.method or M._defaults.method
    local gen_tokens = ctx.gen_tokens or M._defaults.gen_tokens
    local tie_break  = ctx.tie_break  or M._defaults.tie_break
    local x_eps      = ctx.x_eps      or M._defaults.x_eps
    local K          = #ctx.options

    -- Determine agent specs + n.
    local agents
    if ctx.agents ~= nil then
        if type(ctx.agents) ~= "table" or #ctx.agents == 0 then
            error("isp_aggregate.run: ctx.agents must be a non-empty array", 2)
        end
        agents = ctx.agents
    else
        local n = ctx.n or M._defaults.n
        if type(n) ~= "number" or n < 2 or n ~= math.floor(n) then
            error(string.format(
                "isp_aggregate.run: ctx.n must be integer >= 2, got %s",
                tostring(n)), 2)
        end
        agents = default_agents_builder(n)
    end
    local n_agents = #agents

    -- Method-specific calibration / x_direct validation.
    local cal
    local x_used
    local weights
    local kernel
    local calibration_summary

    if method == "ow" then
        if ctx.x_direct == nil then
            error("isp_aggregate.run: method='ow' requires ctx.x_direct "
                .. "(N-array of accuracies). Use method='ow_i' for "
                .. "auto-estimation from calibration.", 2)
        end
        validate_x_direct(ctx.x_direct, n_agents, "run")
        x_used = {}
        for i = 1, n_agents do x_used[i] = ctx.x_direct[i] end
        weights = ow_weights(x_used, K, x_eps)
    elseif method == "meta_prompt_sp" then
        -- non-paper-faithful path; no calibration required.
    elseif method == "isp" or method == "ow_i" then
        cal = ctx.calibration
        if type(cal) ~= "table" then
            error(string.format(
                "isp_aggregate.run: method=%q requires ctx.calibration "
                    .. "(output of M.calibrate). See docstring for the "
                    .. "paper-faithful flow.", method), 2)
        end
        if cal.method ~= method then
            -- Allow OW-I to run with an ISP calibration (kernel alone is
            -- insufficient without x_estimated) — reject explicitly.
            if not (method == "ow_i" and cal.method == "ow_i") then
                if method == "isp" and cal.method == "ow_i" then
                    -- ow_i calibration also contains the kernel; allow.
                else
                    error(string.format(
                        "isp_aggregate.run: ctx.calibration.method=%q does "
                            .. "not match run method=%q. Calibrate with the "
                            .. "same method.", tostring(cal.method), method), 2)
                end
            end
        end
        if type(cal.s_isp_kernel) ~= "table" then
            error("isp_aggregate.run: ctx.calibration.s_isp_kernel missing", 2)
        end
        if cal.n_agents ~= n_agents then
            error(string.format(
                "isp_aggregate.run: ctx.calibration was built for N=%d "
                    .. "agents but run has N=%d. Re-calibrate with the "
                    .. "same agent count.", cal.n_agents, n_agents), 2)
        end
        if type(cal.options) ~= "table" or #cal.options ~= #ctx.options then
            error("isp_aggregate.run: ctx.calibration.options length does "
                .. "not match ctx.options. Options must be fixed across "
                .. "calibration and run (paper §4.3 exchangeability).", 2)
        end
        for i, o in ipairs(ctx.options) do
            if cal.options[i] ~= o then
                error(string.format(
                    "isp_aggregate.run: ctx.calibration.options[%d]=%q "
                        .. "!= ctx.options[%d]=%q. Order must match.",
                    i, tostring(cal.options[i]), i, tostring(o)), 2)
            end
        end
        kernel = cal.s_isp_kernel
        if method == "ow_i" then
            if type(cal.x_estimated) ~= "table"
                or #cal.x_estimated ~= n_agents
            then
                error("isp_aggregate.run: method='ow_i' requires "
                    .. "ctx.calibration.x_estimated (from "
                    .. "M.calibrate({..., method='ow_i'}))", 2)
            end
            x_used = {}
            for i = 1, n_agents do x_used[i] = cal.x_estimated[i] end
            weights = ow_weights(x_used, K, x_eps)
        end
        calibration_summary = {
            method    = cal.method,
            n_agents  = cal.n_agents,
            n_samples = cal.n_samples,
        }
    else
        error(string.format(
            "isp_aggregate.run: unknown method %q (expected "
                .. "\"isp\" | \"ow\" | \"ow_l\" | \"ow_i\" | "
                .. "\"meta_prompt_sp\")", tostring(method)), 2)
    end

    if method == "ow_l" then
        error("isp_aggregate.run: method='ow_l' is NOT implemented in v1. "
            .. "Paper §5.2 Eq.(7) expanded form (§E.2) was not "
            .. "reproducible from the extracted sections; avoid "
            .. "hallucinated OLS target. Use method='ow_i' or pass "
            .. "x_direct with method='ow'.", 2)
    end

    if type(alc) ~= "table" or type(alc.llm) ~= "function" then
        error("isp_aggregate.run: alc.llm is required at runtime", 2)
    end

    -- ─── Online round: 1st-order for every agent ───
    local total_llm_calls = 0
    local paths = {}
    local votes = {}
    for i = 1, n_agents do
        local prompt, opts = build_first_order_prompt(
            agents[i], ctx.task, ctx.options, gen_tokens
        )
        local raw = alc.llm(prompt, opts)
        total_llm_calls = total_llm_calls + 1
        local cleaned = clean_answer(raw)
        votes[i] = cleaned
        paths[i] = { first_order = cleaned }
    end

    -- ─── Optional 2nd-order (meta_prompt_sp only) ───
    local scores
    local best
    if method == "meta_prompt_sp" then
        local so_gen = ctx.second_order_gen_tokens
            or M._defaults.second_order_gen_tokens
        local c2 = {}
        for _, opt in ipairs(ctx.options) do c2[opt] = 0 end
        local parse_failures = 0
        for i = 1, n_agents do
            local prompt, opts = build_second_order_prompt(
                agents[i], ctx.task, ctx.options, votes[i], so_gen, n_agents
            )
            local raw = alc.llm(prompt, opts)
            total_llm_calls = total_llm_calls + 1
            local parsed, failed = parse_probabilities(raw, ctx.options)
            if failed then
                parse_failures = parse_failures + 1
                warn(string.format(
                    "isp_aggregate.run: agent %d 2nd-order parse failed; "
                        .. "using uniform", i))
            end
            paths[i].second_order_raw    = raw
            paths[i].second_order_parsed = parsed
            for _, opt in ipairs(ctx.options) do
                c2[opt] = c2[opt] + parsed[opt]
            end
        end
        -- SP-inspired LINEAR extension (NOT Prelec 2017 verbatim):
        --   score(s) = c1(s) - N · mean_i π_i(s) = c1(s) - Σ_i π_i(s).
        -- Prelec 2017 original uses log(vote_share/predict_share);
        -- linear/additive form is used here for small-N scale stability.
        -- Ties reduce to MV behavior when π is uniform.
        local counts = count_votes(votes, ctx.options)
        scores = {}
        for _, opt in ipairs(ctx.options) do
            scores[opt] = counts[opt] - c2[opt]
        end
        best = argmax_options(scores, ctx.options, tie_break)
    elseif method == "ow" or method == "ow_i" then
        best, scores = aggregate_ow(votes, weights, ctx.options, tie_break)
    else -- method == "isp"
        best, scores = aggregate_isp(votes, kernel, ctx.options, tie_break)
    end

    ctx.result = {
        answer              = best,
        answer_norm         = best and normalize(best) or nil,
        scores              = scores,
        method              = method,
        n_agents            = n_agents,
        votes               = votes,
        weights             = weights,
        x_used              = x_used,
        paths               = paths,
        calibration_summary = calibration_summary,
        total_llm_calls     = total_llm_calls,
    }
    return ctx
end

-- ═══════════════════════════════════════════════════════════════════
-- Test hooks
-- ═══════════════════════════════════════════════════════════════════

M._internal = {
    clean_answer            = clean_answer,
    normalize               = normalize,
    build_opt_lookup        = build_opt_lookup,
    sigma_k                 = sigma_k,
    sigma_k_inv             = sigma_k_inv,
    ow_weights              = ow_weights,
    count_votes             = count_votes,
    argmax_options          = argmax_options,
    aggregate_ow            = aggregate_ow,
    aggregate_isp           = aggregate_isp,
    compute_s_isp_kernel    = compute_s_isp_kernel,
    estimate_accuracy_owi   = estimate_accuracy_owi,
    parse_probabilities     = parse_probabilities,
    s_isp_value             = s_isp_value,
    validate_tensor         = validate_tensor,
    validate_options        = validate_options,
    DIVERSITY_HINTS         = DIVERSITY_HINTS,
}

-- Malli-style self-decoration (per-entry). `M.calibrate` returns an
-- isp_calibrated struct; `M.run` returns an isp_voted struct.
M.calibrate = S.instrument(M, "calibrate")
M.run       = S.instrument(M, "run")

return M
