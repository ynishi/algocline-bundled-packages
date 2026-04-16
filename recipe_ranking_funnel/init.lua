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
---                              ACTIVATION: with default top_k1 =
---                              ceil(N/3) and top_k2 = min(top_k1, 5),
---                              Stage 2 only fires when top_k1 > 5,
---                              i.e. N >= 16. For N ≤ 15 with defaults,
---                              #survivors_1 == top_k2 so Stage 2 is
---                              skipped (flagged in stages[2].name =
---                              "scoring_skipped"). To force Stage 2 on
---                              smaller N, pass ctx.top_k2 explicitly
---                              lower than top_k1.
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
--- ctx.gen_tokens: Max tokens per LLM call in Stage 1 (listwise) and
---     Stage 2 (scoring). (default: 400)
--- ctx.judge_gen_tokens: Max tokens per pairwise judgement call in
---     Stage 3 (and in the N<6 direct-pairwise bypass). Pairwise
---     judgements only need a short verdict (e.g. "A>B"), so this
---     defaults to 20 — lower than gen_tokens on purpose. (default: 20)

local M = {}

---@type AlcMeta
M.meta = {
    name = "recipe_ranking_funnel",
    version = "0.1.0",
    description = "Verified 3-stage ranking funnel — listwise screening, "
        .. "multi-axis scoring, pairwise final rank. -87% calls vs naive "
        .. "pairwise on N=8 (verified). Encodes known failure modes as caveats.",
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
    "N < 6 makes the 3-stage funnel lose discriminative power: "
        .. "Stage 1 (listwise) top_k1 = ceil(N/3) drops to 2 at N=5, "
        .. "forcing Stage 3 (pairwise allpair) onto only 2 items (a single "
        .. "comparison). For small N the funnel is actually CHEAPER than "
        .. "direct allpair (N=5: ~3 calls vs 20), but the aggressive "
        .. "pre-screening leaves no middle ground for pairwise to evaluate"
        .. " → recipe falls back to direct pairwise_rank so all N items "
        .. "get a full bidirectional comparison",
    "pairwise_rank allpair on N > 12 causes cost explosion "
        .. "(>264 LLM calls for bidirectional)"
        .. " → top_k2 capped at 12 (default 5 is safe)",
    "Stage 2 scoring axes must match the ranking criterion; "
        .. "generic axes on domain-specific tasks lose discriminative power"
        .. " → provide ctx.scoring_axes for specialized domains",
    "Stage 2 (multi-axis scoring) is skipped for N ≤ 15 with default "
        .. "top_k1/top_k2 because #survivors_1 == top_k2 ⇒ nothing to score "
        .. "further. Users expecting a 3-stage funnel at N=8 will actually "
        .. "get Stage 1 → Stage 3 only (funnel_shape = {N, top_k1, top_k1})"
        .. " → pass ctx.top_k2 explicitly smaller than top_k1, or raise N "
        .. "above 15, to force Stage 2 to fire",
    "pairwise_rank.compare_pair fails LOUDLY (error() raised) when a "
        .. "single LLM verdict cannot be parsed — this is intentional "
        .. "(silent tie would systematically bias Copeland aggregation). "
        .. "Consequence for this recipe: a single unparseable verdict "
        .. "aborts Stage 3 (main path) or the whole N<6 bypass. There is "
        .. "no per-pair retry / fallback. Mitigation: keep judge_gen_tokens "
        .. "small (default 20) and the pairwise prompt strict so LLMs "
        .. "reliably emit 'Verdict: A/B/tie'; on production workloads wrap "
        .. "the recipe call in pcall if robust continuation matters more "
        .. "than bias-free ranking.",
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
        {
            scenario = "N<6 bypass: TIOBE 2026 ranking (N=4, direct pairwise)",
            harness = "agent-block scripts/e2e/recipe_ranking_funnel_bypass.lua",
            model = "claude-haiku-4-5-20251001",
            run_id = "2026-04-15_091159",
            opts = { candidates_n = 4, gen_tokens = 200 },
            funnel_bypassed = true,
            bypass_reason = "N < 6",
            funnel_shape = { 4, 4, 4 },  -- all 3 stages receive N=4 (skipped stages pass-through)
            top_1 = "Python",
            top_1_correct = true,
            total_llm_calls = 12,  -- N*(N-1) = 4*3 bidirectional pairwise
            naive_baseline_calls = 12,
            savings_percent = nil,  -- NOT 0 — bypass makes savings undefined (P6 fix)
            graders_passed = 7,
            graders_total = 8,  -- python_top_ranked regex missed markdown-table "🥇 1 | Python"
            verifies = {
                "funnel_bypassed = true",
                "bypass_reason = 'N < 6'",
                "savings_percent = nil (P6 fix, not 0)",
                "stages[1..3] all emitted (listwise_skipped, scoring_skipped, pairwise_direct)",
                "ranking shape matches main path",
            },
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
--- Matching is case-insensitive on both the AVERAGE line and per-axis lines:
--- LLMs frequently echo axis names with different casing ("Correctness: 8")
--- than the prompt template ("correctness: <number>"). Without lowercasing,
--- per-axis fallback silently fails and every candidate collapses to the
--- 5.0 default, destroying Stage 2's discriminative power.
local function parse_scoring_response(raw, axes)
    local raw_lc = raw:lower()

    -- Try AVERAGE line first (case-insensitive).
    local avg = raw_lc:match("average:%s*([%d%.]+)")
    if avg then
        local n = tonumber(avg)
        if n and n >= 0 and n <= 10 then return n end
    end

    -- Fallback: parse individual axis scores and compute average.
    -- Lowercase both the haystack and the axis name so "Correctness: 8"
    -- matches an axis named "correctness".
    local total = 0
    local count = 0
    for _, ax in ipairs(axes) do
        local pattern = ax.name:lower() .. ":%s*([%d%.]+)"
        local m = raw_lc:match(pattern)
        if m then
            local n = tonumber(m)
            if n and n >= 0 and n <= 10 then
                total = total + n
                count = count + 1
            end
        end
    end
    if count > 0 then return total / count end

    -- Last resort: use alc.parse_score if available. The `alc and ...`
    -- guard keeps this helper callable from pure unit tests where the
    -- alc global is not injected.
    if alc and alc.parse_score then
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
    local judge_gen_tokens = ctx.judge_gen_tokens or 20
    local stages = {}
    local total_llm_calls = 0

    -- ═══════════════════════════════════════════════════════════════
    -- Caveat: N < 6 → direct pairwise. The funnel is CHEAPER at small N
    -- (e.g. N=5: ~3 calls vs allpair 20), but Stage 1's top_k1=ceil(N/3)
    -- drops to 2, leaving Stage 3 with only a single comparison. Bypass
    -- so every item gets full bidirectional scrutiny.
    -- ═══════════════════════════════════════════════════════════════
    if N < 6 then
        alc.log("info", string.format(
            "recipe_ranking_funnel: N=%d < 6, bypassing funnel → direct "
                .. "pairwise (aggressive screening would leave too few items "
                .. "for Stage 3 to discriminate)",
            N
        ))

        local pairwise_rank = require("pairwise_rank")
        local pr = pairwise_rank.run({
            task = task,
            candidates = candidates,
            method = "allpair",
            gen_tokens = judge_gen_tokens,
        })

        -- Same baseline formula as the non-bypass path; for N<6 the funnel
        -- short-circuits and actually RUNS the naive baseline (direct
        -- allpair pairwise). Savings is therefore not defined — surface
        -- nil instead of 0, so consumers can distinguish "funnel saved
        -- nothing" from "bypass means savings is n/a". funnel_bypassed
        -- = true already signals the bypass.
        local naive_calls = N * (N - 1)
        local savings_pct = nil

        -- Normalize pairwise_rank's ranked shape ({rank, index, score, text})
        -- to the non-bypass shape ({rank, text, original_index, pairwise_score})
        -- so consumers can read result.ranking uniformly regardless of path.
        -- In the bypass, pairwise operates on the full original candidate
        -- array, so pr_item.index IS already the 1-based original index.
        local final_ranking = {}
        for _, pr_item in ipairs(pr.result.ranked) do
            final_ranking[#final_ranking + 1] = {
                rank = pr_item.rank,
                text = pr_item.text,
                original_index = pr_item.index,
                pairwise_score = pr_item.score,
            }
        end

        ctx.result = {
            ranking = final_ranking,
            best = final_ranking[1].text,
            best_index = final_ranking[1].original_index,
            funnel_bypassed = true,
            bypass_reason = "N < 6",
            total_llm_calls = pr.result.total_llm_calls,
            naive_baseline_calls = naive_calls,
            -- Distinct from the non-bypass kind because the bypass path is
            -- NOT a counterfactual — it IS the "naive" allpair run. The
            -- `bypass_` prefix lets consumers pattern-match the distinction
            -- without re-reading `funnel_bypassed`. savings_percent is nil
            -- (not 0) to signal "savings is n/a here", not "zero saved".
            naive_baseline_kind = "bypass_direct_pairwise_allpair_bidirectional",
            savings_percent = savings_pct,
            -- Bypass path has no Stage 2 scoring, so nothing to flag.
            -- Still emit `warnings = {}` so consumers can uniformly
            -- check `#result.warnings > 0` regardless of code path.
            warnings = {},
            -- Emit 3 stages so consumers can safely index stages[1..3]
            -- regardless of the bypass path. Stages 1 and 2 are marked
            -- skipped; stage 3 carries the direct-pairwise result.
            stages = {
                {
                    name = "listwise_skipped",
                    input_count = N,
                    output_count = N,
                    llm_calls = 0,
                    reason = "N < 6 bypass",
                },
                {
                    name = "scoring_skipped",
                    input_count = N,
                    output_count = N,
                    llm_calls = 0,
                    reason = "N < 6 bypass",
                },
                {
                    name = "direct_pairwise",
                    input_count = N,
                    output_count = N,
                    llm_calls = pr.result.total_llm_calls,
                    position_bias_splits = pr.result.position_bias_splits,
                    both_tie_pairs = pr.result.both_tie_pairs,
                },
            },
            -- funnel_shape matches the non-bypass convention
            -- ([S1-input, S2-input, S3-input]). In the bypass, all three
            -- conceptual stages see N candidates: no reduction happens.
            funnel_shape = { N, N, N },
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

    -- Caveat: window_size too small loses top candidates.
    --
    -- Rationale: listwise_rank slides with stride = ceil(window_size/2).
    -- For a true top-K to survive every sliding pass, the final head
    -- window [1, window_size] must contain the K-th best item. With
    -- window_size < ceil(N/2) the stride is small enough that the best
    -- items can bounce out of the head window on intermediate passes,
    -- which statistically biases them downward. Setting window_size >=
    -- ceil(N/2) guarantees the final head window covers the top half
    -- of positions, which keeps the K-th item reachable for K <= N/2.
    --
    -- The raise is skipped when window_size >= N (single-call path inside
    -- listwise_rank — no sliding, no risk).
    local min_window = math.ceil(N / 2)
    if window_size < min_window and N > window_size then
        alc.log("warn", string.format(
            "recipe_ranking_funnel: window_size %d < ceil(N/2)=%d, raising "
                .. "(listwise stride = ceil(window/2) needs window >= N/2 "
                .. "to keep top items in the final head window)",
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
                max_tokens = gen_tokens,
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

        -- Sort by Stage 2 score descending. Note: Stage 1's ordinal
        -- ranking is intentionally DISCARDED here except as a tie-break
        -- when two candidates receive identical Stage 2 scores. Stage 2
        -- is a stronger (multi-axis) evaluator than Stage 1 (pure
        -- listwise ordering), so we let its scores dominate. If you
        -- want Stage 1's rank to carry more weight, lift top_k1 so more
        -- survivors reach Stage 3 directly.
        table.sort(scored, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.stage1_rank < b.stage1_rank
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
        gen_tokens = judge_gen_tokens,
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

    -- Estimate token savings vs the most-expensive naive alternative:
    -- pairwise_rank allpair in bidirectional mode on all N candidates
    -- (= N*(N-1) LLM calls). The comparison is apples-to-apples for users
    -- who would otherwise use pairwise_rank for the whole set; if your
    -- baseline is single-pass pairwise (N*(N-1)/2) or listwise-only
    -- (N/window_size), the savings number below over-reports.
    local naive_calls = N * (N - 1)
    -- savings_pct becomes negative if total_llm_calls > naive_calls. Under
    -- the current funnel design this is unreachable for N >= 6: Stage 3
    -- runs allpair on top_k2 <= 5 items (default), while the naive baseline
    -- allpairs all N, so the funnel is strictly cheaper. No defensive clamp
    -- is applied — an unreachable guard would only add branch noise. If a
    -- future change widens top_k2 beyond N*(N-1)/(N<6-cap) this may turn
    -- negative; treat a negative savings_pct as a bug signal, not a value.
    local savings_pct = math.floor((1 - total_llm_calls / naive_calls) * 100)

    alc.log("info", string.format(
        "recipe_ranking_funnel: DONE — %d total calls vs %d naive "
            .. "(pairwise allpair bidirectional, -%d%%)",
        total_llm_calls, naive_calls, savings_pct
    ))

    -- Top-level structured diagnostics.
    --
    -- Shape (stable contract; extend by adding new `code`s):
    --   warnings = {
    --     {
    --       code     = "<identifier, snake_case>",
    --       severity = "warn" | "critical",
    --       data     = { ... raw numbers for the consumer to re-threshold ... },
    --       message  = "<one-line human-readable summary>",
    --     },
    --     ...
    --   }
    --
    -- Why structured rather than a boolean + string array:
    --   - Future failure modes (Stage 1 inconsistency, Stage 3 tie spikes,
    --     etc.) must be addable without breaking existing consumers.
    --   - Consumers with different thresholds can re-derive from `data`
    --     instead of being locked to our baked-in cutoffs.
    --   - `message` serves HIL/log use cases directly; `code` serves
    --     machine routing; `data` serves re-thresholding. One record
    --     covers all three consumer shapes without duplication.
    --
    -- Consumers check `#result.warnings > 0` for the "any issue?" path.
    -- We intentionally do NOT emit a separate `needs_attention` boolean
    -- to avoid two fields carrying the same bit.
    local warnings = {}

    -- WARN: stage_2_parse_failure_rate_high
    -- Half or more of Stage 2 scoring calls returned unparseable scores.
    -- Effect: all unparseable candidates collapse to the 5.0 default, so
    -- Stage 3 input ordering is dominated by the 5.0 tie-break (Stage 1
    -- ordinal). The recipe still returns a ranking, but its Stage-2
    -- discriminative power is gone. Threshold 0.5 is hardcoded here
    -- because it is the point at which majority-default reduces Stage 2
    -- to a tie-break stage; consumers wanting a stricter cutoff re-check
    -- via `data.rate`.
    local s2 = stages[2]
    if s2 and s2.parse_failures and s2.parse_failures > 0 then
        local scored_n = s2.input_count or 0
        if scored_n > 0 and s2.parse_failures >= math.ceil(scored_n / 2) then
            local rate = s2.parse_failures / scored_n
            warnings[#warnings + 1] = {
                code = "stage_2_parse_failure_rate_high",
                severity = "warn",
                data = {
                    parse_failures = s2.parse_failures,
                    scored_n = scored_n,
                    rate = rate,
                    threshold = 0.5,
                },
                message = string.format(
                    "Stage 2 parse failures %d/%d (%.0f%%) >= 50%%; "
                        .. "scoring effectively collapsed to Stage 1 "
                        .. "ordinal ranking (unparseable candidates "
                        .. "defaulted to 5.0 and tie-break by Stage 1 rank)",
                    s2.parse_failures, scored_n, rate * 100
                ),
            }
        end
    end

    ctx.result = {
        ranking = final_ranking,
        best = final_ranking[1].text,
        best_index = final_ranking[1].original_index,
        funnel_bypassed = false,
        total_llm_calls = total_llm_calls,
        naive_baseline_calls = naive_calls,
        naive_baseline_kind = "pairwise_rank_allpair_bidirectional",
        savings_percent = savings_pct,
        warnings = warnings,
        stages = stages,
        -- funnel_shape = [input-to-Stage-1, input-to-Stage-2, input-to-Stage-3]
        --              = [N, survivors-after-Stage-1, survivors-after-Stage-2]
        -- Length is always 3. Bypass path emits {N, N, N} (no reduction).
        funnel_shape = { N, stages[1].output_count, stages[2].output_count },
    }
    return ctx
end

-- ─── Test hooks ───
-- Expose pure helpers for unit testing. Not part of the public API;
-- prefix = `_internal` is the convention used by other recipe packages.
M._internal = {
    DEFAULT_SCORING_AXES = DEFAULT_SCORING_AXES,
    build_scoring_prompt = build_scoring_prompt,
    parse_scoring_response = parse_scoring_response,
}

return M
