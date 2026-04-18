--- mbr_select — Minimum Bayes Risk Selection
---
--- Selects the candidate that minimizes expected loss across all other
--- candidates. Instead of picking "the best" directly (which requires an
--- absolute quality oracle), MBR picks the candidate most agreed-upon by
--- all others — the one with minimum expected risk.
---
--- Key difference from rank:
---   rank       — single-elimination tournament with pairwise LLM-as-Judge.
---                O(N log N) comparisons. Subject to bracket luck: a strong
---                candidate can be eliminated by a flawed matchup.
---                Position bias in A/B comparisons affects results.
---   mbr_select — computes pairwise similarity for ALL pairs, selects the
---                candidate with highest total agreement. O(N²/2) comparisons
---                (symmetric). No bracket luck. Mathematically optimal under
---                Bayes decision theory.
---
--- Mathematical foundation:
---   MBR selects: argmin_y E_{y'~P}[L(y, y')]
---   where L is a loss function (1 - similarity).
---   Equivalently: argmax_y E_{y'~P}[similarity(y, y')]
---   This is the Bayes-optimal decision under the candidate distribution.
---
--- Based on: "Regularized Best-of-N Sampling with Minimum Bayes Risk"
--- (NAACL 2025). Also: MBR decoding literature (Eikema & Aziz, 2020)
---
--- Usage:
---   local mbr = require("mbr_select")
---   return mbr.run(ctx)
---
--- ctx.task (required): The task to generate candidates for
--- ctx.n: Number of candidates to generate (default: 5)
--- ctx.criteria: Similarity criteria (default: "substantive agreement")
--- ctx.gen_tokens: Max tokens per candidate (default: 400)
--- ctx.sim_tokens: Max tokens per similarity judgment (default: 80)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "mbr_select",
    version = "0.1.0",
    description = "Minimum Bayes Risk selection — picks the candidate with "
        .. "highest expected agreement across all others. Bayes-optimal "
        .. "selection without bracket luck or position bias.",
    category = "selection",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("The task to generate candidates for"),
                n          = T.number:is_optional():describe("Number of candidates to generate (default: 5)"),
                criteria   = T.string:is_optional():describe("Similarity criteria (default: substantive agreement)"),
                gen_tokens = T.number:is_optional():describe("Max tokens per candidate (default: 400)"),
                sim_tokens = T.number:is_optional():describe("Max tokens per similarity judgment (default: 80)"),
            }),
            result = T.shape({
                best              = T.string:describe("Text of the MBR-selected candidate"),
                best_index        = T.number:describe("1-based index of the selected candidate"),
                best_mbr_score    = T.number:describe("Expected similarity score (0-1) of the winner"),
                ranking           = T.array_of(T.shape({
                    index     = T.number,
                    mbr_score = T.number,
                })):describe("All candidates sorted by MBR score descending"),
                candidates        = T.array_of(T.string):describe("All generated candidate texts"),
                similarity_matrix = T.array_of(T.array_of(T.number)):describe("Symmetric N×N pairwise similarity matrix (values in [0, 1])"),
                total_llm_calls   = T.number:describe("Generation calls (N) + pairwise similarity calls (N(N-1)/2)"),
            }),
        },
    },
}

--- Compute pairwise similarity score between two candidates.
--- Returns a score in [0, 1].
local function compute_similarity(task, a, b, criteria, sim_tokens)
    local raw = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Response A:\n%s\n\n"
                .. "Response B:\n%s\n\n"
                .. "Rate the similarity of these two responses on a 0-10 scale.\n"
                .. "Criteria: %s\n"
                .. "10 = identical in substance, 0 = completely different.\n"
                .. "Reply with ONLY the number.",
            task, a, b, criteria
        ),
        {
            system = "Rate substantive similarity (not surface wording). "
                .. "Focus on whether they reach the same conclusions via "
                .. "compatible reasoning. Just the number.",
            max_tokens = sim_tokens,
        }
    )

    local score = alc.parse_score(raw)
    return score / 10.0
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n or 5
    local criteria = ctx.criteria or "substantive agreement on conclusions and reasoning"
    local gen_tokens = ctx.gen_tokens or 400
    local sim_tokens = ctx.sim_tokens or 80

    -- Phase 1: Generate N candidate responses
    local candidates = {}
    for i = 1, n do
        candidates[i] = alc.llm(
            string.format("Task: %s\n\nProvide your best response.", task),
            {
                system = string.format(
                    "You are expert #%d. Give a thorough, high-quality response.", i
                ),
                max_tokens = gen_tokens,
            }
        )
    end

    alc.log("info", string.format("mbr_select: %d candidates generated", n))

    -- Phase 2: Compute pairwise similarity matrix (upper triangle only; symmetric)
    -- sim[i][j] = similarity(candidate_i, candidate_j)
    local sim = {}
    for i = 1, n do
        sim[i] = {}
        sim[i][i] = 1.0  -- self-similarity = 1
    end

    local pair_count = 0
    for i = 1, n do
        for j = i + 1, n do
            local s = compute_similarity(
                task, candidates[i], candidates[j], criteria, sim_tokens
            )
            sim[i][j] = s
            sim[j][i] = s  -- symmetric
            pair_count = pair_count + 1
        end
    end

    alc.log("info", string.format(
        "mbr_select: %d pairwise similarities computed", pair_count
    ))

    -- Phase 3: Compute expected similarity (MBR utility) for each candidate
    -- MBR score(i) = (1/N) * sum_j similarity(i, j)
    local mbr_scores = {}
    local best_idx = 1
    local best_score = -1

    for i = 1, n do
        local total = 0
        for j = 1, n do
            total = total + sim[i][j]
        end
        mbr_scores[i] = total / n

        if mbr_scores[i] > best_score then
            best_score = mbr_scores[i]
            best_idx = i
        end
    end

    -- Build score ranking
    local ranking = {}
    for i = 1, n do
        ranking[i] = { index = i, mbr_score = mbr_scores[i] }
    end
    table.sort(ranking, function(a, b) return a.mbr_score > b.mbr_score end)

    alc.log("info", string.format(
        "mbr_select: winner=#%d (MBR score=%.3f)", best_idx, best_score
    ))

    ctx.result = {
        best = candidates[best_idx],
        best_index = best_idx,
        best_mbr_score = best_score,
        ranking = ranking,
        candidates = candidates,
        similarity_matrix = sim,
        total_llm_calls = n + pair_count,  -- generation + pairwise comparisons
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
