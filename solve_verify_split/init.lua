--- solve_verify_split — Compute-optimal split between solution
--- generation (Self-Consistency) and generative verification (GenRM)
--- under a fixed inference compute budget. Pure Computation pkg.
---
--- Based on:
---   Singhi, Bansal, Hosseini, Grover, Chang, Rohrbach, Rohrbach
---   "When To Solve, When To Verify: Compute-Optimal Problem Solving
---    and Generative Verification for LLM Reasoning"
---   (arXiv:2504.01005, COLM 2025)
---
--- Implements §3.1 cost model and §3.2 / §5.2 power-law inference
--- scaling laws as Pure Computation primitives (no LLM calls).
---
--- Core formulas:
---
---   Cost (paper §3.1, per-solution verification model):
---     C(S, V) = S · (1 + λ · V)
---       where λ = T_V / T_S  (verify-token / solve-token ratio)
---       SC degenerate case: C(S, 0) = S
---
---   Power-law inference scaling (paper §5.2):
---     S_opt(C) = α_S · C^a
---     V_opt(C) = α_V · C^b
---
---     paper-default exponents (§5.2 Llama-3.1-8B + GenRM-FT + MATH):
---       a = 0.57,  b = 0.39
---     Appendix J alternates (transferred only):
---       Qwen-2.5-7B + MATH:    a = 0.75, b = 0.32
---       Llama-3.3-70B + MATH:  a = 0.69, b = 0.43
---
---     α_S, α_V have NO numeric value in the paper — caller MUST fit
---     these from a (S, V) grid via §3.2 Step 5 (log-linear regression).
---
---   §3.2 procedure reconstructed (paper has no Algorithm box):
---     Step 1: S_raw = α_S · B^a,    V_raw = α_V · B^b
---     Step 2: S_int = round(S_raw), V_int = round(V_raw)        (INJECT #A)
---     Step 3: C_actual = S_int · (1 + λ · V_int)
---     Step 4: if C_actual > B then rescale (S_int, V_int) within B (#B)
---     Step 5: if V_int == 0 then SC pure path: S = round(B), V = 0  (#C)
---
--- Cross-over observations (paper §5.1 — observations, NOT a constant):
---   * Llama-3.1-8B + GenRM-FT + MATH: GenRM matches SC at 8× compute,
---     +3.8% accuracy at 128× compute (Figure 1(b))
---   * Qwen-2.5-7B + MATH: 64× to match, +5.4% at 512× (§5.1)
---   * Llama-3.3-70B + GenRM-Base + MATH: 4× to match, +1.7% at 64×
---   * QwQ-32B (thinking) + MATH: 4× to match, +2.5% at 16×
---
---   The 8× (or any specific) cross-over is verifier-quality and
---   model-dependent (Appendix E: GenRM-FT vs Base differs by 16×).
---   This pkg does NOT hardcode a cross-over multiplier.
---
--- ═══ PAPER FIDELITY & INJECTION POINTS ═══════════════════════════════
--- Paper-faithful defaults:
---   * lambda = 1.0                           (§3.1 GenRM-Base equal-token)
---   * exponent_solve = 0.57                  (§5.2 Llama-8B/GenRM-FT/MATH)
---   * exponent_verify = 0.39                 (§5.2 Llama-8B/GenRM-FT/MATH)
---   * integer_method = "round"               (paper not fixed; neutral)
---   * rescale_method = "scale_proportional"  (paper not fixed)
---   * sc_fallback_when_v_zero = true         (§3.1 V=0 path)
---
--- REQUIRED injection points:
---   * B                          — Budget (§3.1 C unit, > 0).
---   * params.lambda              — λ = T_V / T_S (§3.1).
---   * params.exponent_solve      — a in S_opt ∝ C^a (§5.2).
---   * params.exponent_verify     — b in V_opt ∝ C^b (§5.2).
---   * params.prefactor_solve     — α_S; paper has NO numeric value
---                                  (§3.2 Step 5 = caller-fit).
---   * params.prefactor_verify    — α_V; paper has NO numeric value
---                                  (§3.2 Step 5 = caller-fit).
---
--- OPTIONAL paper-faithful injection points:
---   * opts.integer_method = "round" (default) | "floor" | "ceil"
---                                  — Power-law raw → integer rounding
---                                    (paper §3.2 not fixed).
---   * opts.rescale_method = "scale_proportional" (default)
---                          | "prefer_solve" | "prefer_verify"
---                                  — Strategy when integer-rounded
---                                    (S_int, V_int) overflows B
---                                    (paper §3.2 not fixed).
---   * opts.v_cap, opts.s_cap     — Hard caps on V / S (paper not fixed;
---                                    domain-specific).
---   * opts.sc_fallback_when_v_zero = true (default) | false
---                                  — When V_int = 0 after rounding, fall
---                                    back to pure SC path (§3.1 V=0).
---
--- OPTIONAL non-paper-faithful (caller must accept loss of paper guarantees):
---   * opts.cost_model = "per_solution" (default, paper §3.1) | "independent"
---                                  — "independent" uses C = S·c_s + V_total·c_v.
---                                    **NOT paper-faithful**: §3.1 has
---                                    per-solution V structure, not
---                                    independent V budget.
---
--- NOT IN v1 (documented shortfalls):
---   * fit_exponents — Log-linear regression to fit (a, b, α_S, α_V)
---     from caller-supplied grid observations (paper §3.2 Step 5).
---     Caller fits in v1; potential v2 helper.
---   * Cross-over multiplier auto-estimation — Paper §5.1's 8× / 4× / 64×
---     are observations, not constants. Auto-inference would require an
---     accuracy curve model the paper does not formalise.
---   * Multi-question budget partition — Total budget across Q questions.
---     Caller's responsibility (per-question B = total / Q is trivial).
---   * "independent" cost_model — declared as NOT paper-faithful opt-in
---     but not implemented in v1; reserved for the API surface only.
--- ═══════════════════════════════════════════════════════════════════════
---
--- Usage:
---
---   local svs = require("solve_verify_split")
---
---   -- §3.1 cost in isolation
---   svs.cost(4, 3, 1.0)            -- = 16
---   svs.cost(4, 1, 2.0)            -- = 12 (GenRM-FT λ=2)
---
---   -- Optimal allocation (caller fits α_S, α_V from grid)
---   local r = svs.optimal_split(100, {
---       lambda = 2.0,
---       exponent_solve = 0.57, exponent_verify = 0.39,
---       prefactor_solve = 1.0, prefactor_verify = 1.0,
---   })
---   -- r.s_opt / r.v_opt / r.cost_used / r.rescaled / r.raw / ...
---
--- Category: orchestration (allocator alongside compute_alloc).

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "solve_verify_split",
    version = "0.1.0",
    description = "Compute-optimal split between solution generation "
        .. "(SC) and generative verification (GenRM) under a fixed "
        .. "inference budget. Implements Singhi et al. "
        .. "(arXiv:2504.01005, COLM 2025) §3.1 cost model "
        .. "C(S,V) = S·(1+λV) and §5.2 power-law allocator "
        .. "S_opt ∝ C^a, V_opt ∝ C^b as five direct-args entries: "
        .. "cost, score_split, optimal_split, sc_pure, compare_paths. "
        .. "Pure Computation — no alc.llm calls; caller drives test-time "
        .. "inference with sc / step_verify / cove. Fills gap not "
        .. "covered by compute_alloc (paradigm choice) or "
        .. "gumbel_search/ab_mcts (search depth-vs-width): intra-paradigm "
        .. "S↔V split.",
    category = "orchestration",
}

-- Paper-faithful defaults; paper § references in comments per
-- the bundled paper-pkg convention.
M._defaults = {
    -- Paper §3.1 GenRM-Base equal-token. INJECT to 2.0 for GenRM-FT.
    lambda                  = 1.0,
    -- Paper §5.2: Llama-3.1-8B + GenRM-FT + MATH transferred default.
    -- Appendix J: 0.69 (70B) / 0.75 (Qwen-7B). caller should fit own.
    exponent_solve          = 0.57,
    exponent_verify         = 0.39,
    -- Paper has NO numeric prefactor values (§3.2 Step 5 = caller fit).
    -- nil ⇒ optimal_split / score_split (with power_law_score_proxy) errors out
    -- when caller does not supply.
    prefactor_solve         = nil,
    prefactor_verify        = nil,
    -- Paper §3.2 not fixed; "round" is a neutral default.
    integer_method          = "round",
    -- Paper §3.2 not fixed when integer-rounded (S_int, V_int) overflow B.
    -- "scale_proportional" preserves the V/S ratio.
    rescale_method          = "scale_proportional",
    -- Paper §3.1 V=0 path. true = SC pure when V_int rounds to 0.
    sc_fallback_when_v_zero = true,
}

-- ─── Shape definitions (local) ───

local params_shape = T.shape({
    lambda           = T.number:describe("Cost ratio T_V / T_S (paper §3.1)"),
    exponent_solve   = T.number:is_optional()
        :describe("a in S_opt ∝ C^a (paper §5.2). Required by optimal_split."),
    exponent_verify  = T.number:is_optional()
        :describe("b in V_opt ∝ C^b (paper §5.2). Required by optimal_split."),
    prefactor_solve  = T.number:is_optional()
        :describe("α_S in S_opt = α_S · C^a (paper §3.2 Step 5; caller-fit). "
            .. "Required by optimal_split and by score_split when power_law_score_proxy is requested."),
    prefactor_verify = T.number:is_optional()
        :describe("α_V in V_opt = α_V · C^b (paper §3.2 Step 5; caller-fit). "
            .. "Required by optimal_split and by score_split when power_law_score_proxy is requested."),
}, { open = true })

local optimal_split_opts_shape = T.shape({
    integer_method          = T.one_of({ "round", "floor", "ceil" }):is_optional()
        :describe("Integer rounding of power-law raw (paper §3.2 not fixed)"),
    rescale_method          = T.one_of({ "scale_proportional", "prefer_solve", "prefer_verify" }):is_optional()
        :describe("Overflow strategy when (S_int, V_int) > B (paper §3.2 not fixed)"),
    v_cap                   = T.number:is_optional()
        :describe("Hard upper cap on V (paper not fixed)"),
    s_cap                   = T.number:is_optional()
        :describe("Hard upper cap on S (paper not fixed)"),
    sc_fallback_when_v_zero = T.boolean:is_optional()
        :describe("When V_int = 0, use SC pure path (default true, §3.1)"),
    cost_model              = T.one_of({ "per_solution", "independent" }):is_optional()
        :describe("'per_solution' (default, paper §3.1) | 'independent' (NOT paper-faithful, v1 unsupported)"),
}, { open = true })

local score_split_opts_shape = T.shape({
    budget = T.number:is_optional()
        :describe("Optional budget B for is_within calculation"),
}, { open = true })

local score_split_result_shape = T.shape({
    cost                  = T.number:describe("S · (1 + λ·V)"),
    is_within             = T.boolean:is_optional()
        :describe("cost ≤ budget when opts.budget is provided"),
    power_law_score_proxy = T.number:is_optional()
        :describe("S^a · V^b proxy (paper §5.2 power-law direction). "
            .. "NOT a paper-§5.2 SR estimate; valid only as a "
            .. "relative-comparison value within the same (a, b) regime. "
            .. "nil when V <= 0 (SC pure path — proxy is undefined)."),
}, { open = true })

local sc_pure_opts_shape = T.shape({
    integer_method = T.one_of({ "round", "floor", "ceil" }):is_optional(),
}, { open = true })

local sc_pure_result_shape = T.shape({
    s_opt          = T.number,
    v_opt          = T.number:describe("Always 0 (SC pure path)"),
    cost_used      = T.number,
    integer_method = T.string,
}, { open = true })

local compare_paths_result_shape = T.shape({
    sc           = sc_pure_result_shape,
    genrm        = T.ref("compute_optimal_split"),
    delta_s_opt  = T.number
        :describe("genrm.s_opt - sc.s_opt (positive when GenRM "
            .. "allocator picks more solutions than SC pure)"),
    delta_v_opt  = T.number
        :describe("genrm.v_opt - sc.v_opt (sc.v_opt is always 0)"),
    cost_ratio   = T.number
        :describe("genrm.cost_used / sc.cost_used (≈ 1 when both "
            .. "saturate the budget). NOTE: paper §5.1 cross-over "
            .. "(8× / 4× / 64×) is verifier-quality and "
            .. "model-dependent — not derivable from (S, V) alone. "
            .. "Caller must compare on observed accuracy."),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        cost = {
            args   = { T.number, T.number, T.number },
            result = T.number,
        },
        score_split = {
            args   = { T.number, T.number, params_shape, score_split_opts_shape:is_optional() },
            result = score_split_result_shape,
        },
        optimal_split = {
            args   = { T.number, params_shape, optimal_split_opts_shape:is_optional() },
            result = "compute_optimal_split",
        },
        sc_pure = {
            args   = { T.number, sc_pure_opts_shape:is_optional() },
            result = sc_pure_result_shape,
        },
        compare_paths = {
            args   = { T.number, params_shape, optimal_split_opts_shape:is_optional() },
            result = compare_paths_result_shape,
        },
    },
}

-- ─── Validation helpers ───

local function check_positive_number(x, name, entry)
    if type(x) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: %s must be a number, got %s",
            entry, name, type(x)), 3)
    end
    if x <= 0 then
        error(string.format(
            "solve_verify_split.%s: %s must be > 0, got %s",
            entry, name, tostring(x)), 3)
    end
end

local function check_budget(B, entry)
    if type(B) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: B must be a number, got %s",
            entry, type(B)), 3)
    end
    if B < 1 then
        error(string.format(
            "solve_verify_split.%s: B must be >= 1 "
            .. "(paper §3.1 cost is in inference-call / token units; "
            .. "got %s)",
            entry, tostring(B)), 3)
    end
end

local function check_nonneg_integer_like(x, name, entry)
    if type(x) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: %s must be a number, got %s",
            entry, name, type(x)), 3)
    end
    if x < 0 then
        error(string.format(
            "solve_verify_split.%s: %s must be >= 0, got %s",
            entry, name, tostring(x)), 3)
    end
end

local function check_lambda(lambda, entry)
    if type(lambda) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: lambda must be a number, got %s",
            entry, type(lambda)), 3)
    end
    if lambda <= 0 then
        error(string.format(
            "solve_verify_split.%s: lambda must be > 0 (got %s); "
            .. "paper §3.1 defines λ = T_V/T_S as a positive ratio.",
            entry, tostring(lambda)), 3)
    end
end

local function check_params_for_optimal(params, entry)
    if type(params) ~= "table" then
        error(string.format(
            "solve_verify_split.%s: params must be a table, got %s",
            entry, type(params)), 3)
    end
    check_lambda(params.lambda, entry)
    if type(params.exponent_solve) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: params.exponent_solve must be a number "
            .. "(paper §5.2 a). Use 0.57 (Llama-8B/GenRM-FT/MATH default) or "
            .. "fit your own — got %s",
            entry, type(params.exponent_solve)), 3)
    end
    if type(params.exponent_verify) ~= "number" then
        error(string.format(
            "solve_verify_split.%s: params.exponent_verify must be a number "
            .. "(paper §5.2 b). Use 0.39 (Llama-8B/GenRM-FT/MATH default) — "
            .. "got %s",
            entry, type(params.exponent_verify)), 3)
    end
    if not (params.exponent_solve > 0 and params.exponent_solve < 1) then
        error(string.format(
            "solve_verify_split.%s: params.exponent_solve must satisfy "
            .. "0 < a < 1 (paper §5.2 + Appendix J observed range "
            .. "a ∈ [0.57, 0.75]); got %s",
            entry, tostring(params.exponent_solve)), 3)
    end
    if not (params.exponent_verify > 0 and params.exponent_verify < 1) then
        error(string.format(
            "solve_verify_split.%s: params.exponent_verify must satisfy "
            .. "0 < b < 1 (paper §5.2 + Appendix J observed range "
            .. "b ∈ [0.32, 0.43]); got %s",
            entry, tostring(params.exponent_verify)), 3)
    end
    if type(params.prefactor_solve) ~= "number" or params.prefactor_solve <= 0 then
        error(string.format(
            "solve_verify_split.%s: params.prefactor_solve must be a positive number "
            .. "(paper has NO numeric value; §3.2 Step 5 caller-fit required) — got %s",
            entry, tostring(params.prefactor_solve)), 3)
    end
    if type(params.prefactor_verify) ~= "number" or params.prefactor_verify <= 0 then
        error(string.format(
            "solve_verify_split.%s: params.prefactor_verify must be a positive number "
            .. "(paper has NO numeric value; §3.2 Step 5 caller-fit required) — got %s",
            entry, tostring(params.prefactor_verify)), 3)
    end
end

-- ─── Pure helpers (paper §3.1, §5.2) ───

local function cost_of(S_, V, lambda)
    return S_ * (1 + lambda * V)
end

local function power_law_raw(B, a, b, alpha_s, alpha_v)
    local s_raw = alpha_s * (B ^ a)
    local v_raw = alpha_v * (B ^ b)
    return s_raw, v_raw
end

local function round_with_method(x, method)
    if method == "floor" then
        return math.floor(x)
    elseif method == "ceil" then
        return math.ceil(x)
    else  -- "round" (default; banker's variant not used — simple half-up)
        return math.floor(x + 0.5)
    end
end

-- Fit (S, V) into the budget by shrinking. Returns (S', V', rescaled).
local function apply_rescale(S_int, V_int, B, lambda, method)
    local C = cost_of(S_int, V_int, lambda)
    if C <= B then
        return S_int, V_int, false
    end
    if method == "prefer_solve" then
        -- keep S, shrink V until C ≤ B
        local v = V_int
        while v > 0 and cost_of(S_int, v, lambda) > B do
            v = v - 1
        end
        if cost_of(S_int, v, lambda) > B then
            -- still over: shrink S too
            local s = S_int
            while s > 1 and cost_of(s, v, lambda) > B do
                s = s - 1
            end
            return s, v, true
        end
        return S_int, v, true
    elseif method == "prefer_verify" then
        -- keep V, shrink S
        local s = S_int
        while s > 1 and cost_of(s, V_int, lambda) > B do
            s = s - 1
        end
        if cost_of(s, V_int, lambda) > B then
            local v = V_int
            while v > 0 and cost_of(s, v, lambda) > B do
                v = v - 1
            end
            return s, v, true
        end
        return s, V_int, true
    else  -- "scale_proportional"
        -- Iteratively shrink S and V together preserving (V/S) ratio.
        local s, v = S_int, V_int
        while cost_of(s, v, lambda) > B and (s > 1 or v > 0) do
            local cur_C = cost_of(s, v, lambda)
            local factor = math.sqrt(B / cur_C)
            local s_next = math.floor(s * factor)
            local v_next = math.floor(v * factor)
            if s_next < 1 then s_next = 1 end
            if v_next < 0 then v_next = 0 end
            if s_next == s and v_next == v then
                -- no progress: drop V first, then S
                if v > 0 then v = v - 1
                elseif s > 1 then s = s - 1
                else break end
            else
                s, v = s_next, v_next
            end
        end
        return s, v, true
    end
end

local function sc_path(B, integer_method)
    local s = round_with_method(B, integer_method or M._defaults.integer_method)
    if s < 0 then s = 0 end
    return s, 0
end

-- Predicted SR projection (caller-supplied curve form is not in paper).
-- We expose only the power-law-implied compute scaling: SR_proxy(S,V) = S^a · V^b
-- which is monotonic in both (matches §5.2 power-law direction). This is
-- a NOT paper-faithful proxy when used as an absolute SR estimate; we only
-- expose it as a relative-comparison value (used by compare_paths advantage).
local function predicted_sr_proxy(S_, V, params)
    if type(params.exponent_solve) ~= "number" or type(params.exponent_verify) ~= "number" then
        return nil
    end
    if S_ <= 0 then return 0 end
    -- V=0 (SC pure path) breaks the V^b factor (V→0+ gives proxy→0
    -- but V=0 is intentionally undefined here). Return nil so callers
    -- cannot accidentally compare SC vs GenRM via this single field.
    -- Use compare_paths.delta_* / observed accuracy for cross-path
    -- comparison.
    if V <= 0 then return nil end
    local s_term = S_ ^ params.exponent_solve
    local v_term = V ^ params.exponent_verify
    return s_term * v_term
end

-- ─── Public entries ───

function M.cost(S_, V, lambda)
    check_nonneg_integer_like(S_, "S", "cost")
    check_nonneg_integer_like(V, "V", "cost")
    check_lambda(lambda, "cost")
    return cost_of(S_, V, lambda)
end

function M.score_split(S_, V, params, opts)
    check_nonneg_integer_like(S_, "S", "score_split")
    check_nonneg_integer_like(V, "V", "score_split")
    if type(params) ~= "table" then
        error(string.format(
            "solve_verify_split.score_split: params must be a table, got %s",
            type(params)), 2)
    end
    check_lambda(params.lambda, "score_split")
    opts = opts or {}
    local c = cost_of(S_, V, params.lambda)
    local result = { cost = c }
    if type(opts.budget) == "number" then
        result.is_within = (c <= opts.budget)
    end
    -- power_law_score_proxy only when both exponents are present
    if type(params.exponent_solve) == "number" and type(params.exponent_verify) == "number" then
        result.power_law_score_proxy = predicted_sr_proxy(S_, V, params)
    end
    return result
end

function M.optimal_split(B, params, opts)
    check_budget(B, "optimal_split")
    check_params_for_optimal(params, "optimal_split")
    opts = opts or {}
    local integer_method = opts.integer_method or M._defaults.integer_method
    local rescale_method = opts.rescale_method or M._defaults.rescale_method
    if integer_method ~= "round" and integer_method ~= "floor" and integer_method ~= "ceil" then
        error(string.format(
            "solve_verify_split.optimal_split: opts.integer_method must be "
            .. "'round'|'floor'|'ceil', got %s", tostring(integer_method)), 2)
    end
    if rescale_method ~= "scale_proportional"
        and rescale_method ~= "prefer_solve"
        and rescale_method ~= "prefer_verify" then
        error(string.format(
            "solve_verify_split.optimal_split: opts.rescale_method must be "
            .. "'scale_proportional'|'prefer_solve'|'prefer_verify', got %s",
            tostring(rescale_method)), 2)
    end
    if opts.cost_model ~= nil and opts.cost_model ~= "per_solution" then
        error(string.format(
            "solve_verify_split.optimal_split: opts.cost_model='%s' is "
            .. "declared NOT paper-faithful and not implemented in v1 "
            .. "(only 'per_solution' is supported per paper §3.1)",
            tostring(opts.cost_model)), 2)
    end
    local sc_fallback = opts.sc_fallback_when_v_zero
    if sc_fallback == nil then sc_fallback = M._defaults.sc_fallback_when_v_zero end

    -- Step 1: power-law raw
    local s_raw, v_raw = power_law_raw(
        B, params.exponent_solve, params.exponent_verify,
        params.prefactor_solve, params.prefactor_verify)

    -- Step 2: integer rounding
    local s_int = round_with_method(s_raw, integer_method)
    local v_int = round_with_method(v_raw, integer_method)
    if s_int < 1 then s_int = 1 end
    if v_int < 0 then v_int = 0 end

    -- Caps (opt-in)
    if type(opts.s_cap) == "number" and s_int > opts.s_cap then s_int = opts.s_cap end
    if type(opts.v_cap) == "number" and v_int > opts.v_cap then v_int = opts.v_cap end

    -- Step 5 short-circuit: V_int = 0 + SC fallback ⇒ SC pure path
    local is_sc_fallback = false
    if v_int == 0 and sc_fallback then
        local sc_s, sc_v = sc_path(B, integer_method)
        return {
            s_opt          = sc_s,
            v_opt          = sc_v,
            cost_used      = cost_of(sc_s, sc_v, params.lambda),
            cost_budget    = B,
            lambda         = params.lambda,
            integer_method = integer_method,
            rescale_method = rescale_method,
            rescaled       = false,
            is_sc_fallback = true,
            raw            = { s_raw = s_raw, v_raw = v_raw },
        }
    end

    -- Step 3-4: cost check + rescale
    local s_final, v_final, rescaled = apply_rescale(s_int, v_int, B, params.lambda, rescale_method)

    -- Post-rescale: if V dropped to 0 and SC fallback enabled, prefer SC pure
    if v_final == 0 and sc_fallback then
        local sc_s, _ = sc_path(B, integer_method)
        if sc_s > s_final then
            s_final = sc_s
            is_sc_fallback = true
        end
    end

    return {
        s_opt          = s_final,
        v_opt          = v_final,
        cost_used      = cost_of(s_final, v_final, params.lambda),
        cost_budget    = B,
        lambda         = params.lambda,
        integer_method = integer_method,
        rescale_method = rescale_method,
        rescaled       = rescaled,
        is_sc_fallback = is_sc_fallback,
        raw            = { s_raw = s_raw, v_raw = v_raw },
    }
end

function M.sc_pure(B, opts)
    check_budget(B, "sc_pure")
    opts = opts or {}
    local integer_method = opts.integer_method or M._defaults.integer_method
    if integer_method ~= "round" and integer_method ~= "floor" and integer_method ~= "ceil" then
        error(string.format(
            "solve_verify_split.sc_pure: opts.integer_method must be "
            .. "'round'|'floor'|'ceil', got %s", tostring(integer_method)), 2)
    end
    local s, v = sc_path(B, integer_method)
    return {
        s_opt          = s,
        v_opt          = v,
        cost_used      = s,        -- C(S, 0) = S
        integer_method = integer_method,
    }
end

function M.compare_paths(B, params, opts)
    check_budget(B, "compare_paths")
    check_params_for_optimal(params, "compare_paths")
    opts = opts or {}
    local sc = M.sc_pure(B, { integer_method = opts.integer_method })
    local genrm = M.optimal_split(B, params, opts)
    return {
        sc           = sc,
        genrm        = genrm,
        delta_s_opt  = genrm.s_opt - sc.s_opt,
        delta_v_opt  = genrm.v_opt - sc.v_opt,
        cost_ratio   = genrm.cost_used / sc.cost_used,
    }
end

-- ─── Test hooks ───
M._internal = {
    cost_of            = cost_of,
    power_law_raw      = power_law_raw,
    round_with_method  = round_with_method,
    apply_rescale      = apply_rescale,
    sc_path            = sc_path,
    predicted_sr_proxy = predicted_sr_proxy,
}

-- ─── Malli-style self-decoration (per-entry) ───
M.cost          = S.instrument(M, "cost")
M.score_split   = S.instrument(M, "score_split")
M.optimal_split = S.instrument(M, "optimal_split")
M.sc_pure       = S.instrument(M, "sc_pure")
M.compare_paths = S.instrument(M, "compare_paths")

return M
