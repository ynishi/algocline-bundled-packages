--- opinion_abm — Hegselmann-Krause Bounded Confidence Opinion Dynamics
---
--- N agents hold continuous opinion values in [0,1].
--- Each step, an agent updates its opinion to the average of all agents
--- whose opinions are within ε (bounded confidence threshold).
---
--- Emergent phenomena: consensus, polarization (2-3 clusters),
--- fragmentation (many clusters). Determined by ε value.
---   ε > 0.5  → consensus (single cluster)
---   ε ≈ 0.2  → polarization (2-3 clusters)
---   ε < 0.1  → fragmentation (many clusters)
---
--- Based on:
---   Hegselmann & Krause, "Opinion Dynamics and Bounded Confidence:
---   Models, Analysis and Simulation", JASSS 5(3), 2002
---
---   Rodrigo, "Extending the Hegselmann-Krause Model to include
---   AI Oracles", arXiv:2502.19701, 2025
---
--- Usage:
---   local opinion = require("opinion_abm")
---   return opinion.run(ctx)
---
--- ctx.task (required): Description of the opinion scenario
--- ctx.n_agents?: number (default 50)
--- ctx.epsilon?: number Bounded confidence threshold (default 0.25)
--- ctx.steps?: number (default 50)
--- ctx.runs?: number MC runs (default 100)
--- ctx.initial_distribution?: "uniform"|"bimodal"|"clustered" (default "uniform")

local abm = require("abm")
local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "opinion_abm",
    version = "0.1.0",
    description = "Hegselmann-Krause Bounded Confidence opinion dynamics — "
        .. "agents update opinions by averaging nearby opinions within threshold ε. "
        .. "Emergent consensus, polarization, or fragmentation.",
    category = "simulation",
}

---@type AlcSpec
-- Phase 6-a-fix: result is shaped precisely via abm.mc.shape /
-- abm.sweep.shape helpers. `distribution` in the internal params hash
-- is always a string (ctx.initial_distribution → DISTRIBUTIONS key;
-- bad values fall back to "uniform" rather than erroring, so shape
-- cannot be stricter at the input layer).
local params_shape = T.shape({
    n_agents     = T.number:describe("Number of agents (default 50)"),
    epsilon      = T.number:describe("Bounded-confidence threshold (default 0.25)"),
    steps        = T.number:describe("Simulation steps (default 50)"),
    distribution = T.string,
})

M.spec = {
    entries = {
        run = {
            input = T.shape({
                task                 = T.string:is_optional():describe("Task description (free text)"),
                n_agents             = T.number:is_optional():describe("Number of agents (default 50)"),
                epsilon              = T.number:is_optional():describe("Bounded-confidence threshold (default 0.25)"),
                steps                = T.number:is_optional():describe("Simulation steps (default 50)"),
                runs                 = T.number:is_optional():describe("Monte Carlo runs (default 100)"),
                initial_distribution = T.string:is_optional():describe("'uniform' | 'bimodal' | 'clustered' (default 'uniform')"),
            }),
            result = T.shape({
                params      = params_shape,
                simulation  = abm.mc.shape({
                    numbers  = { "clusters", "variance" },
                    booleans = { "converged", "consensus", "polarized" },
                }),
                sensitivity = abm.sweep.shape(),
            }),
        },
    },
}

---------------------------------------------------------------------------
-- Initial opinion distributions
---------------------------------------------------------------------------

local function init_uniform(n, rng)
    local opinions = {}
    for i = 1, n do opinions[i] = rng() end
    return opinions
end

local function init_bimodal(n, rng)
    local opinions = {}
    for i = 1, n do
        if rng() < 0.5 then
            opinions[i] = 0.2 + rng() * 0.15  -- cluster around 0.2-0.35
        else
            opinions[i] = 0.65 + rng() * 0.15  -- cluster around 0.65-0.80
        end
    end
    return opinions
end

local function init_clustered(n, rng)
    local opinions = {}
    local n_clusters = 3
    for i = 1, n do
        local center = (math.floor(rng() * n_clusters) + 0.5) / n_clusters
        opinions[i] = math.max(0, math.min(1, center + (rng() - 0.5) * 0.1))
    end
    return opinions
end

local DISTRIBUTIONS = {
    uniform = init_uniform,
    bimodal = init_bimodal,
    clustered = init_clustered,
}

---------------------------------------------------------------------------
-- HK Model core
---------------------------------------------------------------------------

--- Single HK update step (synchronous).
--- All agents update simultaneously based on current opinions.
--- @param opinions number[] Current opinion values
--- @param epsilon number Bounded confidence threshold
--- @return number[] Updated opinions
local function hk_step(opinions, epsilon)
    local n = #opinions
    local new_opinions = {}

    for i = 1, n do
        local sum = 0
        local count = 0
        for j = 1, n do
            if math.abs(opinions[i] - opinions[j]) <= epsilon then
                sum = sum + opinions[j]
                count = count + 1
            end
        end
        new_opinions[i] = sum / count
    end

    return new_opinions
end

--- Count distinct opinion clusters (groups within δ of each other).
--- @param opinions number[]
--- @param delta number Cluster merge threshold (default 0.01)
--- @return number
local function count_clusters(opinions, delta)
    delta = delta or 0.01
    local sorted = {}
    for i, v in ipairs(opinions) do sorted[i] = v end
    table.sort(sorted)

    local clusters = 1
    for i = 2, #sorted do
        if sorted[i] - sorted[i - 1] > delta then
            clusters = clusters + 1
        end
    end
    return clusters
end

--- Compute opinion variance.
local function opinion_variance(opinions)
    local n = #opinions
    if n == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(opinions) do sum = sum + v end
    local mean = sum / n
    local var = 0
    for _, v in ipairs(opinions) do
        local d = v - mean
        var = var + d * d
    end
    return var / n
end

---------------------------------------------------------------------------
-- Simulation runner
---------------------------------------------------------------------------

--- Run a single HK simulation.
--- @param params table { n_agents, epsilon, steps, distribution }
--- @param seed number
--- @return table { clusters, variance, converged, final_opinions_sample }
local function run_single(params, seed)
    local r = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(r) end

    local n = params.n_agents or 50
    local epsilon = params.epsilon or 0.25
    local steps = params.steps or 50
    local dist = params.distribution or "uniform"

    local init_fn = DISTRIBUTIONS[dist] or DISTRIBUTIONS.uniform
    local opinions = init_fn(n, rng)

    -- Run HK dynamics
    for _ = 1, steps do
        local new_opinions = hk_step(opinions, epsilon)

        -- Early convergence check (max change < 1e-6)
        local max_change = 0
        for i = 1, n do
            local d = math.abs(new_opinions[i] - opinions[i])
            if d > max_change then max_change = d end
        end
        opinions = new_opinions
        if max_change < 1e-6 then break end
    end

    local clusters = count_clusters(opinions)
    local variance = opinion_variance(opinions)

    -- Classify outcome
    local converged = variance < 0.001

    return {
        clusters = clusters,
        variance = variance,
        converged = converged,
        consensus = clusters == 1,
        polarized = clusters == 2 or clusters == 3,
    }
end

---------------------------------------------------------------------------
-- M.run(ctx)
---------------------------------------------------------------------------

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    -- ctx.task is available for LLM prompt integration (e.g. via hybrid_abm)

    local params = {
        n_agents = ctx.n_agents or 50,
        epsilon = ctx.epsilon or 0.25,
        steps = ctx.steps or 50,
        distribution = ctx.initial_distribution or "uniform",
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = { "clusters", "variance", "converged", "consensus", "polarized" },
    })

    -- Sensitivity sweep on epsilon
    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = { "epsilon" },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "consensus" },
            })
            return quick.consensus_rate or 0
        end,
    })

    ctx.result = {
        params = params,
        simulation = mc_result,
        sensitivity = sensitivity,
    }
    return ctx
end

--- Expose run_single for use as sim_fn in hybrid_abm.
M.run_single = run_single

-- Malli-style self-decoration. run_single stays uninstrumented
-- (hybrid_abm sim_fn callback).
M.run = S.instrument(M, "run")

return M
