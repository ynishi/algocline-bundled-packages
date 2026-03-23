--- optimize.stop — Stopping criteria for parameter optimization
---
--- Provides pluggable stopping conditions with a unified interface:
---   criterion.should_stop(history, config) → stopped, reason
---
--- Design Rationale:
---   Early stopping is essential to avoid wasting LLM calls on converged
---   or hopeless optimization runs. Neural network training established
---   patience-based early stopping (Prechelt 1998, "Early Stopping — But
---   When?"). This module generalizes that to 4 complementary criteria,
---   composable via the "composite" meta-criterion.
---
--- Built-in criteria:
---
---   "variance" (default)
---     Monitors score variance over a sliding window. Stops when
---     Var(scores) < max(mean²·tolerance, 0.001). Detects convergence
---     when the optimizer has settled on a stable region.
---     Config: { window=5, tolerance=0.01 }
---
---   "patience"
---     Stops when no score exceeds the historical best for N consecutive
---     rounds. Standard early stopping from deep learning.
---     Config: { patience=5 }
---     Ref: Prechelt 1998, "Early Stopping — But When?"
---
---   "threshold"
---     Stops immediately when any score reaches the target. Useful when
---     a "good enough" score is known in advance.
---     Config: { target=0.9 }
---
---   "improvement"
---     Compares average scores of two consecutive windows. Stops when
---     the relative improvement rate drops below min_rate. Detects
---     diminishing returns even when absolute scores are still variable.
---     Config: { window=5, min_rate=0.01 }
---
---   "composite"
---     Combines multiple criteria with OR logic (any triggers stop).
---     Config: { {"patience", {patience=5}}, {"threshold", {target=0.9}} }

local M = {}

-- ============================================================
-- Variance criterion (from original prototype)
-- ============================================================

local variance = {}

function variance.should_stop(history, config)
    local window = (config and config.window) or 5
    local results = history.results
    if #results < window then return false, nil end

    local scores = {}
    for i = #results - window + 1, #results do
        scores[#scores + 1] = results[i].score
    end

    local sum = 0
    for _, s in ipairs(scores) do sum = sum + s end
    local mean = sum / #scores

    local var_sum = 0
    for _, s in ipairs(scores) do var_sum = var_sum + (s - mean) ^ 2 end
    local var = var_sum / #scores

    local tol = (config and config.tolerance) or 0.01
    local converged = var < math.max(mean * mean * tol, 0.001)
    if converged then
        return true, string.format("variance converged (var=%.6f, window=%d)", var, window)
    end
    return false, nil
end

-- ============================================================
-- Patience criterion (early stopping)
-- ============================================================

local patience = {}

function patience.should_stop(history, config)
    local max_patience = (config and config.patience) or 5
    local results = history.results
    if #results < max_patience + 1 then return false, nil end

    -- Find best score before the patience window
    local best_before = -math.huge
    for i = 1, #results - max_patience do
        if results[i].score > best_before then
            best_before = results[i].score
        end
    end

    -- Check if any score in the patience window improved
    local improved = false
    for i = #results - max_patience + 1, #results do
        if results[i].score > best_before then
            improved = true
            break
        end
    end

    if not improved then
        return true, string.format(
            "no improvement for %d rounds (best=%.4f)", max_patience, best_before)
    end
    return false, nil
end

-- ============================================================
-- Threshold criterion (target achieved)
-- ============================================================

local threshold = {}

function threshold.should_stop(history, config)
    local target = config and config.target
    if not target then return false, nil end

    local results = history.results
    if #results == 0 then return false, nil end

    local latest = results[#results]
    if latest.score >= target then
        return true, string.format(
            "threshold reached (score=%.4f >= target=%.4f)", latest.score, target)
    end
    return false, nil
end

-- ============================================================
-- Improvement rate criterion
-- ============================================================

local improvement = {}

function improvement.should_stop(history, config)
    local window = (config and config.window) or 5
    local min_rate = (config and config.min_rate) or 0.01
    local results = history.results
    if #results < window * 2 then return false, nil end

    -- Average of first half vs second half of recent window
    local mid = #results - window
    local sum_old, sum_new = 0, 0
    local n_old, n_new = 0, 0
    for i = mid - window + 1, mid do
        if i >= 1 then
            sum_old = sum_old + results[i].score
            n_old = n_old + 1
        end
    end
    for i = mid + 1, #results do
        sum_new = sum_new + results[i].score
        n_new = n_new + 1
    end

    if n_old == 0 or n_new == 0 then return false, nil end

    local avg_old = sum_old / n_old
    local avg_new = sum_new / n_new
    local rate = (avg_old ~= 0) and ((avg_new - avg_old) / math.abs(avg_old)) or 0

    if rate < min_rate then
        return true, string.format(
            "improvement rate %.4f < min_rate %.4f (old=%.4f, new=%.4f)",
            rate, min_rate, avg_old, avg_new)
    end
    return false, nil
end

-- ============================================================
-- Composite criterion (any of multiple criteria)
-- ============================================================

local composite = {}

function composite.should_stop(history, config)
    local criteria = config and config.criteria
    if not criteria then return false, nil end
    for _, entry in ipairs(criteria) do
        local criterion = M.resolve(entry.name or entry[1])
        local stopped, reason = criterion.should_stop(history, entry.config or entry[2] or {})
        if stopped then return true, reason end
    end
    return false, nil
end

-- ============================================================
-- Registry
-- ============================================================

M.criteria = {
    variance    = variance,
    patience    = patience,
    threshold   = threshold,
    improvement = improvement,
    composite   = composite,
}

--- Resolve a stopping criterion by name or table.
--- Returns { should_stop }.
function M.resolve(spec)
    if spec == nil then return variance end
    if type(spec) == "string" then
        local c = M.criteria[spec]
        if not c then error("optimize.stop: unknown criterion '" .. spec .. "'") end
        return c
    elseif type(spec) == "table" then
        if spec.should_stop then return spec end
        -- Treat as composite config: { {"patience", {patience=5}}, {"threshold", {target=0.9}} }
        return { should_stop = function(h, _cfg)
            return composite.should_stop(h, { criteria = spec })
        end }
    end
    error("optimize.stop: spec must be nil, a string name, or criterion table")
end

return M
