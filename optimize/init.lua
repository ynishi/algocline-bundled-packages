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
--- ctx.auto_card (optional): Emit a Card on completion (default: false)
--- ctx.card_pkg  (optional): Card pkg.name override (default: "optimize_{target}")

local search_mod = require("optimize.search")
local eval_mod   = require("optimize.eval")
local stop_mod   = require("optimize.stop")
local S          = require("alc_shapes")
local T          = S.T

math.randomseed(os.time())

local M = {}

---@type AlcMeta
M.meta = {
    name = "optimize",
    version = "0.3.0",
    description = "Modular parameter optimization orchestrator. "
        .. "Composes pluggable search strategies (UCB1, OPRO, EA, greedy), "
        .. "evaluators (evalframe, custom, LLM judge), and stopping criteria "
        .. "(variance, patience, threshold). Persists history via alc.state.",
    category = "optimization",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                target         = T.string:describe("Strategy package name to optimize (e.g., 'biz_kernel')"),
                space          = T.table:describe("Parameter search space (map of param_name → def {type, min, max, step, values})"),
                scenario       = T.any:describe("Eval scenario — inline table or scenario name string"),
                rounds         = T.number:is_optional():describe("Max optimization rounds (default: 20)"),
                search         = T.any:is_optional():describe("Search strategy — name string or config table (default: 'ucb')"),
                evaluator      = T.any:is_optional():describe("Evaluator — name string or config table (default: 'evalframe')"),
                stop           = T.any:is_optional():describe("Stopping criterion — name string or config table (default: 'variance')"),
                stop_config    = T.table:is_optional():describe("Extra config for stopping criterion"),
                name           = T.string:is_optional():describe("Run name used as state key suffix (default: ctx.target)"),
                defaults       = T.table:is_optional():describe("Base parameter defaults merged with arm params"),
                strategy_opts  = T.table:is_optional():describe("Extra opts passed through to the target strategy"),
                eval_fn        = T.any:is_optional():describe("Custom evaluation function (only for evaluator='custom')"),
                auto_card      = T.boolean:is_optional():describe("Emit a Card on completion (default: false)"),
                card_pkg       = T.string:is_optional():describe("Card pkg.name override (default: 'optimize_{target}')"),
                scenario_name  = T.string:is_optional():describe("Explicit scenario name for the emitted Card"),
            }),
            result = T.shape({
                status            = T.string:describe("'converged' (stopper fired) or 'budget_exhausted'"),
                stop_reason       = T.string:is_optional():describe("Stopper's reason string; nil when budget_exhausted"),
                best_params       = T.table:describe("Best-ranked parameter set"),
                best_score        = T.number:describe("Average score of best_params"),
                rounds_used       = T.number:describe("Actual rounds executed this run"),
                total_evaluations = T.number:describe("Cumulative evaluations in history (including prior runs)"),
                arm_count         = T.number:describe("Number of distinct arms in history"),
                top_5             = T.array_of(T.shape({
                    params    = T.table:describe("Arm parameter set"),
                    avg_score = T.number:describe("Arm's average score"),
                    pulls     = T.number:describe("Arm's total pull count"),
                })):describe("Top-5 ranked arms (may contain fewer than 5)"),
                history_key       = T.string:describe("alc.state key for the persisted history"),
                card_id           = T.string:is_optional():describe("Emitted Card id (only when auto_card=true)"),
            }),
        },
    },
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

--- Emit a Card from optimize results (Two-Tier Content Policy).
--- Tier 1 (Card body): aggregate scalars, optimize config, top_k ranking.
--- Tier 2 (samples.jsonl): per-round history (one row per round).
local function emit_card(ctx, result, history)
    local pkg_name = ctx.card_pkg or ("optimize_" .. (ctx.name or ctx.target))
    local search_name = type(ctx.search) == "string" and ctx.search or "ucb"
    local eval_name = type(ctx.evaluator) == "string" and ctx.evaluator or "evalframe"
    local stop_name = type(ctx.stop) == "string" and ctx.stop or "variance"

    local top_k = {}
    for i, arm in ipairs(result.top_5) do
        top_k[i] = {
            rank = i,
            avg_score = arm.avg_score,
            pulls = arm.pulls,
            params = arm.params,
        }
    end

    local card = alc.card.create({
        pkg = { name = pkg_name },
        scenario = { name = ctx.scenario_name
            or (type(ctx.scenario) == "string" and ctx.scenario)
            or (type(ctx.scenario) == "table" and ctx.scenario.name)
            or "unknown" },
        params = result.best_params,
        stats = { best_score = result.best_score },
        optimize = {
            target = ctx.target,
            search = search_name,
            evaluator = eval_name,
            stop = stop_name,
            rounds_used = result.rounds_used,
            total_evaluations = result.total_evaluations,
            arm_count = result.arm_count,
            stop_reason = result.stop_reason,
            history_key = result.history_key,
            top_k = top_k,
        },
    })

    -- Tier 2: per-round history as samples sidecar
    if history.results and #history.results > 0 then
        alc.card.write_samples(card.card_id, history.results)
    end

    return card.card_id
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

    -- Emit Card if opted in
    if ctx.auto_card then
        local card_id = emit_card(ctx, ctx.result, history)
        ctx.result.card_id = card_id
        alc.log("info", "optimize: card emitted — " .. card_id)
    end

    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
