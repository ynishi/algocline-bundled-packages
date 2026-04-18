--- ensemble_div — Ambiguity Decomposition (Krogh-Vedelsby 1995)
---
--- Pure-computation utility for ensemble diversity measurement.
--- Implements the fundamental identity: E = E_bar - A_bar
---
---   E     = ensemble squared error = (V - t)²
---   E_bar = weighted average individual error = Σ w_a · (V^a - t)²
---   A_bar = ambiguity (diversity) = Σ w_a · (V^a - V)²
---
--- This identity holds WITHOUT any independence assumption and for
--- arbitrary weight distributions. It is exact, not an approximation.
---
--- Key insight: A_bar > 0 ⟹ E < E_bar (ensemble always beats the
--- weighted average of individuals when there is any disagreement).
---
--- Theory:
---   Krogh, Vedelsby. "Neural Network Ensembles, Cross Validation,
---   and Active Learning". NeurIPS 7, pp.231-238, 1995 (Eq. 6).
---
---   Hong, Page. "Groups of diverse problem solvers can outperform
---   groups of high-ability problem solvers". PNAS 101(46),
---   pp.16385-16389, 2004. (Same identity restated as the Diversity
---   Prediction Theorem: crowd error = avg error - diversity.)
---
--- Multi-Agent / Swarm context:
---   This decomposition answers the fundamental question of multi-agent
---   systems: "Does adding another agent actually help?"
---
---   - Diversity monitoring: A_bar measures how much agents disagree.
---     If A_bar ≈ 0, agents are redundant (same model/prompt producing
---     near-identical outputs). Diversity is the ONLY mechanism by which
---     ensembles reduce error — without it, more agents are pure waste.
---   - Ensemble health: decompose() verifies the identity E = E_bar - A_bar
---     in real time, providing a live diagnostic of ensemble quality.
---   - Weight optimization: non-uniform weights (e.g. from mwu or ucb)
---     are fully supported. The identity holds for arbitrary weights.
---   - Composable with panel, moa, sc as a diagnostic layer: run
---     decompose() on agent outputs to measure whether the ensemble
---     is actually benefiting from diversity or just adding cost.
---   - Connects to condorcet (independence assumption) and inverse_u
---     (diminishing returns): low diversity often co-occurs with
---     high correlation and inverse-U scaling.
---
--- Usage:
---   local ed = require("ensemble_div")
---   local r = ed.decompose({0.8, 0.6, 0.9}, 1.0)
---   -- r.E, r.E_bar, r.A_bar, r.identity_holds

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "ensemble_div",
    version = "0.1.0",
    description = "Ambiguity Decomposition — Krogh-Vedelsby Eq.6 identity "
        .. "E = Ē − Ā for ensemble diversity measurement. Quantifies "
        .. "how much agent disagreement reduces ensemble error "
        .. "(Krogh-Vedelsby NeurIPS 1995, Hong-Page PNAS 2004).",
    category = "aggregation",
}

---@type AlcSpec
M.spec = {
    entries = {
        ensemble = {
            args   = {
                T.array_of(T.number),
                T.array_of(T.number):is_optional(),
            },
            result = T.number,
        },
        ambiguity = {
            args   = {
                T.array_of(T.number),
                T.array_of(T.number):is_optional(),
            },
            result = T.number,
        },
        avg_error = {
            args   = {
                T.array_of(T.number),
                T.number,
                T.array_of(T.number):is_optional(),
            },
            result = T.number,
        },
        ensemble_error = {
            args   = {
                T.array_of(T.number),
                T.number,
                T.array_of(T.number):is_optional(),
            },
            result = T.number,
        },
        decompose = {
            args   = {
                T.array_of(T.number),
                T.number,
                T.array_of(T.number):is_optional(),
            },
            result = T.shape({
                E              = T.number,
                E_bar          = T.number,
                A_bar          = T.number,
                V              = T.number,
                identity_holds = T.boolean,
                identity_error = T.number,
            }),
        },
    },
}

-- ─── Internal helpers ───

--- Validate and normalize weights.
--- If nil, returns uniform weights. Otherwise validates sum ~= 1.
local function normalize_weights(scores, weights)
    local n = #scores
    if not weights then
        local w = {}
        for i = 1, n do w[i] = 1 / n end
        return w
    end
    if #weights ~= n then
        error("ensemble_div: weights length (" .. #weights ..
              ") != scores length (" .. n .. ")")
    end
    local sum = 0
    for _, w in ipairs(weights) do
        if type(w) ~= "number" or w < 0 then
            error("ensemble_div: weights must be non-negative numbers")
        end
        sum = sum + w
    end
    if math.abs(sum - 1.0) > 1e-6 then
        -- Renormalize
        local normed = {}
        for i, w in ipairs(weights) do normed[i] = w / sum end
        return normed
    end
    return weights
end

-- ─── Public API ───

--- Compute ensemble prediction (weighted average).
---@param scores table list of numeric individual predictions {V^1, V^2, ...}
---@param weights table|nil optional weights (default: uniform)
---@return number V weighted ensemble prediction
function M.ensemble(scores, weights)
    if type(scores) ~= "table" or #scores == 0 then
        error("ensemble_div.ensemble: need a non-empty list of scores")
    end
    local w = normalize_weights(scores, weights)
    local V = 0
    for i, s in ipairs(scores) do
        V = V + w[i] * s
    end
    return V
end

--- Compute ambiguity (diversity): A_bar = SUM w_a * (V^a - V)^2
---@param scores table list of numeric predictions
---@param weights table|nil optional weights
---@return number A_bar ambiguity / diversity measure
function M.ambiguity(scores, weights)
    if type(scores) ~= "table" or #scores == 0 then
        error("ensemble_div.ambiguity: need a non-empty list of scores")
    end
    local w = normalize_weights(scores, weights)
    local V = M.ensemble(scores, w)
    local A = 0
    for i, s in ipairs(scores) do
        local d = s - V
        A = A + w[i] * d * d
    end
    return A
end

--- Compute average individual error: E_bar = SUM w_a * (V^a - t)^2
---@param scores table list of numeric predictions
---@param target number the true value t
---@param weights table|nil optional weights
---@return number E_bar weighted average individual squared error
function M.avg_error(scores, target, weights)
    if type(scores) ~= "table" or #scores == 0 then
        error("ensemble_div.avg_error: need a non-empty list of scores")
    end
    if type(target) ~= "number" then
        error("ensemble_div.avg_error: target must be a number")
    end
    local w = normalize_weights(scores, weights)
    local E = 0
    for i, s in ipairs(scores) do
        local d = s - target
        E = E + w[i] * d * d
    end
    return E
end

--- Compute ensemble error: E = (V - t)^2
---@param scores table list of numeric predictions
---@param target number the true value t
---@param weights table|nil optional weights
---@return number E ensemble squared error
function M.ensemble_error(scores, target, weights)
    local V = M.ensemble(scores, weights)
    local d = V - target
    return d * d
end

--- Full decomposition: E = E_bar - A_bar (Eq. 6).
--- Returns all three quantities plus a verification flag.
---@param scores table list of numeric predictions {V^1, V^2, ...}
---@param target number the true value t
---@param weights table|nil optional weights (default: uniform)
---@return table result { E, E_bar, A_bar, V, identity_holds, identity_error }
function M.decompose(scores, target, weights)
    if type(scores) ~= "table" or #scores == 0 then
        error("ensemble_div.decompose: need a non-empty list of scores")
    end
    if type(target) ~= "number" then
        error("ensemble_div.decompose: target must be a number")
    end
    local w = normalize_weights(scores, weights)
    local V = M.ensemble(scores, w)

    local E = (V - target) * (V - target)
    local E_bar = 0
    local A_bar = 0
    for i, s in ipairs(scores) do
        E_bar = E_bar + w[i] * (s - target) * (s - target)
        A_bar = A_bar + w[i] * (s - V) * (s - V)
    end

    -- Verify identity: E = E_bar - A_bar
    local identity_error = math.abs(E - (E_bar - A_bar))
    local identity_holds = identity_error < 1e-10

    return {
        E = E,
        E_bar = E_bar,
        A_bar = A_bar,
        V = V,
        identity_holds = identity_holds,
        identity_error = identity_error,
    }
end

-- Malli-style self-decoration. Internal M.ensemble calls go through
-- the wrapper, re-validating args but returning identical results.
M.ensemble       = S.instrument(M, "ensemble")
M.ambiguity      = S.instrument(M, "ambiguity")
M.avg_error      = S.instrument(M, "avg_error")
M.ensemble_error = S.instrument(M, "ensemble_error")
M.decompose      = S.instrument(M, "decompose")

return M
