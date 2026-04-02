--- optimize — Modular parameter optimization orchestrator
--- Explores parameter configurations for a target strategy by composing
--- pluggable search strategies, evaluators, and stopping criteria.
--- Persists history in alc.state for incremental optimization across sessions.
---
--- Design Rationale:
---   Automatic Prompt Optimization (APO) research identifies 4 core concerns
---   in any optimization loop: candidate generation, evaluation, selection,
---   and termination. This package separates those concerns into composable
---   submodules, following the promptolution framework's modular architecture
---   (Hebenstreit et al. 2024, arXiv:2512.02840).
---
---   The orchestrator itself is intentionally thin — it owns only the
---   optimization loop, state persistence (via alc.state), and result
---   aggregation. All domain logic is delegated to pluggable components.
---   This mirrors DSPy's separation of program structure from optimizer
---   (Khattab et al. 2023, arXiv:2310.03714).
---
--- Architecture (4-component separation):
---   optimize/init.lua   — Orchestrator (this file): loop control, state, results
---   optimize/search.lua — Search strategies: ucb, random, opro, ea, greedy
---   optimize/eval.lua   — Evaluators: evalframe, custom, llm_judge
---   optimize/stop.lua   — Stopping criteria: variance, patience, threshold, improvement
---
--- References:
---   [1] Khattab et al. "DSPy: Compiling Declarative Language Model Calls
---       into Self-Improving Pipelines" (2023, arXiv:2310.03714)
---   [2] Yang et al. "Large Language Models as Optimizers" — OPRO
---       (2023, arXiv:2309.03409)
---   [3] Guo et al. "EvoPrompt: Connecting LLMs with Evolutionary Algorithms
---       Yields Powerful Prompt Optimizers" (ICLR 2024, arXiv:2309.08532)
---   [4] Yuksekgonul et al. "TextGrad: Automatic Differentiation via Text"
---       (Nature 2024, arXiv:2406.07496)
---   [5] Hebenstreit et al. "promptolution: A Unified, Modular Framework
---       for Prompt Optimization" (2024, arXiv:2512.02840)
---   [6] APO Survey: "A Systematic Survey of Automatic Prompt Optimization
---       Techniques" (2025, arXiv:2502.16923)
---
--- Usage:
---   local optimize = require("optimize")
---   return optimize.run(ctx)
---
--- ctx.target    (required): Strategy package name (e.g. "biz_kernel")
--- ctx.space     (required): Parameter search space definition
---   { param_name = { type="int"|"float"|"choice", min, max, step, values }, ... }
--- ctx.scenario  (required): Eval scenario (inline table or scenario name string)
--- ctx.rounds    (optional): Max optimization rounds (default: 20)
--- ctx.search    (optional): Search strategy — "ucb"|"random"|"opro"|"ea"|"greedy" or table (default: "ucb")
--- ctx.evaluator (optional): Evaluator — "evalframe"|"custom"|"llm_judge" or table (default: "evalframe")
--- ctx.stop      (optional): Stopping criterion — "variance"|"patience"|"threshold"|"improvement" or table (default: "variance")
--- ctx.stop_config (optional): Config for stopping criterion (e.g. { patience=5 })
--- ctx.name      (optional): Optimization run name for state key (default: ctx.target)
--- ctx.defaults  (optional): Base parameter defaults (merged with arm params)
--- ctx.strategy_opts (optional): Extra opts passed to target strategy
--- ctx.eval_fn   (optional): Custom evaluation function (for evaluator="custom")

local search_mod = require("optimize.search")
local eval_mod   = require("optimize.eval")
local stop_mod   = require("optimize.stop")

math.randomseed(os.time())

local M = {}

---@type AlcMeta
M.meta = {
    name = "optimize",
    version = "0.2.0",
    description = "Modular parameter optimization orchestrator. "
        .. "Composes pluggable search strategies (UCB1, OPRO, EA, greedy), "
        .. "evaluators (evalframe, custom, LLM judge), and stopping criteria "
        .. "(variance, patience, threshold). Persists history via alc.state.",
    category = "optimization",
}

-- Re-export submodules for direct access
M.search = search_mod
M.eval   = eval_mod
M.stop   = stop_mod

--- Merge arm params into defaults using alc.tuning if available.
local function merge_params(defaults, arm_params)
    if defaults and type(alc.tuning) == "function" then
        return alc.tuning(defaults, arm_params)
    end
    if not defaults then return arm_params end
    local merged = {}
    for k, v in pairs(defaults) do merged[k] = v end
    for k, v in pairs(arm_params) do merged[k] = v end
    return merged
end

--- Build ranking from history results.
local function build_ranking(results)
    -- Aggregate by unique param combination (using params_eq for order-independent matching)
    local arm_list = {}
    for _, r in ipairs(results) do
        local found = false
        for _, arm in ipairs(arm_list) do
            if search_mod.params_eq(arm.params, r.params) then
                arm.total = arm.total + r.score
                arm.n = arm.n + 1
                found = true
                break
            end
        end
        if not found then
            arm_list[#arm_list + 1] = { params = r.params, total = r.score, n = 1 }
        end
    end
    -- Compute averages and sort
    local rankings = {}
    for _, arm in ipairs(arm_list) do
        if arm.n > 0 then
            rankings[#rankings + 1] = {
                params = arm.params,
                avg_score = arm.total / arm.n,
                pulls = arm.n,
            }
        end
    end
    table.sort(rankings, function(a, b) return a.avg_score > b.avg_score end)
    return rankings
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local target = ctx.target or error("ctx.target is required")
    local space = ctx.space or error("ctx.space is required")
    local scenario = ctx.scenario or error("ctx.scenario is required")
    local max_rounds = ctx.rounds or 20
    local run_name = ctx.name or target
    local defaults = ctx.defaults
    local strategy_opts = ctx.strategy_opts

    -- Resolve pluggable components
    local searcher = search_mod.resolve(ctx.search or "ucb")
    local evaluator = eval_mod.resolve(ctx.evaluator)
    local stopper = stop_mod.resolve(ctx.stop)
    local stop_config = ctx.stop_config or {}

    -- Load or initialize persistent history
    local history_key = "optimize_" .. run_name
    local history = alc.state.get(history_key) or { results = {} }

    -- Initialize search state from history
    local search_state = searcher.init(space, history)

    alc.log("info", string.format(
        "optimize: starting '%s' — search=%s, evaluator=%s, max %d rounds, %d prior results",
        run_name,
        type(ctx.search) == "string" and ctx.search or "ucb",
        type(ctx.evaluator) == "string" and ctx.evaluator or "evalframe",
        max_rounds, #history.results))

    local rounds_used = 0
    local stop_reason = nil

    for round = 1, max_rounds do
        rounds_used = round

        -- 1. Propose: search strategy proposes next candidate
        local params = searcher.propose(search_state)
        local merged = merge_params(defaults, params)

        alc.log("info", string.format(
            "optimize: round %d/%d — params: %s",
            round, max_rounds, alc.json_encode(params)))

        -- 2. Evaluate: evaluator scores the candidate
        local eval_result = evaluator.evaluate(target, merged, scenario, {
            strategy_opts = strategy_opts,
            eval_fn = ctx.eval_fn,
        })
        local score = eval_result.mean

        -- 3. Update: feed result back to search strategy
        search_state = searcher.update(search_state, params, score)

        -- 4. Record: persist result
        history.results[#history.results + 1] = {
            round = #history.results + 1,
            params = params,
            score = score,
            std = eval_result.std,
            n = eval_result.n,
            failures = eval_result.failures,
        }
        alc.state.set(history_key, history)

        alc.log("info", string.format(
            "optimize: round %d score=%.4f (std=%.4f, n=%d)",
            round, score, eval_result.std, eval_result.n))

        -- 5. Stop: check stopping criterion
        local stopped, reason = stopper.should_stop(history, stop_config)
        if stopped then
            stop_reason = reason
            alc.log("info", "optimize: stopped — " .. reason)
            break
        end
    end

    -- Build results
    local rankings = build_ranking(history.results)
    local best = rankings[1] or { params = {}, avg_score = 0, pulls = 0 }

    ctx.result = {
        status = stop_reason and "converged" or "budget_exhausted",
        stop_reason = stop_reason,
        best_params = best.params,
        best_score = best.avg_score,
        rounds_used = rounds_used,
        total_evaluations = #history.results,
        arm_count = #rankings,
        top_5 = {},
        history_key = history_key,
    }
    for i = 1, math.min(5, #rankings) do
        ctx.result.top_5[i] = rankings[i]
    end

    return ctx
end

return M
