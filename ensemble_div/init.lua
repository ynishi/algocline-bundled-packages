--- ensemble_div — Ambiguity Decomposition (Krogh-Vedelsby 1995)
---
--- Pure-computation utility for ensemble diversity measurement.
--- Implements the fundamental identity: E = E_bar - A_bar
---
---   E     = ensemble squared error = (V - t)^2
---   E_bar = weighted average individual error = SUM w_a * (V^a - t)^2
---   A_bar = ambiguity (diversity) = SUM w_a * (V^a - V)^2
---
--- This identity holds WITHOUT any independence assumption and for
--- arbitrary weight distributions. It is exact, not an approximation.
---
--- Key insight: A_bar > 0 => E < E_bar (ensemble always beats the
--- weighted average of individuals when there is any disagreement).
---
--- Based on: Krogh, Vedelsby. "Neural Network Ensembles, Cross Validation,
--- and Active Learning". NeurIPS 7, pp.231-238, 1995 (Eq. 6).
---
--- Hong-Page's Diversity Prediction Theorem (PNAS 2004) is the same
--- identity restated: "crowd error = avg individual error - diversity".
--- Unified here per foundations_selected.md F4 + OQ-5.
---
--- Usage:
---   local ed = require("ensemble_div")
---   local r = ed.decompose({0.8, 0.6, 0.9}, 1.0)
---   -- r.E, r.E_bar, r.A_bar, r.identity_holds

local M = {}

---@type AlcMeta
M.meta = {
    name = "ensemble_div",
    version = "0.1.0",
    description = "Ambiguity Decomposition — Krogh-Vedelsby Eq.6 identity "
        .. "E = E_bar - A_bar for ensemble diversity measurement",
    category = "foundation",
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

return M
