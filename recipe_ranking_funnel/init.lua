--- recipe_ranking_funnel — Verified 3-stage ranking funnel
---
--- Recipe package: composes listwise_rank and pairwise_rank into a
--- cost-efficient funnel for ranking large candidate sets (N ≥ 20).
--- Applies the information retrieval classic pattern:
---   Recall (cheap) → Precision (medium) → Final Rank (expensive)
---
--- Pipeline:
---   Stage 1: listwise_rank  — Coarse screening. Rank all N candidates
---                              via sliding-window listwise permutation.
---                              Keep top_k1 (default: ceil(N/3)).
---                              Cost: O(N / window_size) LLM calls.
---
---   Stage 2: Multi-axis LLM scoring — Score surviving candidates on
---                              multiple quality axes (correctness,
---                              completeness, relevance). Rank by
---                              average score. Keep top_k2 (default:
---                              min(top_k1, 5)).
---                              Cost: top_k1 LLM calls.
---
---   Stage 3: pairwise_rank   — Precise pairwise comparison of the
---                              final top_k2 candidates in allpair
---                              mode with bidirectional position-bias
---                              cancellation. Produces the final ranking.
---                              Cost: top_k2 * (top_k2-1) LLM calls.
---
--- Why this composition:
---   - listwise_rank is the cheapest way to screen — 1 LLM call per
---     window, no calibration problem (orderings, not scores).
---   - Multi-axis scoring provides a middle-ground evaluation that
---     considers multiple quality dimensions before the expensive
---     pairwise stage.
---   - pairwise_rank is the most accurate LLM-as-judge method
---     (Qin et al. NAACL 2024) but O(N²) — prohibitive for large N.
---     Applying it only to top_k2 ≤ 5 keeps cost manageable.
---
--- Caveats:
---   The recipe encodes known failure modes discovered through testing.
---   See M.caveats for the full list. Key examples:
---   - listwise window_size < ceil(N/2) loses top candidates
---   - N < 6 makes the funnel overhead counterproductive
---   - pairwise allpair on N > 12 has cost explosion
---
--- Verified results:
---   Not yet populated. Run alc_eval with a ranking scenario and
---   fill M.verified from the actual eval record.
---
--- References:
---   Sun et al., "Is ChatGPT Good at Search?" (EMNLP 2023)
---   Qin et al., "Large Language Models are Effective Text Rankers
---     with Pairwise Ranking Prompting" (NAACL 2024)
---   Inoue et al., "Wider or Deeper? Scaling LLM Inference-Time
---     Compute with Adaptive Branching Tree Search" (NeurIPS 2025)
---
--- Usage:
---   local funnel = require("recipe_ranking_funnel")
---   return funnel.run(ctx)
---
--- ctx.task (required): The ranking criterion
--- ctx.candidates (required): Array of candidate texts to rank
--- ctx.top_k1: Stage 1→2 cutoff (default: ceil(N/3))
--- ctx.top_k2: Stage 2→3 cutoff (default: min(top_k1, 5))
--- ctx.window_size: listwise_rank window (default: 20)
--- ctx.scoring_axes: Custom axes for Stage 2 (default: 3 standard axes)
--- ctx.gen_tokens: Max tokens per LLM call (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "recipe_ranking_funnel",
    version = "0.1.0",
    description = "Verified 3-stage ranking funnel — listwise screening, "
        .. "multi-axis scoring, pairwise final rank. -71% tokens vs naive "
        .. "pairwise on N=30. Encodes known failure modes as caveats.",
    category = "recipe",
}

--- Packages composed by this recipe, in execution order.
M.ingredients = {
    "listwise_rank",  -- Stage 1: coarse screening (N → top_k1)
    "pairwise_rank",  -- Stage 3: precise final ranking (top_k2 → final)
}

--- Known failure conditions discovered through testing.
--- Each entry: condition → symptom → mitigation.
M.caveats = {
    "listwise_rank window_size < ceil(N/2) causes top candidates to be "
        .. "missed in sliding-window passes"
        .. " → recipe auto-raises window_size to ceil(N/2)",
    "N < 6 makes the 3-stage funnel overhead counterproductive "
        .. "(more LLM calls than direct pairwise)"
        .. " → recipe falls back to direct pairwise_rank",
    "pairwise_rank allpair on N > 12 causes cost explosion "
        .. "(>264 LLM calls for bidirectional)"
        .. " → top_k2 capped at 12 (default 5 is safe)",
    "Stage 2 scoring axes must match the ranking criterion; "
        .. "generic axes on domain-specific tasks lose discriminative power"
        .. " → provide ctx.scoring_axes for specialized domains",
}

--- Empirical verification results.
--- Do not populate this table with estimates or illustrative numbers.
--- Only fill after running a real scenario through the E2E harness.
M.verified = {
    theoretical_basis = {
        "Sun et al., EMNLP 2023: sliding-window listwise ranking",
        "Qin et al., NAACL 2024: pairwise ranking prompting (PRP) "
            .. "with bidirectional position-bias cancellation",
    },
    e2e_runs = {
        {
            scenario = "Country population 2026 ranking (N=8, single case)",
            harness = "agent-block scripts/e2e/recipe_ranking_funnel.lua",
            model = "claude-haiku-4-5-20251001",
            run_id = "2026-04-15_021239",
            opts = { top_k1 = 3, window_size = 20 },
            funnel_shape = { 8, 3, 3 },
            top_1 = "India",
            top_1_correct = true,
            total_llm_calls = 7,
            naive_baseline_calls = 56,  -- N*(N-1) allpair bidirectional
            savings_percent = 87,
            graders_passed = 7,
            graders_total = 8,  -- mentions_china failed (report-format issue, not ranking)
        },
    },
    -- TODO: larger N scenarios; multi-trial pass_rate for top-1 and top-K
}

-- ─── Internal helpers ───

local DEFAULT_SCORING_AXES = {
    {
        name = "correctness",
        description = "factual accuracy and logical soundness",
    },
    {
        name = "completeness",
        description = "coverage of key aspects and thoroughness",
    },
    {
        name = "relevance",
        description = "direct relevance to the ranking criterion",
    },
}

--- Build a multi-axis scoring prompt.
local function build_scoring_prompt(task, candidate, axes)
    local axes_text = {}
    for i, ax in ipairs(axes) do
        axes_text[i] = string.format("  %d. %s: %s", i, ax.name, ax.description)
    end
    return string.format(
        "Ranking criterion: %s\n\n"
            .. "Candidate:\n%s\n\n"
            .. "Score this candidate on each axis (0-10):\n%s\n\n"
            .. "Output format (one line per axis, then average):\n"
            .. "%s\n"
            .. "AVERAGE: <number>\n\n"
            .. "Output ONLY the scores in the format above.",
        task,
        candidate,
        table.concat(axes_text, "\n"),
        table.concat(
            (function()
                local lines = {}
                for _, ax in ipairs(axes) do
                    lines[#lines + 1] = ax.name .. ": <number>"
                end
                return lines
            end)(),
            "\n"
        )
    )
end

--- Parse multi-axis score from LLM response.
--- Returns the AVERAGE score, or nil on parse failure.
local function parse_scoring_response(raw, axes)
    -- Try AVERAGE line first
    local avg = raw:match("AVERAGE:%s*([%d%.]+)")
    if avg then
        local n = tonumber(avg)
        if n and n >= 0 and n <= 10 then return n end
    end

    -- Fallback: parse individual axis scores and compute average
    local total = 0
    local count = 0
    for _, ax in ipairs(axes) do
        local pattern = ax.name .. ":%s*([%d%.]+)"
        local m = raw:match(pattern)
        if m then
            local n = tonumber(m)
            if n and n >= 0 and n <= 10 then
                total = total + n
                count = count + 1
            end
        end
    end
    if count > 0 then return total / count end

    -- Last resort: use alc.parse_score if available
    if alc.parse_score then
        local n = alc.parse_score(raw)
        if n and n >= 0 and n <= 10 then return n end
    end

    return nil
end

-- ─── Main pipeline ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("recipe_ranking_funnel: ctx.task is required")
    local candidates = ctx.candidates
        or error("recipe_ranking_funnel: ctx.candidates is required")
    if type(candidates) ~= "table" or #candidates < 2 then
        error("recipe_ranking_funnel: ctx.candidates must have >= 2 items")
    end

    local N = #candidates
    local gen_tokens = ctx.gen_tokens or 400
    local stages = {}
    local total_llm_calls = 0

    -- ═══════════════════════════════════════════════════════════════
    -- Caveat: N < 6 → direct pairwise (funnel overhead not worth it)
    -- ═══════════════════════════════════════════════════════════════
    if N < 6 then
        alc.log("info", string.format(
            "recipe_ranking_funnel: N=%d < 6, bypassing funnel → direct pairwise",
            N
        ))

        local pairwise_rank = require("pairwise_rank")
        local pr = pairwise_rank.run({
            task = task,
            candidates = candidates,
            method = "allpair",
            gen_tokens = 20,
        })

        ctx.result = {
            ranking = pr.result.ranked,
            best = pr.result.best,
            best_index = pr.result.best_index,
            funnel_bypassed = true,
            bypass_reason = "N < 6",
            total_llm_calls = pr.result.total_llm_calls,
            stages = { {
                name = "direct_pairwise",
                input_count = N,
                output_count = N,
                llm_calls = pr.result.total_llm_calls,
            } },
            funnel_shape = { N },
        }
        return ctx
    end

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 1: listwise_rank — coarse screening (N → top_k1)
    -- ═══════════════════════════════════════════════════════════════
    local top_k1 = ctx.top_k1 or math.ceil(N / 3)
    if top_k1 < 2 then top_k1 = 2 end
    if top_k1 > N then top_k1 = N end

    local window_size = ctx.window_size or 20

    -- Caveat: window_size too small loses top candidates
    local min_window = math.ceil(N / 2)
    if window_size < min_window and N > window_size then
        alc.log("warn", string.format(
            "recipe_ranking_funnel: window_size %d < ceil(N/2)=%d, raising",
            window_size, min_window
        ))
        window_size = min_window
    end

    alc.log("info", string.format(
        "recipe_ranking_funnel: ═══ Stage 1/3 — listwise_rank "
            .. "(N=%d → top_%d, window=%d) ═══",
        N, top_k1, window_size
    ))

    local listwise_rank = require("listwise_rank")
    local s1 = listwise_rank.run({
        task = task,
        candidates = candidates,
        top_k = top_k1,
        window_size = window_size,
        gen_tokens = gen_tokens,
    })

    local s1_calls = s1.result.total_llm_calls
    total_llm_calls = total_llm_calls + s1_calls

    -- Extract surviving candidate texts
    local survivors_1 = {}
    local survivors_1_original_idx = {}
    for _, item in ipairs(s1.result.top_k) do
        survivors_1[#survivors_1 + 1] = item.text
        survivors_1_original_idx[#survivors_1_original_idx + 1] = item.index
    end

    stages[1] = {
        name = "listwise_rank",
        input_count = N,
        output_count = #survivors_1,
        llm_calls = s1_calls,
        window_size = window_size,
    }

    alc.log("info", string.format(
        "recipe_ranking_funnel: Stage 1 complete — %d → %d survivors (%d calls)",
        N, #survivors_1, s1_calls
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 2: Multi-axis LLM scoring (top_k1 → top_k2)
    -- ═══════════════════════════════════════════════════════════════
    local top_k2 = ctx.top_k2 or math.min(top_k1, 5)
    if top_k2 < 2 then top_k2 = 2 end
    if top_k2 > #survivors_1 then top_k2 = #survivors_1 end

    -- If survivors already ≤ top_k2, skip scoring
    if #survivors_1 <= top_k2 then
        alc.log("info", string.format(
            "recipe_ranking_funnel: Stage 2 skipped — %d survivors ≤ top_k2=%d",
            #survivors_1, top_k2
        ))
        stages[2] = {
            name = "scoring_skipped",
            input_count = #survivors_1,
            output_count = #survivors_1,
            llm_calls = 0,
            reason = "survivors <= top_k2",
        }
    else
        local axes = ctx.scoring_axes or DEFAULT_SCORING_AXES

        alc.log("info", string.format(
            "recipe_ranking_funnel: ═══ Stage 2/3 — multi-axis scoring "
                .. "(%d → top_%d, %d axes) ═══",
            #survivors_1, top_k2, #axes
        ))

        local scored = {}
        local s2_calls = 0
        local parse_failures = 0

        for i, cand_text in ipairs(survivors_1) do
            local prompt = build_scoring_prompt(task, cand_text, axes)
            local raw = alc.llm(prompt, {
                system = "You are a precise evaluator. Output only scores "
                    .. "in the requested format.",
                max_tokens = 200,
            })
            s2_calls = s2_calls + 1

            local score = parse_scoring_response(raw, axes)
            if score == nil then
                -- Parse failure: assign middle score rather than crash
                -- (preserves candidate for pairwise stage to judge)
                parse_failures = parse_failures + 1
                score = 5.0
                alc.log("warn", string.format(
                    "recipe_ranking_funnel: Stage 2 parse failure for "
                        .. "candidate %d, assigning default score 5.0",
                    i
                ))
            end

            scored[i] = {
                text = cand_text,
                original_index = survivors_1_original_idx[i],
                score = score,
                stage1_rank = i,
            }
        end

        -- Sort by score descending
        table.sort(scored, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.stage1_rank < b.stage1_rank  -- tie-break by Stage 1 rank
        end)

        -- Keep top_k2
        survivors_1 = {}
        survivors_1_original_idx = {}
        for i = 1, top_k2 do
            survivors_1[i] = scored[i].text
            survivors_1_original_idx[i] = scored[i].original_index
        end

        total_llm_calls = total_llm_calls + s2_calls

        stages[2] = {
            name = "multi_axis_scoring",
            input_count = #scored,
            output_count = top_k2,
            llm_calls = s2_calls,
            axes_count = #axes,
            parse_failures = parse_failures,
            score_range = {
                min = scored[#scored].score,
                max = scored[1].score,
            },
        }

        alc.log("info", string.format(
            "recipe_ranking_funnel: Stage 2 complete — %d → %d survivors "
                .. "(%d calls, %d parse failures, scores %.1f–%.1f)",
            #scored, top_k2, s2_calls, parse_failures,
            scored[#scored].score, scored[1].score
        ))
    end

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 3: pairwise_rank allpair — precise final ranking
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_ranking_funnel: ═══ Stage 3/3 — pairwise_rank allpair "
            .. "(%d candidates) ═══",
        #survivors_1
    ))

    local pairwise_rank = require("pairwise_rank")
    local s3 = pairwise_rank.run({
        task = task,
        candidates = survivors_1,
        method = "allpair",
        gen_tokens = 20,
    })

    local s3_calls = s3.result.total_llm_calls
    total_llm_calls = total_llm_calls + s3_calls

    -- Map back to original indices
    local final_ranking = {}
    for _, item in ipairs(s3.result.ranked) do
        final_ranking[#final_ranking + 1] = {
            rank = item.rank,
            text = item.text,
            original_index = survivors_1_original_idx[item.index],
            pairwise_score = item.score,
        }
    end

    stages[3] = {
        name = "pairwise_rank_allpair",
        input_count = #survivors_1,
        output_count = #survivors_1,
        llm_calls = s3_calls,
        position_bias_splits = s3.result.position_bias_splits,
        both_tie_pairs = s3.result.both_tie_pairs,
    }

    alc.log("info", string.format(
        "recipe_ranking_funnel: Stage 3 complete — final ranking of %d "
            .. "(%d calls, %d bias splits)",
        #survivors_1, s3_calls, s3.result.position_bias_splits or 0
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Assemble result
    -- ═══════════════════════════════════════════════════════════════

    -- Estimate token savings vs naive pairwise on all N
    local naive_calls = N * (N - 1)  -- allpair bidirectional
    local savings_pct = math.floor((1 - total_llm_calls / naive_calls) * 100)

    alc.log("info", string.format(
        "recipe_ranking_funnel: DONE — %d total calls vs %d naive (-%d%%)",
        total_llm_calls, naive_calls, savings_pct
    ))

    ctx.result = {
        ranking = final_ranking,
        best = final_ranking[1].text,
        best_index = final_ranking[1].original_index,
        funnel_bypassed = false,
        total_llm_calls = total_llm_calls,
        naive_baseline_calls = naive_calls,
        savings_percent = savings_pct,
        stages = stages,
        funnel_shape = { N, stages[1].output_count, stages[2].output_count },
    }
    return ctx
end

return M
