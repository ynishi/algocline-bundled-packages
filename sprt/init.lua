--- sprt — Wald Sequential Probability Ratio Test (SPRT) for Bernoulli streams
---
--- Given a Bernoulli stream X₁, X₂, … with unknown parameter p, SPRT
--- decides between H0: p = p0 and H1: p = p1 (with p0 < p1) while
--- observing trials one at a time. Maintains the running log-likelihood
--- ratio
---
---     λ_n = Σᵢ log(f₁(Xᵢ) / f₀(Xᵢ))
---
--- and stops as soon as λ_n crosses an upper boundary A (accept H1) or a
--- lower boundary B (accept H0), using Wald's classical approximations:
---
---     A = log((1 - β) / α)       B = log(β / (1 - α))
---
--- Wald & Wolfowitz (1948) proved SPRT minimizes E[N] among all tests
--- satisfying the (α, β) error constraints under the two boundary
--- hypotheses. This makes SPRT the right primitive for "stop as soon as
--- evidence is strong enough" decisions — complementing cs_pruner
--- (multi-arm anytime-valid elimination) and f_race (ranked Friedman
--- elimination). Key difference:
---
---     cs_pruner : N candidates × D rubric dims, kill on CS overlap.
---     f_race    : N candidates × D dims, kill on Friedman rank gap.
---     sprt      : 1 stream of Bernoulli trials, 2-hypothesis stop.
---
--- References:
---   Wald, A. (1945). "Sequential Tests of Statistical Hypotheses".
---       Ann. Math. Statist. 16(2), 117–186.
---   Wald & Wolfowitz (1948). "Optimum character of the sequential
---       probability ratio test". Ann. Math. Statist. 19(3), 326–339.
---
--- Usage:
---   local sprt = require("sprt")
---   local st = sprt.new({ p0 = 0.5, p1 = 0.75, alpha = 0.05, beta = 0.10 })
---   for _, x in ipairs(stream) do
---       sprt.observe(st, x)
---       if sprt.decide(st).verdict ~= "continue" then break end
---   end
---
--- This is a substrate-style primitive: it does NOT call alc.llm. It only
--- accumulates evidence and exposes the decision boundary. Users compose
--- it inside a recipe (see recipe_quick_vote) or orch driver loop.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "sprt",
    version = "0.1.0",
    description = "Wald Sequential Probability Ratio Test — anytime "
        .. "2-hypothesis stopping rule for Bernoulli streams with (α, β) "
        .. "error guarantees and Wald–Wolfowitz optimal E[N]. Complements "
        .. "cs_pruner (multi-arm anytime-valid elimination) and f_race "
        .. "(Friedman rank elimination).",
    category = "validation",
}

-- ─── Shape specifications ───
--
-- sprt is a library-style primitive (direct-args, no ctx-threading), so
-- each entry declares `args` (positional) and `result` (raw return).

local sprt_cfg = T.shape({
    p0    = T.number:describe("Null Bernoulli rate in (0,1); require p0 < p1"),
    p1    = T.number:describe("Alternative Bernoulli rate in (0,1)"),
    alpha = T.number:describe("Type-I error rate in (0, 0.5)"),
    beta  = T.number:describe("Type-II error rate in (0, 0.5)"),
}, { open = true })

local sprt_state = T.shape({
    p0      = T.number,
    p1      = T.number,
    alpha   = T.number,
    beta    = T.number,
    log_lr  = T.number:describe("Running log-likelihood ratio"),
    n       = T.number:describe("Observations consumed so far"),
    a_bound = T.number:describe("Upper boundary log((1-β)/α)"),
    b_bound = T.number:describe("Lower boundary log(β/(1-α))"),
    verdict = T.string:describe("'continue' | 'accept_h0' | 'accept_h1'"),
}, { open = true })

local sprt_snapshot = T.shape({
    verdict = T.string:describe("'continue' | 'accept_h0' | 'accept_h1'"),
    log_lr  = T.number,
    n       = T.number,
    a_bound = T.number,
    b_bound = T.number,
}, { open = true })

local sprt_sim_result = T.shape({
    verdict   = T.string,
    n         = T.number,
    log_lr    = T.number,
    truncated = T.boolean:describe("True when max_n hit before a verdict"),
}, { open = true })

---@type AlcSpec
M.spec = {
    entries = {
        new = {
            args   = { sprt_cfg },
            result = sprt_state,
        },
        observe = {
            args = {
                sprt_state,
                T.any:describe("Bernoulli outcome: boolean, 0, or 1"),
            },
            result = sprt_state,
        },
        decide = {
            args   = { sprt_state },
            result = sprt_snapshot,
        },
        simulate = {
            args = {
                sprt_cfg,
                T.number:describe("True Bernoulli success rate in [0,1]"),
                T.number:describe("Max number of trials (positive integer)"),
                T.number:is_optional():describe("RNG seed (nil = use global state)"),
            },
            result = sprt_sim_result,
        },
        expected_n_envelope = {
            args = {
                sprt_cfg,
                T.number:describe("True rate p (typically p0 for size or p1 for power)"),
            },
            -- Returns nil when the drift E[log λ | p] is exactly zero
            -- (degenerate point). is_optional() permits that null return.
            result = T.number:is_optional():describe(
                "Wald's envelope E[N]; nil at degenerate zero-drift points"),
        },
    },
}

-- ─── Input validation ───

local function validate_config(cfg)
    if type(cfg) ~= "table" then
        error("sprt.new: cfg must be a table", 3)
    end
    local p0, p1, alpha, beta = cfg.p0, cfg.p1, cfg.alpha, cfg.beta
    if type(p0) ~= "number" or p0 <= 0 or p0 >= 1 then
        error("sprt.new: p0 must be in (0, 1), got " .. tostring(p0), 3)
    end
    if type(p1) ~= "number" or p1 <= 0 or p1 >= 1 then
        error("sprt.new: p1 must be in (0, 1), got " .. tostring(p1), 3)
    end
    if p0 >= p1 then
        error(string.format(
            "sprt.new: require p0 < p1 (got p0=%s, p1=%s). Flip the "
            .. "hypotheses or choose a non-empty gap.",
            tostring(p0), tostring(p1)), 3)
    end
    if type(alpha) ~= "number" or alpha <= 0 or alpha >= 0.5 then
        error("sprt.new: alpha must be in (0, 0.5), got " .. tostring(alpha), 3)
    end
    if type(beta) ~= "number" or beta <= 0 or beta >= 0.5 then
        error("sprt.new: beta must be in (0, 0.5), got " .. tostring(beta), 3)
    end
end

local function to_bernoulli(x)
    if x == true or x == 1 then return 1 end
    if x == false or x == 0 or x == nil then return 0 end
    if type(x) == "number" then
        if x == 1 then return 1 end
        if x == 0 then return 0 end
    end
    error("sprt.observe: outcome must be boolean or 0/1, got "
        .. tostring(x), 3)
end

-- ─── Public API ───

--- Create a new SPRT state.
---
--- Boundaries use Wald's approximation (ignoring overshoot):
---   A = log((1 - β) / α)  — accept H1 when log_lr ≥ A
---   B = log(β / (1 - α))  — accept H0 when log_lr ≤ B
---
--- The classical approximations upper-bound the realized error rates
--- by α* ≤ α / (1 - β) and β* ≤ β / (1 - α), i.e. slightly looser than
--- the declared (α, β) when overshoot is non-negligible. Grid-verified
--- in tests/test_sprt.lua to stay within 2× of declared rates for the
--- typical operating region (α, β ∈ [0.05, 0.2], p0 ∈ [0.3, 0.6],
--- p1 ∈ [0.55, 0.9]).
---
---@param cfg table { p0, p1, alpha, beta }
---@return table state
function M.new(cfg)
    validate_config(cfg)
    return {
        p0      = cfg.p0,
        p1      = cfg.p1,
        alpha   = cfg.alpha,
        beta    = cfg.beta,
        log_lr  = 0,
        n       = 0,
        a_bound = math.log((1 - cfg.beta) / cfg.alpha),
        b_bound = math.log(cfg.beta / (1 - cfg.alpha)),
        verdict = "continue",
    }
end

--- Observe one Bernoulli outcome and update the state in place.
--- Becomes a no-op once a terminal verdict has been reached.
---
---@param state table created by M.new
---@param outcome any boolean, 0, or 1
---@return table state (same reference, mutated)
function M.observe(state, outcome)
    if state.verdict ~= "continue" then
        return state
    end
    local x = to_bernoulli(outcome)
    local p0, p1 = state.p0, state.p1
    local inc
    if x == 1 then
        inc = math.log(p1 / p0)
    else
        inc = math.log((1 - p1) / (1 - p0))
    end
    state.log_lr = state.log_lr + inc
    state.n = state.n + 1
    if state.log_lr >= state.a_bound then
        state.verdict = "accept_h1"
    elseif state.log_lr <= state.b_bound then
        state.verdict = "accept_h0"
    end
    return state
end

--- Snapshot the current decision. Pure function: does not mutate state.
---
---@param state table
---@return table { verdict, log_lr, n, a_bound, b_bound }
function M.decide(state)
    return {
        verdict = state.verdict,
        log_lr  = state.log_lr,
        n       = state.n,
        a_bound = state.a_bound,
        b_bound = state.b_bound,
    }
end

--- Run SPRT to termination (or max_n) on a synthetic Bernoulli(p)
--- stream. Used for α/β grid verification without live LLM cost.
---
--- NOTE: uses Lua's global math.random state — pass `seed` for
--- reproducibility. Monte Carlo callers should set up their own RNG
--- seeding schedule around this function.
---
---@param cfg table { p0, p1, alpha, beta }
---@param p number true Bernoulli success rate in [0, 1]
---@param max_n integer cap on number of trials
---@param seed number|nil RNG seed for reproducibility
---@return table { verdict, n, log_lr, truncated }
function M.simulate(cfg, p, max_n, seed)
    if type(p) ~= "number" or p < 0 or p > 1 then
        error("sprt.simulate: p must be in [0, 1], got " .. tostring(p), 2)
    end
    if type(max_n) ~= "number" or max_n < 1 then
        error("sprt.simulate: max_n must be a positive integer, got "
            .. tostring(max_n), 2)
    end
    if seed ~= nil then
        math.randomseed(seed)
    end
    local st = M.new(cfg)
    for _ = 1, max_n do
        local x = (math.random() < p) and 1 or 0
        M.observe(st, x)
        if st.verdict ~= "continue" then break end
    end
    return {
        verdict   = st.verdict,
        n         = st.n,
        log_lr    = st.log_lr,
        truncated = (st.verdict == "continue"),
    }
end

--- Minimum odd / even sample size (Wald's asymptotic E[N]) at the true
--- parameter p. Useful for sizing max_n defensively.
--- Returns nil when p is exactly at a degenerate boundary (0, 1, or a
--- point where the expected log-LR is zero).
---
--- Wald (1945) §3.4:
---     E[N | p] ≈ [ L(p)·B + (1 - L(p))·A ] / E[log λ | p]
--- where E[log λ | p] = p·log(p1/p0) + (1-p)·log((1-p1)/(1-p0))
--- and L(p) ≈ operating characteristic (not computed here; we return
--- the simpler numerator-only envelope at p = p1 or p = p0).
---@param cfg table { p0, p1, alpha, beta }
---@param p number true rate (typically p1 for power or p0 for size)
---@return number|nil expected_n
function M.expected_n_envelope(cfg, p)
    validate_config(cfg)
    if type(p) ~= "number" or p < 0 or p > 1 then
        error("sprt.expected_n_envelope: p must be in [0, 1]", 2)
    end
    local a_bound = math.log((1 - cfg.beta) / cfg.alpha)
    local b_bound = math.log(cfg.beta / (1 - cfg.alpha))
    local ell = p * math.log(cfg.p1 / cfg.p0)
        + (1 - p) * math.log((1 - cfg.p1) / (1 - cfg.p0))
    if ell == 0 then return nil end
    -- Power-side envelope: at p ≥ p1 the test should accept H1, so
    -- E[N] ≈ A / ell. At p ≤ p0, ≈ |B| / |ell|. Use matching sign.
    if ell > 0 then
        return a_bound / ell
    else
        return b_bound / ell
    end
end

-- Malli-style self-decoration. Each entry is a pure library function
-- (direct-args); the wrapper asserts args / result when ALC_SHAPE_CHECK=1.
M.new                 = S.instrument(M, "new")
M.observe             = S.instrument(M, "observe")
M.decide              = S.instrument(M, "decide")
M.simulate            = S.instrument(M, "simulate")
M.expected_n_envelope = S.instrument(M, "expected_n_envelope")

return M
