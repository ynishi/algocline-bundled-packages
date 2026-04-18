--- ab_select — Adaptive Branching Selection (multi-fidelity Thompson sampling)
---
--- Selects the best candidate from a pool using staged evaluators of
--- increasing cost. Thompson Sampling decides which candidate receives the
--- next, more expensive evaluation, allocating expensive evaluations only
--- to candidates whose Beta posterior suggests they are promising.
---
--- Key difference from ab_mcts / gumbel_search / mbr_select:
---   ab_mcts        — builds reasoning paths in a TREE; uses LLM both to
---                    generate new nodes AND evaluate them. 2*B+1 LLM calls.
---                    Answers "what is a good reasoning path?".
---   gumbel_search  — fixed flat pool, SINGLE evaluator, Sequential Halving
---                    for budget allocation. Cannot exploit cheap-vs-expensive
---                    evaluator structure.
---   mbr_select     — fixed flat pool, pairwise similarity, no budget allocation.
---   ab_select      — fixed flat pool with MULTI-FIDELITY evaluator cascade
---                    (cheap → expensive). Thompson Sampling allocates the
---                    expensive evaluator only to candidates worth the cost.
---                    Multi-fidelity is the unique axis vs every other
---                    selection package in this repository.
---
--- Algorithm (AB-MCTS adapted to fixed pool, no GEN node, no kill):
---   1. Generate N candidate answers from ctx.task.
---   2. Initialize Beta(α₀, β₀) per candidate.
---   3. While budget remains and at least one candidate has an unevaluated
---      level affordable under remaining budget:
---        a. Sample θᵢ ~ Beta(αᵢ, βᵢ) for each affordable candidate.
---        b. Pick i* = argmax θᵢ.
---        c. Evaluate i* at its lowest unevaluated fidelity level.
---        d. s = score / score_hi normalized into [0, 1]
---        e. αᵢ ← αᵢ + s ;  βᵢ ← βᵢ + (1 - s)
---   4. Rank by posterior mean αᵢ / (αᵢ + βᵢ); return best.
---
--- Note on pruning: there is NO mid-flight kill. Thompson Sampling naturally
--- starves candidates with low posteriors by reducing the probability they
--- are picked at the next iteration. AB-MCTS (Inoue et al.) does not include
--- a kill mechanism, and our calibration analysis shows that any fixed
--- credible-bound threshold is depth-dependent and statistically unsound.
--- See pairwise_rank / listwise_rank / setwise_rank for theory-backed
--- pruning when calibration of absolute scores cannot be assumed.
---
--- Based on: Inoue et al., "Wider or Deeper? Scaling LLM Inference-Time
---   Compute with Adaptive Branching Tree Search"
---   (NeurIPS 2025 Spotlight, arXiv:2503.04412)
---
--- Usage:
---   local ab_select = require("ab_select")
---   return ab_select.run(ctx)
---
--- ctx.task (required): The problem to generate and select an answer for
--- ctx.n: Number of initial candidates (default: 6)
--- ctx.budget: Total fidelity-cost budget for evaluation (default: 18)
--- ctx.alpha_prior: Beta prior alpha (default: 1.0)
--- ctx.beta_prior:  Beta prior beta (default: 1.0)
--- ctx.score_hi: Maximum raw score (default: 10) — used to normalize to [0,1]
--- ctx.gen_tokens: Max tokens per candidate generation (default: 400)
--- ctx.fidelities: Override the evaluator ladder (each entry =
---     { name, cost, prompt, max_tokens }). Defaults to a 3-level
---     quick/detail/thorough ladder.
--- ctx.seed: PRNG seed for Thompson sampling (default: 1)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "ab_select",
    version = "0.1.0",
    description = "Adaptive Branching Selection — multi-fidelity Thompson "
        .. "sampling over a fixed candidate pool. Allocates expensive "
        .. "evaluators only to promising candidates. Unique multi-fidelity "
        .. "axis vs other selection packages.",
    category = "selection",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task        = T.string:describe("The problem to generate and select an answer for"),
                n           = T.number:is_optional():describe("Number of initial candidates (default: 6)"),
                budget      = T.number:is_optional():describe("Total fidelity-cost budget (default: 18)"),
                alpha_prior = T.number:is_optional():describe("Beta prior α (default: 1.0)"),
                beta_prior  = T.number:is_optional():describe("Beta prior β (default: 1.0)"),
                score_hi    = T.number:is_optional():describe("Maximum raw score for normalization (default: 10)"),
                gen_tokens  = T.number:is_optional():describe("Max tokens per candidate generation (default: 400)"),
                fidelities  = T.array_of(T.shape({
                    name       = T.string,
                    cost       = T.number,
                    prompt     = T.string,
                    max_tokens = T.number,
                })):is_optional():describe("Override the evaluator ladder (default: 3-level quick/detail/thorough)"),
                seed        = T.number:is_optional():describe("PRNG seed for Thompson sampling (default: 1)"),
            }),
            result = T.shape({
                best            = T.string:describe("Text of the winning candidate"),
                best_index      = T.number:describe("1-based index of the winner"),
                best_score      = T.number:describe("Posterior mean of the winner"),
                ranking         = T.array_of(T.shape({
                    index          = T.number,
                    posterior_mean = T.number,
                    alpha          = T.number,
                    beta           = T.number,
                    evaluations    = T.table:describe("Sparse map level(number) -> raw score"),
                    n_evals        = T.number,
                })):describe("All candidates sorted by posterior mean descending"),
                candidates      = T.array_of(T.string):describe("All generated candidate texts"),
                rounds          = T.array_of(T.shape({
                    iteration   = T.number,
                    candidate   = T.number,
                    level       = T.number,
                    level_name  = T.string,
                    score       = T.number,
                    score_norm  = T.number,
                    alpha       = T.number,
                    beta        = T.number,
                    theta_pick  = T.number,
                    cost        = T.number,
                    budget_used = T.number,
                })):describe("Per-iteration Thompson sampling trace"),
                budget_used     = T.number:describe("Total fidelity cost consumed"),
                budget          = T.number:describe("Total fidelity-cost budget supplied"),
                total_llm_calls = T.number:describe("Generation calls + evaluation calls"),
            }),
        },
    },
}

-- ─── Deterministic xorshift32 PRNG ───
-- Self-contained so test runs are reproducible without depending on
-- math.random global state.

local function make_rng(seed)
    local state = seed or 1
    if state == 0 then state = 1 end
    return function()
        state = state ~ ((state << 13) & 0xFFFFFFFF)
        state = state ~ (state >> 17)
        state = state ~ ((state << 5) & 0xFFFFFFFF)
        state = state & 0xFFFFFFFF
        return state / 0x100000000
    end
end

-- ─── Beta sampling via Marsaglia-Tsang Gamma ratio ───

local function normal(rng)
    local u1 = rng()
    local u2 = rng()
    if u1 < 1e-12 then u1 = 1e-12 end
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function gamma_ge1(rng, shape)
    local d = shape - 1.0 / 3.0
    local c = 1.0 / math.sqrt(9.0 * d)
    while true do
        local x, v
        repeat
            x = normal(rng)
            v = 1 + c * x
        until v > 0
        v = v * v * v
        local u = rng()
        if u < 1 - 0.0331 * x * x * x * x then
            return d * v
        end
        if math.log(math.max(u, 1e-12)) < 0.5 * x * x + d * (1 - v + math.log(v)) then
            return d * v
        end
    end
end

local function gamma_sample(rng, shape)
    if shape < 1 then
        local g = gamma_ge1(rng, shape + 1)
        local u = rng()
        if u < 1e-12 then u = 1e-12 end
        return g * u ^ (1 / shape)
    end
    return gamma_ge1(rng, shape)
end

local function beta_sample(rng, alpha, beta)
    if alpha <= 0 then alpha = 0.01 end
    if beta <= 0 then beta = 0.01 end
    local x = gamma_sample(rng, alpha)
    local y = gamma_sample(rng, beta)
    local s = x + y
    if s <= 0 then return 0.5 end
    return x / s
end

-- ─── Default fidelity ladder ───
-- Three stages of evaluation depth. Cost is the number of "budget units"
-- charged per call (relative; the same LLM API is used at every level).

local DEFAULT_FIDELITIES = {
    {
        name = "quick",
        cost = 1,
        prompt = "Task: %s\n\nCandidate answer:\n%s\n\n"
            .. "Quick assessment: rate this answer 0-10 in one judgment. "
            .. "Reply with ONLY the number.",
        max_tokens = 10,
    },
    {
        name = "detail",
        cost = 2,
        prompt = "Task: %s\n\nCandidate answer:\n%s\n\n"
            .. "Detailed assessment on three axes (correctness, completeness, "
            .. "clarity). Each axis 0-10. Then output the AVERAGE on the last "
            .. "line as 'FINAL: <number>'. Reply with the analysis followed "
            .. "by the FINAL line.",
        max_tokens = 200,
    },
    {
        name = "thorough",
        cost = 4,
        prompt = "Task: %s\n\nCandidate answer:\n%s\n\n"
            .. "Thorough evaluation. Identify the strongest point, the weakest "
            .. "point, any factual or logical errors, and the overall quality "
            .. "0-10. End with 'FINAL: <number>' on the last line.",
        max_tokens = 400,
    },
}

--- Parse a score from an LLM response. Looks for the last 'FINAL: <num>'
--- pattern (used by detail/thorough levels), then falls back to
--- alc.parse_score (used by quick level which only emits a bare number).
--- Errors on total parse failure — silent zero would systematically starve
--- the candidate via the Bayesian update and corrupt Thompson sampling.
--- Matches the strict policy of pairwise_rank / setwise_rank.
local function parse_eval_score(raw)
    local m = raw:match("FINAL:%s*([%-%d%.]+)[^%d]*$")
    if m then
        local n = tonumber(m)
        if n then return n end
    end
    local n = alc.parse_score(raw)
    if n then return n end
    error(
        "ab_select: cannot parse score from LLM response: "
            .. tostring(raw):sub(1, 200),
        2
    )
end

--- Index of the lowest unevaluated fidelity level for candidate i.
--- Returns nil if all levels evaluated.
local function next_level(evals_i, n_levels)
    for lv = 1, n_levels do
        if evals_i[lv] == nil then return lv end
    end
    return nil
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n or 6
    local budget = ctx.budget or 18
    local alpha_prior = ctx.alpha_prior or 1.0
    local beta_prior = ctx.beta_prior or 1.0
    local score_hi = ctx.score_hi or 10
    local gen_tokens = ctx.gen_tokens or 400
    local fidelities = ctx.fidelities or DEFAULT_FIDELITIES
    local n_levels = #fidelities
    local seed = ctx.seed or 1

    if n < 2 then error("ab_select: ctx.n must be >= 2", 2) end
    if type(seed) ~= "number" or seed ~= math.floor(seed) or seed < 0 then
        error("ab_select: ctx.seed must be a non-negative integer", 2)
    end
    if budget < fidelities[1].cost then
        error("ab_select: budget too small for even one level-1 evaluation", 2)
    end

    local rng = make_rng(seed)

    -- ── Phase 1: Generate N candidates ──
    local candidates = {}
    for i = 1, n do
        candidates[i] = alc.llm(
            string.format(
                "Task: %s\n\nProvide your best answer. Be specific and complete.",
                task
            ),
            {
                system = string.format(
                    "You are expert #%d. Give a thorough answer that may "
                        .. "differ in approach from others.", i
                ),
                max_tokens = gen_tokens,
            }
        )
    end

    alc.log("info", string.format("ab_select: generated %d candidates", n))

    -- ── Phase 2: Multi-fidelity Thompson sampling ──
    local alpha = {}
    local beta  = {}
    local evals = {}    -- evals[i][level] = raw score
    for i = 1, n do
        alpha[i] = alpha_prior
        beta[i]  = beta_prior
        evals[i] = {}
    end

    local budget_used = 0
    local iteration = 0
    local evals_done = 0
    local rounds = {}

    while true do
        iteration = iteration + 1

        -- Find affordable, unfinished candidates
        local choices = {}
        for i = 1, n do
            local nl = next_level(evals[i], n_levels)
            if nl ~= nil then
                local cost = fidelities[nl].cost
                if budget_used + cost <= budget then
                    choices[#choices + 1] = { i = i, level = nl, cost = cost }
                end
            end
        end
        if #choices == 0 then break end

        -- Thompson sample
        for _, ch in ipairs(choices) do
            ch.theta = beta_sample(rng, alpha[ch.i], beta[ch.i])
        end
        table.sort(choices, function(a, b) return a.theta > b.theta end)
        local pick = choices[1]
        local i = pick.i
        local level = pick.level
        local cfg = fidelities[level]

        -- Evaluate
        local raw = alc.llm(
            string.format(cfg.prompt, task, candidates[i]),
            {
                system = "You are a rigorous evaluator. Be precise.",
                max_tokens = cfg.max_tokens,
            }
        )
        local score = parse_eval_score(raw)
        evals[i][level] = score
        budget_used = budget_used + cfg.cost
        evals_done = evals_done + 1

        -- Bayesian update
        local s = score / score_hi
        if s < 0 then s = 0 end
        if s > 1 then s = 1 end
        alpha[i] = alpha[i] + s
        beta[i]  = beta[i]  + (1 - s)

        rounds[#rounds + 1] = {
            iteration = iteration,
            candidate = i,
            level = level,
            level_name = cfg.name,
            score = score,
            score_norm = s,
            alpha = alpha[i],
            beta = beta[i],
            theta_pick = pick.theta,
            cost = cfg.cost,
            budget_used = budget_used,
        }

        alc.log("info", string.format(
            "ab_select: iter %d — cand #%d at %s, score=%.2f (α=%.2f β=%.2f)",
            iteration, i, cfg.name, score, alpha[i], beta[i]
        ))
    end

    -- ── Phase 3: Rank by posterior mean ──
    local ranking = {}
    for i = 1, n do
        ranking[i] = {
            index = i,
            posterior_mean = alpha[i] / (alpha[i] + beta[i]),
            alpha = alpha[i],
            beta = beta[i],
            evaluations = evals[i],
            n_evals = 0,
        }
        for _ in pairs(evals[i]) do
            ranking[i].n_evals = ranking[i].n_evals + 1
        end
    end
    table.sort(ranking, function(a, b)
        return a.posterior_mean > b.posterior_mean
    end)

    local best = ranking[1]

    alc.log("info", string.format(
        "ab_select: winner=#%d (posterior_mean=%.3f, %d evals) "
            .. "budget_used=%d/%d",
        best.index, best.posterior_mean, best.n_evals, budget_used, budget
    ))

    ctx.result = {
        best = candidates[best.index],
        best_index = best.index,
        best_score = best.posterior_mean,
        ranking = ranking,
        candidates = candidates,
        rounds = rounds,
        budget_used = budget_used,
        budget = budget,
        total_llm_calls = n + evals_done,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
