--- optimize.eval — Evaluator components for parameter optimization
---
--- Provides pluggable evaluation strategies with a unified interface:
---   evaluator.evaluate(target, params, scenario, opts) → { mean, std, n, failures }
---
--- Design Rationale:
---   DSPy MIPROv2 [1] separates evaluation from search by passing a metric
---   function to the optimizer. This module applies the same principle:
---   the optimizer orchestrator delegates all scoring to an evaluator,
---   allowing different evaluation backends without changing the search loop.
---
---   This separation is critical for the algocline ecosystem because:
---   (a) evalframe is the standard eval tool but may not always be available
---   (b) rapid prototyping benefits from lightweight eval (custom function)
---   (c) LLM-as-judge enables evaluation without ground-truth datasets
---
--- Built-in evaluators:
---
---   "evalframe" (default)
---     Delegates to algocline's evalframe suite system. Builds a provider
---     from the target strategy, resolves the scenario (by name or inline
---     table), and returns aggregated { mean, std, n } from suite:run().
---     Best for: production optimization with structured test scenarios.
---
---   "custom"
---     Calls a user-provided ctx.eval_fn(target, params, scenario).
---     Accepts either a numeric return (interpreted as mean score) or a
---     table { mean, std, n }. Best for: rapid prototyping, domain-
---     specific scoring, or wrapping external evaluation tools.
---
---   "llm_judge"
---     Uses alc.llm() to directly score a parameter configuration on
---     [0.0, 1.0]. No ground-truth data required. Based on the LLM-as-
---     judge paradigm (Zheng et al. 2023, arXiv:2306.05685). Useful for
---     subjective quality metrics or when labeled data is unavailable.
---     Caveat: scores are non-deterministic and may have systematic bias.

local M = {}

-- ============================================================
-- evalframe evaluator
-- ============================================================

local evalframe_eval = {}

function evalframe_eval.evaluate(target, params, scenario, opts)
    local ef = require("evalframe")

    -- Build strategy opts: merge params into opts
    local strategy_opts = {}
    if opts.strategy_opts then
        for k, v in pairs(opts.strategy_opts) do strategy_opts[k] = v end
    end
    for k, v in pairs(params) do strategy_opts[k] = v end

    local provider = ef.providers.algocline {
        strategy = target,
        opts = strategy_opts,
    }

    -- Resolve scenario
    local scenario_def
    if type(scenario) == "string" then
        local ok, loaded = pcall(require, "scenarios." .. scenario)
        if not ok then
            ok, loaded = pcall(dofile,
                os.getenv("HOME") .. "/.algocline/scenarios/" .. scenario .. ".lua")
        end
        if not ok then
            error("optimize.eval: cannot load scenario '" .. scenario .. "'")
        end
        scenario_def = loaded
    elseif type(scenario) == "table" then
        scenario_def = scenario
    else
        error("optimize.eval: scenario must be a string name or table")
    end

    -- Build suite spec: bindings go into array part, provider+cases into hash part
    local spec = { provider = provider, cases = scenario_def.cases }
    for i, v in ipairs(scenario_def) do
        spec[i] = v
    end

    local suite = ef.suite("optimize_eval")(spec)

    local result = suite:run()
    local agg = result.aggregated
    return {
        mean     = agg.mean or 0,
        std      = agg.std or 0,
        n        = agg.n or 0,
        failures = result.failures and #result.failures or 0,
    }
end

-- ============================================================
-- Custom evaluator (user-provided function)
-- ============================================================

local custom_eval = {}

function custom_eval.evaluate(target, params, scenario, opts)
    local fn = opts.eval_fn
    if not fn then
        error("optimize.eval: 'custom' evaluator requires opts.eval_fn")
    end
    local result = fn(target, params, scenario)
    if type(result) == "number" then
        return { mean = result, std = 0, n = 1, failures = 0 }
    end
    return {
        mean     = result.mean or result.score or 0,
        std      = result.std or 0,
        n        = result.n or 1,
        failures = result.failures or 0,
    }
end

-- ============================================================
-- LLM judge evaluator
-- ============================================================

local llm_judge = {}

function llm_judge.evaluate(target, params, scenario, opts)
    local task = opts.judge_task or scenario
    if type(task) == "table" then
        task = task.description or alc.json_encode(task)
    end
    local score_str = alc.llm(
        string.format(
            "Evaluate this parameter configuration for the strategy '%s'.\n\n"
            .. "Parameters: %s\n"
            .. "Task context: %s\n\n"
            .. "Rate the expected effectiveness of these parameters on a scale of 0.0 to 1.0.\n"
            .. "Respond with ONLY a decimal number.",
            target, alc.json_encode(params), tostring(task)
        ),
        { system = "You are an expert evaluator. Return only a decimal number between 0.0 and 1.0.",
          max_tokens = 20 }
    )
    local score = tonumber(score_str:match("[%d%.]+")) or 0
    score = math.max(0, math.min(1, score))
    return { mean = score, std = 0, n = 1, failures = 0 }
end

-- ============================================================
-- Registry
-- ============================================================

M.evaluators = {
    evalframe = evalframe_eval,
    custom    = custom_eval,
    llm_judge = llm_judge,
}

--- Resolve an evaluator by name or table.
--- Returns { evaluate }.
function M.resolve(spec)
    if spec == nil then return evalframe_eval end
    if type(spec) == "string" then
        local e = M.evaluators[spec]
        if not e then error("optimize.eval: unknown evaluator '" .. spec .. "'") end
        return e
    elseif type(spec) == "table" then
        if not spec.evaluate then
            error("optimize.eval: custom evaluator requires evaluate()")
        end
        return spec
    end
    error("optimize.eval: spec must be nil, a string name, or evaluator table")
end

return M
