--- abm.mc — Monte Carlo simulation runner
---
--- Runs a simulation function N times with different seeds,
--- collects results, and produces aggregate statistics.
---
--- Usage:
---   local mc = require("abm.mc")
---   local result = mc.run({
---       sim_fn = function(seed) return run_single(params, seed) end,
---       runs = 200,
---       extract = { "survived", "final_users", "final_revenue" },
---   })
---   -- result.survived_rate, result.survived_ci
---   -- result.final_users_median, result.final_users_p25, ...

local stats = require("abm.stats")

local M = {}

--- Run Monte Carlo simulation.
---
--- @param opts table
---   sim_fn: function(seed: number) → table  — single run
---   runs?: number                            — MC iterations (default 200)
---   extract: string[]                        — keys to collect from results
---   classify_fn?: function(agg) → table      — equilibrium classifier
---   seed_fn?: function(run_index) → number   — custom seed generator
--- @return table Aggregated results
function M.run(opts)
    local sim_fn = opts.sim_fn or error("mc.run: sim_fn required", 2)
    local runs = opts.runs or 200
    local extract = opts.extract or error("mc.run: extract required", 2)
    local seed_fn = opts.seed_fn or function(i) return i * 7919 end

    -- Collect raw values per key
    local raw = {}         -- key → number[]
    local raw_bool = {}    -- key → boolean[]
    local key_is_bool = {} -- key → boolean (detected from first non-nil value)

    for _, key in ipairs(extract) do
        raw[key] = {}
        raw_bool[key] = {}
    end

    for run = 1, runs do
        local result = sim_fn(seed_fn(run))
        for _, key in ipairs(extract) do
            local v = result[key]
            if v ~= nil then
                -- Auto-detect type from first value
                if key_is_bool[key] == nil then
                    key_is_bool[key] = (type(v) == "boolean")
                end
                if key_is_bool[key] then
                    raw_bool[key][#raw_bool[key] + 1] = v
                else
                    raw[key][#raw[key] + 1] = tonumber(v) or 0
                end
            end
        end
    end

    -- Aggregate
    local agg = { runs = runs }

    for _, key in ipairs(extract) do
        if key_is_bool[key] then
            local ba = stats.bool_aggregate(raw_bool[key])
            agg[key .. "_rate"] = ba.rate
            agg[key .. "_ci"] = { lower = ba.ci_lower, upper = ba.ci_upper }
            agg[key .. "_count"] = ba.count
        elseif #raw[key] > 0 then
            local na = stats.num_aggregate(raw[key])
            agg[key .. "_median"] = na.median
            agg[key .. "_p25"] = na.p25
            agg[key .. "_p75"] = na.p75
            agg[key .. "_mean"] = na.mean
            agg[key .. "_std"] = na.std
        end
    end

    -- Optional classification
    if opts.classify_fn then
        agg.equilibrium = opts.classify_fn(agg)
    end

    return agg
end

--- Build the result T.shape produced by `M.run` for a given extract
--- classification.
---
--- Callers declare which extract keys are numeric vs boolean (the
--- author of each ABM pkg knows this from their own `run_single`
--- return type). This function expands each key using the single
--- source of truth for suffix convention that lives together with
--- `M.run` above:
---   number key `K` → K_median / K_p25 / K_p75 / K_mean / K_std
---   bool   key `K` → K_rate / K_ci{lower,upper} / K_count
--- `runs` is always present. When `with_classify = true`, the
--- `equilibrium` key becomes part of the contract (opaque table,
--- since classify_fn is caller-defined).
---
--- @param spec table
---   numbers?: string[]          — extract keys that resolve to numbers
---   booleans?: string[]         — extract keys that resolve to booleans
---   with_classify?: boolean     — include `equilibrium` in the shape
--- @return table Schema (T.shape, open)
function M.shape(spec)
    local S = require("alc_shapes")
    local T = S.T
    spec = spec or {}

    local fields = { runs = T.number }

    for _, key in ipairs(spec.numbers or {}) do
        fields[key .. "_median"] = T.number
        fields[key .. "_p25"]    = T.number
        fields[key .. "_p75"]    = T.number
        fields[key .. "_mean"]   = T.number
        fields[key .. "_std"]    = T.number
    end

    for _, key in ipairs(spec.booleans or {}) do
        fields[key .. "_rate"]  = T.number
        fields[key .. "_ci"]    = T.shape({
            lower = T.number,
            upper = T.number,
        })
        fields[key .. "_count"] = T.number
    end

    if spec.with_classify then
        fields.equilibrium = T.table  -- caller-defined payload
    end

    return T.shape(fields)  -- open=true default (tolerates future additions)
end

--- Run Monte Carlo with Model-based API.
--- Creates a fresh model per run, sets seed, runs N steps, extracts.
---
--- @param opts table
---   model_fn: function(seed) → model    — factory
---   steps: number                        — steps per run
---   runs?: number                        — MC iterations (default 200)
---   extract_fn: function(model) → table  — extract results from final model
---   extract: string[]                    — keys in the extracted table
---   classify_fn?: function(agg) → table
--- @return table Aggregated results
function M.run_model(opts)
    local model_fn = opts.model_fn or error("mc.run_model: model_fn required", 2)
    local steps = opts.steps or error("mc.run_model: steps required", 2)
    local extract_fn = opts.extract_fn or error("mc.run_model: extract_fn required", 2)
    local Model = require("abm.frame.model")

    return M.run({
        sim_fn = function(seed)
            local model = model_fn(seed)
            Model.set_seed(model, seed)
            Model.run(model, steps)
            return extract_fn(model)
        end,
        runs = opts.runs,
        extract = opts.extract,
        classify_fn = opts.classify_fn,
        seed_fn = opts.seed_fn,
    })
end

return M
