--- abm.stats — ABM-specific statistical utilities
---
--- alc.math provides: median, percentile, wilson_ci, rng_*
--- This module adds ABM-specific calculations.
---
--- Usage:
---   local stats = require("abm.stats")
---   if stats.converged(scores, 20, 0.001) then break end

local M = {}

--- Check if a series has converged (variance within window < threshold).
--- @param values number[]
--- @param window number Lookback window size
--- @param threshold number Variance threshold
--- @return boolean
function M.converged(values, window, threshold)
    if #values < window then return false end
    local sum, sum_sq = 0, 0
    for i = #values - window + 1, #values do
        sum = sum + values[i]
        sum_sq = sum_sq + values[i] * values[i]
    end
    local mean = sum / window
    local variance = sum_sq / window - mean * mean
    return variance < threshold
end

--- Compute mean of an array.
--- @param values number[]
--- @return number
function M.mean(values)
    if #values == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(values) do sum = sum + v end
    return sum / #values
end

--- Compute standard deviation.
--- @param values number[]
--- @return number
function M.std(values)
    if #values < 2 then return 0 end
    local m = M.mean(values)
    local sum_sq = 0
    for _, v in ipairs(values) do
        local d = v - m
        sum_sq = sum_sq + d * d
    end
    return math.sqrt(sum_sq / (#values - 1))
end

--- Aggregate boolean results: count, rate, Wilson CI.
--- @param results boolean[]
--- @param confidence? number (default 0.95)
--- @return table { count, total, rate, ci_lower, ci_upper }
function M.bool_aggregate(results, confidence)
    confidence = confidence or 0.95
    local count = 0
    for _, v in ipairs(results) do
        if v then count = count + 1 end
    end
    local total = #results
    local rate = total > 0 and (count / total) or 0
    local ci = alc.math.wilson_ci(count, total, confidence)
    return {
        count = count,
        total = total,
        rate = rate,
        ci_lower = ci.lower,
        ci_upper = ci.upper,
    }
end

--- Aggregate numeric results: median, p25, p75, mean, std.
--- @param values number[]
--- @return table
function M.num_aggregate(values)
    if #values == 0 then
        return { median = 0, p25 = 0, p75 = 0, mean = 0, std = 0 }
    end
    return {
        median = alc.math.median(values),
        p25 = alc.math.percentile(values, 25),
        p75 = alc.math.percentile(values, 75),
        mean = M.mean(values),
        std = M.std(values),
    }
end

return M
