--- abm.sweep — Parameter sensitivity analysis
---
--- Two-tier adaptive sweep: probes parameter perturbations to find
--- which parameters most affect the outcome.
---
--- Usage:
---   local sweep = require("abm.sweep")
---   local results = sweep.run({
---       base_params = params,
---       param_names = { "trust_solo", "switching_cost_in" },
---       eval_fn = function(p) return quick_survival(p) end,
---       tiers = { 0.20, 0.50 },
---   })

local M = {}

--- Copy a flat params table.
local function copy_params(p)
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    return c
end

--- Sweep all params at a given perturbation factor.
--- @param base table Base parameters
--- @param names string[] Parameter names to sweep
--- @param eval_fn function(params) → number Score (0-1)
--- @param factor number Perturbation (e.g. 0.20 = ��20%)
--- @return table[] Sensitivity results (delta descending)
local function sweep_at_factor(base, names, eval_fn, factor)
    local results = {}

    for _, name in ipairs(names) do
        local base_val = base[name]
        if type(base_val) == "number" and base_val > 0 then
            -- Low perturbation
            local lo = copy_params(base)
            lo[name] = base_val * (1 - factor)
            local lo_score = eval_fn(lo)

            -- High perturbation
            local hi = copy_params(base)
            hi[name] = base_val * (1 + factor)
            local hi_score = eval_fn(hi)

            results[#results + 1] = {
                param = name,
                base_value = base_val,
                low_value = lo[name],
                high_value = hi[name],
                score_at_low = lo_score,
                score_at_high = hi_score,
                delta = math.abs(hi_score - lo_score),
                factor = factor,
            }
        end
    end

    table.sort(results, function(a, b) return a.delta > b.delta end)
    return results
end

--- Run adaptive sensitivity sweep.
---
--- @param opts table
---   base_params: table       — base parameter set
---   param_names: string[]    — which parameters to sweep
---   eval_fn: function(params) → number  — scoring function (0-1)
---   tiers?: number[]         — perturbation factors (default {0.20, 0.50})
--- @return table[] Sensitivity results (delta descending)
function M.run(opts)
    local base = opts.base_params or error("sweep.run: base_params required", 2)
    local names = opts.param_names or error("sweep.run: param_names required", 2)
    local eval_fn = opts.eval_fn or error("sweep.run: eval_fn required", 2)
    local tiers = opts.tiers or { 0.20, 0.50 }

    for _, factor in ipairs(tiers) do
        local results = sweep_at_factor(base, names, eval_fn, factor)

        -- Check if any parameter showed sensitivity
        local max_delta = 0
        for _, r in ipairs(results) do
            if r.delta > max_delta then max_delta = r.delta end
        end

        if max_delta > 0.001 then
            return results
        end
    end

    -- All tiers stable — return last tier's results (all zero delta)
    return sweep_at_factor(base, names, eval_fn, tiers[#tiers])
end

--- Build the result T.shape produced by `M.run`.
---
--- The row shape is fixed by `sweep_at_factor` above (the single
--- source of truth for sweep row keys lives together with this
--- helper). Length is variable (= count of numeric positive
--- `param_names`) so this is an `array_of` with no size bound.
---
--- @return table Schema (T.array_of(T.shape))
function M.shape()
    local S = require("alc_shapes")
    local T = S.T
    return T.array_of(T.shape({
        param         = T.string,
        base_value    = T.number,
        low_value     = T.number,
        high_value    = T.number,
        score_at_low  = T.number,
        score_at_high = T.number,
        delta         = T.number,
        factor        = T.number,
    }))
end

return M
