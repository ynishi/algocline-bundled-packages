--- hybrid_abm — LLM-as-Parameterizer Agent-Based Model strategy
---
--- Hybrid architecture: LLM extracts simulation parameters (Phase A),
--- Pure Lua ABM runs Monte Carlo (Phase B+C), sensitivity sweep (Phase D).
---
--- Based on: FCLAgent (arXiv:2510.12189) — "judgment = LLM, execution = rules"
--- decoupling. JASSS position paper (arXiv:2507.19364) modular hybrid recommendation.
---
--- The key insight: LLM is excellent at extracting domain parameters from
--- natural language descriptions, but terrible at running simulations.
--- ABM is excellent at simulating emergent behavior from simple rules.
--- Combining them gives better results than either alone.
---
--- Usage:
---   local hybrid = require("hybrid_abm")
---   return hybrid.run(ctx)
---
--- ctx.task (required): Description of what to simulate
--- ctx.param_prompt (required): LLM prompt template (%s = task)
--- ctx.param_schema: { {name, min, max, default}, ... }
--- ctx.sim_fn (required): function(params, seed) → result table
--- ctx.extract (required): string[] — keys to aggregate
--- ctx.classify_fn?: function(agg) → equilibrium table
--- ctx.runs?: number (default 200)
--- ctx.sweep_params?: string[] (default: from param_schema)
--- ctx.sweep_runs?: number (default 50, for quick eval per perturbation)
---
--- Shape policy (why hybrid_abm is NOT S.instrument-decorated):
---   Phase 6-a-fix-3: sibling ABM pkgs (boids_abm, epidemic_abm, evogame_abm,
---   opinion_abm, schelling_abm, sugarscape_abm) all declare their result
---   shape via `abm.mc.shape({numbers = ..., booleans = ...})` because their
---   `extract` key set is known at load time.
---
---   hybrid_abm is different: `extract`, `sim_fn`, `classify_fn`,
---   `param_schema`, `sweep_params` are ALL supplied by the caller via ctx
---   at run time. The set of suffix-expanded keys in ctx.result.simulation
---   (K_median / K_rate / K_ci / ...) therefore depends on the caller's
---   extract list and cannot be pinned at module load. Declaring a closed
---   T.shape({...}) here would either reject valid callers or degrade to
---   T.table opaque, and T.table opaque ≡ T.any (no discoverability value).
---
---   Resolution: hybrid_abm stays un-instrumented. Callers that wrap
---   hybrid_abm (e.g. a domain-specific pkg that fixes its own extract set)
---   should call `abm.mc.shape(...)` with their known keys in their own
---   M.spec, then `S.instrument` at their layer. See boids_abm/init.lua for
---   the canonical pattern.

local abm = require("abm")

local M = {}

---@type AlcMeta
M.meta = {
    name = "hybrid_abm",
    version = "0.1.0",
    description = "LLM-as-Parameterizer ABM — LLM extracts sim parameters, "
        .. "Pure Lua ABM runs Monte Carlo simulation + sensitivity sweep. "
        .. "Based on FCLAgent (arXiv:2510.12189) hybrid architecture.",
    category = "simulation",
}

---------------------------------------------------------------------------
-- Phase A: LLM Parameter Extraction
---------------------------------------------------------------------------

--- Clamp a parameter value to schema bounds.
local function clamp_param(value, schema_entry)
    if type(value) ~= "number" then return schema_entry.default end
    if value < schema_entry.min then return schema_entry.min end
    if value > schema_entry.max then return schema_entry.max end
    return value
end

--- Extract and validate parameters via LLM.
--- @param task string
--- @param prompt_template string Format string (%s = task)
--- @param schema? table[] { {name, min, max, default}, ... }
--- @return table params
local function extract_params(task, prompt_template, schema)
    local prompt = string.format(prompt_template, task)
    local params = alc.llm_json(prompt, {
        system = "You are a parameter extraction engine. "
            .. "Output ONLY valid JSON. No markdown, no explanation.",
        max_tokens = 500,
    })

    if not params then
        error("hybrid_abm: LLM parameter extraction failed (no valid JSON returned)")
    end

    -- Schema-based clamping
    if schema then
        for _, s in ipairs(schema) do
            params[s.name] = clamp_param(params[s.name], s)
        end
    end

    return params
end

---------------------------------------------------------------------------
-- Phase D helper: quick eval for sweep
---------------------------------------------------------------------------

--- Build a quick-eval function for sensitivity sweep.
--- Runs a reduced MC (sweep_runs iterations) and returns the first
--- boolean key's rate as the score.
local function make_sweep_eval(sim_fn, extract_keys, sweep_runs)
    return function(params)
        local quick = abm.mc.run({
            sim_fn = function(seed) return sim_fn(params, seed) end,
            runs = sweep_runs,
            extract = extract_keys,
        })
        -- Return first boolean rate found, or first numeric median
        for _, key in ipairs(extract_keys) do
            if quick[key .. "_rate"] then return quick[key .. "_rate"] end
        end
        for _, key in ipairs(extract_keys) do
            if quick[key .. "_median"] then return quick[key .. "_median"] end
        end
        return 0
    end
end

---------------------------------------------------------------------------
-- M.run(ctx) — alc_advice compatible entry point
---------------------------------------------------------------------------

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local sim_fn = ctx.sim_fn or error("ctx.sim_fn is required")
    local extract_keys = ctx.extract or error("ctx.extract is required")

    -- Phase A: LLM parameter extraction (or use pre-supplied params)
    local params
    if ctx.param_prompt then
        params = extract_params(task, ctx.param_prompt, ctx.param_schema)
        alc.log("info", string.format(
            "hybrid_abm: extracted %d params via LLM",
            ctx.param_schema and #ctx.param_schema or 0
        ))
    elseif ctx.params then
        params = ctx.params
    else
        error("ctx.param_prompt or ctx.params required")
    end

    -- Phase B+C: Monte Carlo simulation
    local mc_runs = ctx.runs or 200
    local mc_result = abm.mc.run({
        sim_fn = function(seed) return sim_fn(params, seed) end,
        runs = mc_runs,
        extract = extract_keys,
        classify_fn = ctx.classify_fn,
    })

    alc.log("info", string.format("hybrid_abm: MC complete — %d runs", mc_runs))

    -- Phase D: Sensitivity sweep (optional)
    local sensitivity = {}
    local sweep_params = ctx.sweep_params
    if not sweep_params and ctx.param_schema then
        sweep_params = {}
        for _, s in ipairs(ctx.param_schema) do
            sweep_params[#sweep_params + 1] = s.name
        end
    end

    if sweep_params and #sweep_params > 0 then
        local sweep_runs = ctx.sweep_runs or 50
        sensitivity = abm.sweep.run({
            base_params = params,
            param_names = sweep_params,
            eval_fn = make_sweep_eval(sim_fn, extract_keys, sweep_runs),
        })

        -- Log top 3 sensitivity drivers
        for i = 1, math.min(3, #sensitivity) do
            local s = sensitivity[i]
            alc.log("info", string.format(
                "hybrid_abm: sensitivity — %s: delta=%.1f%% (lo=%.1f%% hi=%.1f%%)",
                s.param, s.delta * 100, s.score_at_low * 100, s.score_at_high * 100
            ))
        end
    end

    ctx.result = {
        params = params,
        simulation = mc_result,
        sensitivity = sensitivity,
    }
    return ctx
end

return M
