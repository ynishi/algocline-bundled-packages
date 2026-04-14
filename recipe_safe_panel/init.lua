--- recipe_safe_panel — Verified safe majority-vote panel
---
--- Recipe package: composes condorcet, sc, inverse_u, and calibrate
--- into a safety-gated panel vote. The recipe ensures that majority
--- voting is only applied when the mathematical preconditions are met,
--- and provides early warnings when adding more agents would degrade
--- rather than improve accuracy.
---
--- Pipeline:
---   Stage 1: condorcet — Panel size design
---     condorcet.is_anti_jury(p) gates entry: if p < 0.5, majority
---     vote provably degrades with more agents (Condorcet Anti-Jury).
---     condorcet.optimal_n(p, target) computes the minimum panel size
---     needed to reach the target accuracy.
---
---   Stage 2: sc — Independent sampling + majority vote
---     sc.run({ task, n }) samples N independent reasoning paths
---     with diversity hints to maximize independence. The majority
---     answer is extracted via vote counting.
---
---   Stage 3: inverse_u — Scaling health check
---     Analyzes the vote distribution to detect whether the panel
---     has reached or passed its accuracy peak. If the inverse-U
---     pattern (Chen et al. NeurIPS 2024) is detected, warns that
---     adding more agents would hurt.
---
---   Stage 4: calibrate — Meta-confidence gate
---     Synthesizes panel vote margin, Condorcet expected accuracy,
---     and inverse_u safety into a single confidence assessment.
---     Low confidence triggers "needs_investigation" flag.
---
--- Theory:
---   Condorcet, M. "Essai sur l'application de l'analyse..." 1785.
---     Core: P(Maj_n) → 1 as n → ∞ when p > 0.5 (Jury Theorem)
---     Anti: P(Maj_n) → 0 as n → ∞ when p < 0.5
---
---   Chen et al. "Are More LM Calls All You Need? Scaling Laws
---     in Multi-Agent Systems." NeurIPS 2024.
---     Theorem 2: Vote accuracy is inverse-U shaped in N when
---     p1 + p2 > 1 AND α < 1 - 1/t.
---
---   Wang et al. "Self-Consistency Improves Chain of Thought
---     Reasoning in Language Models." 2022. arXiv:2203.11171.
---
--- Caveats:
---   See M.caveats. Key: Anti-Jury abort, inverse-U detection,
---   independence violation from same-model sampling.
---
--- Usage:
---   local safe_panel = require("recipe_safe_panel")
---   return safe_panel.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.p_estimate: Estimated per-agent accuracy (default: 0.7)
--- ctx.target_accuracy: Target majority-vote accuracy (default: 0.95)
--- ctx.max_n: Maximum panel size (default: 15)
--- ctx.confidence_threshold: Calibrate gate threshold (default: 0.7)
--- ctx.scaling_check: Run inverse_u analysis (default: true)
--- ctx.gen_tokens: Max tokens per LLM call (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "recipe_safe_panel",
    version = "0.1.0",
    description = "Verified safe majority-vote panel — Condorcet-sized, "
        .. "Anti-Jury gated, inverse-U monitored, confidence-calibrated. "
        .. "Composes condorcet + sc + inverse_u + calibrate with known "
        .. "failure mode awareness.",
    category = "recipe",
}

--- Packages composed by this recipe, in execution order.
M.ingredients = {
    "condorcet",   -- Stage 1: panel size design + Anti-Jury gate
    "sc",          -- Stage 2: independent sampling + majority vote
    "inverse_u",   -- Stage 3: scaling health check
    "calibrate",   -- Stage 4: meta-confidence gate
}

--- Known failure conditions discovered through testing and theory.
M.caveats = {
    "p_estimate < 0.5 (Anti-Jury) makes majority vote provably harmful"
        .. " — adding more agents drives accuracy toward 0, not 1"
        .. " → recipe ABORTs with anti_jury=true and recommendation",
    "inverse_u detection needs >= 5 data points to be meaningful"
        .. " → recipe skips inverse_u check when panel size < 5",
    "sc samples from same model/prompt violate Condorcet's independence "
        .. "assumption — correlated agents weaken the theorem's guarantee"
        .. " → sc uses diversity hints; recipe adds correlation warning "
        .. "when vote unanimity is suspiciously high",
    "condorcet.optimal_n() assumes independence — with correlated agents "
        .. "the actual required N is higher"
        .. " → recipe applies 1.5x multiplier when p_estimate < 0.65 "
        .. "(low competence + correlation is the worst case)",
    "max_n cap can make target_accuracy unreachable"
        .. " → recipe reports actual expected accuracy rather than "
        .. "silently claiming the target was met",
}

--- Empirical verification results.
M.verified = {
    theoretical_basis = {
        "Condorcet Jury Theorem (1785): P(Maj_n) → 1 as n → ∞ when p > 0.5",
        "Chen et al. NeurIPS 2024 Theorem 2: inverse-U when α < 1-1/t",
        "Wang et al. 2022: Self-Consistency improves accuracy via majority vote",
    },
    e2e_runs = {
        {
            scenario = "Capital of Japan (factual QA, single case)",
            harness = "agent-block scripts/e2e/recipe_safe_panel.lua",
            model = "claude-haiku-4-5-20251001",
            run_id = "2026-04-15_021159",
            opts = { p_estimate = 0.85, target_accuracy = 0.7, max_n = 3 },
            panel_size = 3,
            answer = "Tokyo",
            confidence = 0.99,
            vote_margin = 1.0,
            condorcet_expected_acc = 0.939,
            total_llm_calls = 8,
            graders_passed = 6,
            graders_total = 6,
        },
    },
    alc_eval_runs = {
        {
            scenario = "math_basic",
            cases = 7,
            harness = "agent-block scripts/e2e/recipe_safe_panel_eval.lua → alc_eval",
            model = "claude-haiku-4-5-20251001",
            run_id = "2026-04-15_021851",
            opts = {
                p_estimate = 0.85, target_accuracy = 0.7,
                max_n = 3, confidence_threshold = 0.6, scaling_check = false,
            },
            pass_rate = 1.0,
            cases_passed = 7,
            total_llm_calls = 56,
            llm_calls_per_case = 8,
            mean_confidence = 0.99,
            anti_jury_triggers = 0,
            needs_investigation = 0,
            card_id = "recipe_safe_panel_model_20260414T172053_c551b6",
            exec_time_sec = 119.1,
        },
    },
}

-- ─── Internal helpers ───

--- Analyze vote distribution for consensus quality signals.
--- Returns margin (majority fraction), entropy, and unanimity flag.
local function analyze_votes(vote_counts, total)
    local max_count = 0
    local n_distinct = 0
    for _, count in pairs(vote_counts) do
        if count > max_count then max_count = count end
        n_distinct = n_distinct + 1
    end

    local margin = max_count / total

    -- Shannon entropy of vote distribution (normalized by log(n_distinct))
    local entropy = 0
    for _, count in pairs(vote_counts) do
        if count > 0 then
            local p = count / total
            entropy = entropy - p * math.log(p)
        end
    end
    local max_entropy = n_distinct > 1 and math.log(n_distinct) or 0
    local norm_entropy = max_entropy > 0 and entropy / max_entropy or 0

    return {
        margin = margin,
        max_count = max_count,
        n_distinct = n_distinct,
        norm_entropy = norm_entropy,
        unanimous = (n_distinct == 1),
    }
end

--- Build progressive accuracy series from sc votes for inverse_u analysis.
--- Simulates "what if we had used only the first k votes?" for k=1,3,5,...
local function build_accuracy_proxy(votes, answer)
    local series = {}
    local match_count = 0
    for i = 1, #votes do
        if votes[i] == answer then
            match_count = match_count + 1
        end
        -- Only odd panel sizes give clean majority
        if i % 2 == 1 and i >= 3 then
            series[#series + 1] = match_count / i
        end
    end
    return series
end

-- ─── Main pipeline ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("recipe_safe_panel: ctx.task is required")
    local p_est = ctx.p_estimate or 0.7
    local target = ctx.target_accuracy or 0.95
    local max_n = ctx.max_n or 15
    local conf_threshold = ctx.confidence_threshold or 0.7
    local do_scaling = ctx.scaling_check ~= false
    local gen_tokens = ctx.gen_tokens or 400

    local stages = {}
    local total_llm_calls = 0

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 1: condorcet — Panel size design + Anti-Jury gate
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_safe_panel: ═══ Stage 1/4 — condorcet "
            .. "(p=%.2f, target=%.2f) ═══",
        p_est, target
    ))

    local condorcet = require("condorcet")

    -- Caveat: Anti-Jury check
    if condorcet.is_anti_jury(p_est) then
        alc.log("error", string.format(
            "recipe_safe_panel: ABORT — Anti-Jury detected (p=%.2f < 0.5). "
                .. "Majority vote will DEGRADE accuracy with more agents.",
            p_est
        ))

        ctx.result = {
            answer = nil,
            confidence = 0,
            panel_size = 0,
            anti_jury = true,
            aborted = true,
            abort_reason = string.format(
                "Anti-Jury: p=%.2f < 0.5. Condorcet Jury Theorem guarantees "
                    .. "that majority vote accuracy → 0 as N → ∞. "
                    .. "Do NOT use panel voting. Consider: "
                    .. "(1) improve individual agent quality, "
                    .. "(2) use expert routing instead of voting, "
                    .. "(3) use pairwise_rank for comparison-based selection.",
                p_est
            ),
            stages = { {
                name = "condorcet_anti_jury",
                p_estimate = p_est,
                is_anti_jury = true,
            } },
        }
        return ctx
    end

    -- Compute optimal panel size
    local recommended_n = condorcet.optimal_n(p_est, target)

    -- Caveat: correlation adjustment for low competence
    if p_est < 0.65 then
        local adjusted = math.ceil(recommended_n * 1.5)
        alc.log("info", string.format(
            "recipe_safe_panel: low p=%.2f, applying 1.5x correlation "
                .. "adjustment: %d → %d",
            p_est, recommended_n, adjusted
        ))
        recommended_n = adjusted
    end

    -- Cap at max_n
    if recommended_n > max_n then
        alc.log("warn", string.format(
            "recipe_safe_panel: recommended N=%d exceeds max_n=%d, capping",
            recommended_n, max_n
        ))
        recommended_n = max_n
    end

    -- Ensure odd for clean majority
    if recommended_n % 2 == 0 then
        recommended_n = recommended_n + 1
        if recommended_n > max_n then
            recommended_n = recommended_n - 2
        end
    end
    if recommended_n < 3 then recommended_n = 3 end

    local expected_acc = condorcet.prob_majority(recommended_n, p_est)

    stages[1] = {
        name = "condorcet",
        p_estimate = p_est,
        recommended_n = recommended_n,
        expected_accuracy = expected_acc,
        target_accuracy = target,
        target_met = expected_acc >= target,
    }

    alc.log("info", string.format(
        "recipe_safe_panel: Stage 1 — N=%d, expected_acc=%.3f (target=%.2f, %s)",
        recommended_n, expected_acc, target,
        expected_acc >= target and "MET" or "NOT MET"
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 2: sc — Independent sampling + majority vote
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_safe_panel: ═══ Stage 2/4 — sc (N=%d) ═══",
        recommended_n
    ))

    local sc = require("sc")
    local sc_result = sc.run({
        task = task,
        n = recommended_n,
        gen_tokens = gen_tokens,
    })

    local answer = sc_result.result.answer or sc_result.result.consensus
    local answer_norm = sc_result.result.answer_norm
    local vote_counts = sc_result.result.vote_counts or {}
    local votes = sc_result.result.votes or {}
    local sc_calls = sc_result.result.total_llm_calls
        or (recommended_n * 2)  -- samples + extractions
    total_llm_calls = total_llm_calls + sc_calls

    -- Analyze vote distribution
    local vote_info = analyze_votes(vote_counts, recommended_n)

    stages[2] = {
        name = "sc",
        panel_size = recommended_n,
        answer = answer,
        vote_margin = vote_info.margin,
        n_distinct_answers = vote_info.n_distinct,
        unanimous = vote_info.unanimous,
        llm_calls = sc_calls,
    }

    -- Caveat: unanimity warning (possible independence violation)
    if vote_info.unanimous and recommended_n >= 5 then
        alc.log("warn",
            "recipe_safe_panel: UNANIMOUS vote — possible independence "
                .. "violation. Same model/prompt may be producing identical "
                .. "reasoning paths. Consider diversifying prompts or models."
        )
    end

    alc.log("info", string.format(
        "recipe_safe_panel: Stage 2 — answer='%s', margin=%.0f%%, "
            .. "%d distinct answers (%d calls)",
        tostring(answer):sub(1, 50),
        vote_info.margin * 100,
        vote_info.n_distinct,
        sc_calls
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 3: inverse_u — Scaling health check
    -- ═══════════════════════════════════════════════════════════════
    local scaling_safe = true
    local peak_info = nil

    local has_votes = type(votes) == "table" and #votes >= 5
    if do_scaling and recommended_n >= 5 and has_votes then
        alc.log("info", "recipe_safe_panel: ═══ Stage 3/4 — inverse_u ═══")

        local inverse_u = require("inverse_u")

        -- Build accuracy proxy series from progressive vote subsets.
        -- votes[i] are normalized, so compare against answer_norm.
        local series = build_accuracy_proxy(votes, answer_norm or answer)

        if #series >= 3 then
            peak_info = inverse_u.detect(series)
            scaling_safe = not peak_info.is_declining

            if not scaling_safe then
                alc.log("warn", string.format(
                    "recipe_safe_panel: INVERSE-U DETECTED — accuracy peaked "
                        .. "at series point %d with %d consecutive drops. "
                        .. "Do NOT add more agents.",
                    peak_info.peak_idx or 0,
                    peak_info.consecutive_drops or 0
                ))
            end
        else
            alc.log("info",
                "recipe_safe_panel: Stage 3 — insufficient data points "
                    .. "for inverse_u analysis"
            )
        end

        stages[3] = {
            name = "inverse_u",
            series_length = #series,
            is_safe = scaling_safe,
            peak_idx = peak_info and peak_info.peak_idx,
            consecutive_drops = peak_info and peak_info.consecutive_drops,
        }
    else
        local skip_reason
        if not do_scaling then
            skip_reason = "scaling_check disabled"
        elseif recommended_n < 5 then
            skip_reason = "panel too small (N < 5)"
        elseif not has_votes then
            skip_reason = "sc did not return individual votes array"
        else
            skip_reason = "insufficient vote data"
        end

        alc.log("info", string.format(
            "recipe_safe_panel: Stage 3 skipped — %s", skip_reason
        ))

        stages[3] = {
            name = "inverse_u_skipped",
            reason = skip_reason,
            is_safe = true,
        }
    end

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 4: calibrate — Meta-confidence gate
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", "recipe_safe_panel: ═══ Stage 4/4 — calibrate ═══")

    local calibrate = require("calibrate")

    local cal_task = string.format(
        "A panel of %d independent agents voted on the following task:\n"
            .. "Task: %s\n\n"
            .. "Panel result:\n"
            .. "  Answer: %s\n"
            .. "  Vote margin: %.0f%% (%d/%d agents agree)\n"
            .. "  Distinct answers: %d\n"
            .. "  Expected accuracy (Condorcet, p=%.2f): %.1f%%\n"
            .. "  Scaling safety (inverse-U): %s\n\n"
            .. "Based on this information, how confident should we be "
            .. "in the panel's answer?",
        recommended_n,
        task,
        tostring(answer),
        vote_info.margin * 100,
        vote_info.max_count,
        recommended_n,
        vote_info.n_distinct,
        p_est,
        expected_acc * 100,
        scaling_safe and "SAFE (no decline detected)"
            or "WARNING (inverse-U pattern detected)"
    )

    local cal_result = calibrate.run({
        task = cal_task,
        threshold = conf_threshold,
        fallback = "retry",  -- retry only — don't spawn another panel
        gen_tokens = 300,
    })

    local confidence = cal_result.result.confidence or 0.5
    local cal_calls = cal_result.result.escalated and 2 or 1
    total_llm_calls = total_llm_calls + cal_calls

    local needs_investigation = confidence < conf_threshold

    stages[4] = {
        name = "calibrate",
        confidence = confidence,
        threshold = conf_threshold,
        needs_investigation = needs_investigation,
        escalated = cal_result.result.escalated or false,
        llm_calls = cal_calls,
    }

    alc.log("info", string.format(
        "recipe_safe_panel: Stage 4 — confidence=%.2f (%s, threshold=%.2f)",
        confidence,
        needs_investigation and "NEEDS INVESTIGATION" or "OK",
        conf_threshold
    ))

    -- ═══════════════════════════════════════════════════════════════
    -- Assemble result
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_safe_panel: DONE — answer='%s', confidence=%.2f, "
            .. "panel=%d, margin=%.0f%%, %d total calls",
        tostring(answer):sub(1, 50),
        confidence,
        recommended_n,
        vote_info.margin * 100,
        total_llm_calls
    ))

    ctx.result = {
        answer = answer,
        confidence = confidence,
        panel_size = recommended_n,
        vote_margin = vote_info.margin,
        vote_counts = vote_counts,
        n_distinct_answers = vote_info.n_distinct,
        expected_accuracy = expected_acc,
        target_met = expected_acc >= target,
        is_safe = scaling_safe,
        anti_jury = false,
        aborted = false,
        needs_investigation = needs_investigation,
        unanimous = vote_info.unanimous,
        total_llm_calls = total_llm_calls,
        stages = stages,
    }
    return ctx
end

return M
