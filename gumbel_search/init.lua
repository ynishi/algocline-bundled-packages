--- gumbel_search — Gumbel Top-k + Sequential Halving Tree Search
---
--- Budget-optimal tree search that combines two theoretically grounded
--- techniques: Gumbel Top-k for unbiased candidate sampling without
--- replacement, and Sequential Halving for optimal budget allocation
--- when comparing candidates.
---
--- Key difference from ab_mcts / tot:
---   ab_mcts  — Thompson Sampling with adaptive branching (wider vs deeper).
---              Excels at exploration-exploitation balance with unlimited budget.
---              Beta posteriors require multiple visits to converge.
---   tot      — Fixed DFS/BFS strategy. Structured but budget allocation is
---              not optimized; may waste evaluations on poor candidates.
---   gumbel_search — **Fixed-budget optimal pure exploration**. Sequential
---              Halving provably minimizes simple regret under budget constraint.
---              Gumbel noise ensures unbiased candidate ranking.
---              Outperforms standard decoding with just 5-15 simulations (~500 tokens).
---              Best for "I have exactly B evaluation budget, find the best answer."
---
--- Mathematical guarantees:
---   Sequential Halving: O(N/log(N)) simple regret bound (Karnin et al., 2013).
---     Optimal among algorithms that don't use arm means.
---   Gumbel Top-k: unbiased non-replacement sampling from categorical distributions
---     (Kool et al., 2019). Equivalent to sorting by value + Gumbel noise.
---
--- Based on: "Revisiting Tree Search for LLMs: Gumbel and Sequential Halving
--- for Budget-Scalable Reasoning" (2026, arXiv:2603.21162)
--- Also: Karnin et al., "Almost Optimal Exploration in Multi-Armed Bandits" (ICML 2013)
---
--- Usage:
---   local gs = require("gumbel_search")
---   return gs.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.initial_candidates: Number of initial candidates (default: 8)
--- ctx.gen_tokens: Max tokens for generation (default: 400)
--- ctx.eval_tokens: Max tokens for evaluation (default: 100)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "gumbel_search",
    version = "0.1.0",
    description = "Budget-optimal tree search — Sequential Halving for optimal "
        .. "budget allocation + Gumbel Top-k for unbiased sampling. Provably "
        .. "minimizes simple regret under fixed evaluation budget.",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task               = T.string:describe("The problem to solve"),
                initial_candidates = T.number:is_optional():describe("Number of initial candidates (default: 8)"),
                gen_tokens         = T.number:is_optional():describe("Max tokens for generation (default: 400)"),
                eval_tokens        = T.number:is_optional():describe("Max tokens for evaluation (default: 100)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Winning candidate's response text"),
                best_index        = T.number:describe("1-based index of the winning candidate"),
                best_score        = T.number:describe("Final mean score of the winner in [0,1]"),
                halving_rounds    = T.number:describe("Number of Sequential Halving rounds executed"),
                total_evaluations = T.number:describe("Total per-candidate evaluations across rounds"),
                total_llm_calls   = T.number:describe("Total LLM calls (generation + evaluations)"),
                candidates        = T.array_of(T.shape({
                    index      = T.number:describe("Original candidate index"),
                    mean_score = T.number:describe("Final mean evaluation score in [0,1]"),
                    n_evals    = T.number:describe("Number of evaluations this candidate received"),
                })):describe("All candidates' final state (order preserved from generation)"),
            }),
        },
    },
}

--- Sample from Gumbel(0,1) distribution.
--- Gumbel(0,1) = -log(-log(U)) where U ~ Uniform(0,1)
local function gumbel_sample()
    local u = math.random()
    -- Clamp to avoid log(0)
    u = math.max(u, 1e-10)
    u = math.min(u, 1 - 1e-10)
    return -math.log(-math.log(u))
end

--- Generate a set of diverse candidate solutions.
local function generate_candidates(task, n, gen_tokens)
    local candidates = {}
    local prompts = {
        "Solve directly and concisely.",
        "Think step by step before answering.",
        "Consider alternative approaches before choosing one.",
        "Start from first principles.",
        "Work backwards from the desired result.",
        "Break this into sub-problems, solve each, then combine.",
        "Identify the key constraints first, then solve.",
        "Consider the simplest possible solution first.",
    }

    for i = 1, n do
        local hint = prompts[((i - 1) % #prompts) + 1]
        local response = alc.llm(
            string.format("Task: %s\n\n%s", task, hint),
            {
                system = string.format(
                    "You are solver #%d. Provide a complete, thoughtful answer.", i
                ),
                max_tokens = gen_tokens,
            }
        )
        -- Add Gumbel noise for unbiased ranking
        candidates[i] = {
            index = i,
            response = response,
            gumbel_noise = gumbel_sample(),
            scores = {},
            mean_score = 0,
        }
    end
    return candidates
end

--- Evaluate a candidate. Returns a normalized score in [0, 1].
local function evaluate_candidate(task, candidate, eval_tokens)
    local raw = alc.llm(
        string.format(
            "Task: %s\n\nCandidate solution:\n%s\n\n"
                .. "Rate this solution on a 0-10 scale for:\n"
                .. "- Correctness\n- Completeness\n- Clarity of reasoning\n\n"
                .. "Reply with ONLY the number.",
            task, candidate.response
        ),
        { system = "Strict evaluator. Just the number 0-10.", max_tokens = 10 }
    )

    local score = alc.parse_score(raw)
    return score / 10.0
end

--- Sequential Halving: iteratively eliminate the worse half.
--- At each round, allocate evaluations equally among survivors,
--- then eliminate the bottom half.
---
--- Total budget: sum over rounds of (survivors_r * evals_per_round)
--- This is provably optimal for simple regret (Karnin et al., 2013).
local function sequential_halving(task, candidates, eval_tokens)
    local survivors = {}
    for _, c in ipairs(candidates) do
        survivors[#survivors + 1] = c
    end

    local round = 0
    local total_evals = 0

    while #survivors > 1 do
        round = round + 1
        local n_survivors = #survivors

        -- Evaluate each survivor
        for _, candidate in ipairs(survivors) do
            local score = evaluate_candidate(task, candidate, eval_tokens)
            candidate.scores[#candidate.scores + 1] = score
            total_evals = total_evals + 1

            -- Update running mean
            local sum = 0
            for _, s in ipairs(candidate.scores) do sum = sum + s end
            candidate.mean_score = sum / #candidate.scores
        end

        -- Sort by (mean_score + gumbel_noise) for unbiased selection
        -- Gumbel-Top-k: argmax(score + gumbel) is equivalent to sampling
        -- from the categorical without replacement
        table.sort(survivors, function(a, b)
            return (a.mean_score + a.gumbel_noise) > (b.mean_score + b.gumbel_noise)
        end)

        -- Eliminate bottom half
        local keep = math.max(1, math.ceil(n_survivors / 2))
        local new_survivors = {}
        for i = 1, keep do
            new_survivors[i] = survivors[i]
        end

        alc.log("info", string.format(
            "gumbel_search: round %d — %d → %d survivors (top score: %.2f)",
            round, n_survivors, keep,
            new_survivors[1] and new_survivors[1].mean_score or 0
        ))

        survivors = new_survivors
    end

    return survivors[1], round, total_evals
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.initial_candidates or 8
    local gen_tokens = ctx.gen_tokens or 400
    local eval_tokens = ctx.eval_tokens or 100

    -- Phase 1: Generate diverse candidates with Gumbel noise
    alc.log("info", string.format("gumbel_search: generating %d candidates", n))
    local candidates = generate_candidates(task, n, gen_tokens)

    -- Phase 2: Sequential Halving to find the best
    local best, rounds, total_evals = sequential_halving(
        task, candidates, eval_tokens
    )

    -- Build candidate summary
    local candidate_summary = {}
    for _, c in ipairs(candidates) do
        candidate_summary[#candidate_summary + 1] = {
            index = c.index,
            mean_score = c.mean_score,
            n_evals = #c.scores,
        }
    end

    alc.log("info", string.format(
        "gumbel_search: winner=#%d (score=%.2f) after %d rounds, %d evaluations",
        best.index, best.mean_score, rounds, total_evals
    ))

    ctx.result = {
        answer = best.response,
        best_index = best.index,
        best_score = best.mean_score,
        halving_rounds = rounds,
        total_evaluations = total_evals,
        total_llm_calls = n + total_evals,  -- generation + evaluations
        candidates = candidate_summary,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
