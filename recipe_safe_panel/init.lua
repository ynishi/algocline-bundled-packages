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
---   Stage 3: inverse_u — Vote-prefix stability check
---     Builds a progressive-majority series from the first 3, 5, 7,
---     ... votes of the single sc run (all from the same panel), then
---     feeds it to inverse_u.detect as a lightweight stability proxy.
---     NOTE: This is NOT a true inverse-U test. Chen et al. (NeurIPS
---     2024) concerns the accuracy curve across independent panels of
---     increasing size; a prefix of one run tends to approach the
---     majority fraction monotonically and will usually report "safe".
---     A true inverse-U test requires repeating sc.run at multiple N.
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
--- ctx.p_estimate (required): Estimated per-agent accuracy in (0, 1].
---     REQUIRED with no default — silent fallback to 0.7 would bypass
---     the Anti-Jury gate on tasks where the real p < 0.5. Estimate via
---     a pilot (sc.run at n=1 over a labeled sample, then
---     condorcet.estimate_p) or pass an explicit value based on task
---     difficulty.
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
    "inverse_u detection needs >= 3 series points to be meaningful, and "
        .. "the prefix accuracy series is only sampled at odd k >= 3 "
        .. "(k = 3, 5, 7, ...). So Stage 3 requires a panel of n >= 7 to "
        .. "produce a 3-point series; at n in {3, 5} the stage is skipped "
        .. "(logged as 'insufficient data points')"
        .. " → run with max_n >= 7 if you need Stage 3 to fire; smaller "
        .. "panels rely entirely on Condorcet expected accuracy + calibrate "
        .. "confidence gating",
    "sc samples from same model/prompt violate Condorcet's independence "
        .. "assumption — correlated agents weaken the theorem's guarantee"
        .. " → sc uses diversity hints; recipe adds correlation warning "
        .. "when vote unanimity is suspiciously high",
    "condorcet.optimal_n() assumes independence — with correlated agents "
        .. "the actual required N is higher"
        .. " → recipe applies a 1.5x multiplier when p_estimate < 0.65. "
        .. "NOTE: 1.5x is a recipe-level HEURISTIC, not a theorem. It is "
        .. "chosen to approximately compensate for the sample-size inflation "
        .. "implied by a moderate intra-panel correlation (ρ ≈ 0.2–0.3) in "
        .. "the effective-N formula N_eff = N / (1 + (N-1)·ρ). For stronger "
        .. "correlation, or to replace this with a measured adjustment, pass "
        .. "your own ctx.max_n or pre-compute recommended_n with condorcet "
        .. "and disable this recipe layer.",
    "max_n cap can make target_accuracy unreachable"
        .. " → recipe reports actual expected accuracy rather than "
        .. "silently claiming the target was met",
    "Stage 3 inverse_u uses a single-run vote prefix as an accuracy proxy, "
        .. "not independent panels of increasing size (Chen et al. scenario)"
        .. " → the prefix series is biased toward monotone convergence and "
        .. "rarely triggers; treat the 'safe' signal as weak evidence only. "
        .. "For a true inverse-U test, call sc.run at multiple N and feed "
        .. "the resulting accuracy curve to inverse_u.detect directly.",
    "ctx.p_estimate is the USER'S ESTIMATE of per-agent accuracy and is "
        .. "trusted as-is. It is REQUIRED (no silent default): omitting "
        .. "it raises an error. This was a deliberate break from the "
        .. "initial 0.7 default — that default silently bypassed the "
        .. "Anti-Jury abort on tasks where the real p < 0.5, defeating "
        .. "the main safety guarantee of this recipe"
        .. " → always set ctx.p_estimate explicitly. When unsure, run a "
        .. "small pilot (e.g. sc.run with n=1 over a labeled sample) and "
        .. "feed condorcet.estimate_p() into p_estimate before invoking "
        .. "this recipe.",
    "Stage 4 (calibrate) is invoked via calibrate.assess, not calibrate."
        .. "run — the recipe consumes only result.confidence and applies "
        .. "its own conf_threshold gate via needs_investigation. assess "
        .. "is exactly calibrate's 1-call Phase 1 (answer + self-assessed "
        .. "confidence) with no escalation, matching what this recipe "
        .. "needs; escalation inside calibrate would not reassess "
        .. "confidence and therefore cannot improve the signal this "
        .. "recipe reads. Consequence: every non-abort run pays a fixed "
        .. "+1 LLM call on top of sc's 2n+1. Budget for the recipe is "
        .. "therefore 2n+2 LLM calls in steady state (plus optional Stage "
        .. "3 which is call-free)."
        .. " → when sizing cost caps include the +1 calibrate call; when "
        .. "abort-gated, cost is 0 LLM calls (Stage 1 is pure math).",
    "p_estimate = 0.5 is treated like Anti-Jury: the recipe aborts with "
        .. "aborted=true and anti_jury=false (distinguished as coin-flip). "
        .. "At p=0.5, P(Maj_n) = 0.5 for every odd n, so a panel adds no "
        .. "signal"
        .. " → improve agent quality before using any voting strategy; do "
        .. "not pass p_estimate=0.5 hoping the panel will rescue it.",
}

--- Empirical verification results.
---
--- Note on Stage 3 (vote_prefix): In every recorded run max_n = 3, but the
--- prefix-stability series needs length >= 3 sampled at odd k >= 3, which
--- requires n >= 7. Stage 3 therefore reports "skipped (panel too small /
--- scaling_check disabled)" in all current runs — that string is not
--- evidence of inverse_u detecting "safe"; it means the stage did not run.
--- See `stage_coverage` entry for Stage 3 below for the structured coverage
--- status and the action required to close the gap.
---
--- Shape of `stage_coverage` (stable contract; see R3 design note):
---   Array of { stage, name, status, evidence[, reason, to_verify] }.
---   `status`: "verified" | "not_exercised" | "theoretical_only"
---   `evidence`: array of run_id strings from e2e_runs / alc_eval_runs
---               that actually exercised this stage.
---   `reason` / `to_verify`: present when status != "verified"; reason
---               explains why coverage is missing, to_verify prescribes
---               the concrete run that would close the gap.
M.verified = {
    theoretical_basis = {
        "Condorcet Jury Theorem (1785): P(Maj_n) → 1 as n → ∞ when p > 0.5",
        "Chen et al. NeurIPS 2024 Theorem 2: inverse-U when α < 1-1/t",
        "Wang et al. 2022: Self-Consistency improves accuracy via majority vote",
    },
    stage_coverage = {
        {
            stage = 1,
            name = "condorcet",
            status = "verified",
            -- Anti-Jury gate exercised by run 2; optimal_n + p>0.5 path
            -- exercised by runs 1 and 3.
            evidence = {
                "2026-04-15_021159",
                "2026-04-15_091138",
                "2026-04-15_021851",
            },
        },
        {
            stage = 2,
            name = "sc",
            status = "verified",
            -- Panel sampling + plurality vote exercised by non-aborted
            -- runs. Run 2 aborts at Stage 1 so does NOT evidence Stage 2.
            evidence = {
                "2026-04-15_021159",
                "2026-04-15_021851",
            },
        },
        {
            stage = 3,
            name = "vote_prefix",
            status = "not_exercised",
            reason = "max_n < 7 in all recorded runs; prefix series is "
                .. "sampled at odd k >= 3, which requires n >= 7 to yield "
                .. "the 3-point minimum inverse_u.detect needs.",
            to_verify = "re-run recipe_safe_panel with max_n >= 7 and "
                .. "scaling_check = true; confirm stages[3] reports a "
                .. "series with length >= 3 rather than 'skipped', and "
                .. "capture whether inverse_u.detect flags the series.",
            evidence = {},
        },
        {
            stage = 4,
            name = "calibrate",
            status = "verified",
            -- Confidence-gate path exercised by non-aborted runs. Run 2
            -- aborts at Stage 1 so does NOT evidence Stage 4.
            evidence = {
                "2026-04-15_021159",
                "2026-04-15_021851",
            },
        },
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
            plurality_fraction = 1.0,
            margin_gap = 1.0,
            condorcet_expected_acc = 0.939,
            total_llm_calls = 8,
            graders_passed = 6,
            graders_total = 6,
        },
        {
            scenario = "Anti-Jury abort (p_estimate=0.3 → refuse panel)",
            harness = "agent-block scripts/e2e/recipe_safe_panel_anti_jury.lua",
            model = "claude-haiku-4-5-20251001",
            run_id = "2026-04-15_091138",
            opts = {
                p_estimate = 0.3, target_accuracy = 0.95,
                max_n = 7, confidence_threshold = 0.6, scaling_check = false,
            },
            aborted = true,
            anti_jury = true,
            panel_size = 0,
            answer = nil,  -- no panel sampled
            total_llm_calls = 0,  -- Stage 1 pure-math abort
            abort_reason_excerpt = "Anti-Jury: p=0.30 < 0.5",
            agent_turns = 2,
            graders_passed = 8,
            graders_total = 8,
            verifies = {
                "aborted/anti_jury flags set",
                "zero LLM calls (no panel sampled)",
                "abort_reason surfaces p value",
                "answer = nil",
                "result shape unified with main path",
            },
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
--- Returns:
---   plurality_fraction — max_count / total. This is the TOP-answer share,
---     NOT a majority-vs-runner-up gap. On a 2-2-1 split with n=5 it is
---     0.4 even though no answer has a strict majority. Named explicitly
---     to avoid confusion with the LLM-as-judge "winning margin" idiom.
---   margin_gap — (max_count - runner_up_count) / total. True margin-of-
---     victory. 0 when the vote is tied at the top.
---   norm_entropy — Shannon entropy normalized by log(n_distinct).
---   unanimous — all votes agree.
local function analyze_votes(vote_counts, total)
    local max_count = 0
    local runner_up = 0
    local n_distinct = 0
    for _, count in pairs(vote_counts) do
        if count > max_count then
            runner_up = max_count
            max_count = count
        elseif count > runner_up then
            runner_up = count
        end
        n_distinct = n_distinct + 1
    end

    local plurality_fraction = max_count / total
    local margin_gap = (max_count - runner_up) / total

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
        plurality_fraction = plurality_fraction,
        margin_gap = margin_gap,
        max_count = max_count,
        runner_up_count = runner_up,
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

    -- p_estimate is REQUIRED. A silent default (previously 0.7) would let
    -- a caller who forgot to pass it run a panel on a task where the real
    -- p < 0.5, silently bypassing the Anti-Jury gate — the exact failure
    -- mode this recipe is designed to prevent. Force the caller to commit
    -- to a number.
    local p_est = ctx.p_estimate
    if p_est == nil then
        error(
            "recipe_safe_panel: ctx.p_estimate is REQUIRED (no default). "
                .. "A silent fallback would bypass the Anti-Jury gate on "
                .. "tasks where the real p < 0.5. Run a small pilot "
                .. "(sc.run at n=1 over a labeled sample) and feed "
                .. "condorcet.estimate_p() in, or pass an explicit value "
                .. "based on task difficulty.",
            2
        )
    end
    if type(p_est) ~= "number" or p_est <= 0 or p_est > 1 then
        error(string.format(
            "recipe_safe_panel: ctx.p_estimate must be a number in (0, 1], "
                .. "got %s",
            tostring(p_est)
        ), 2)
    end

    local target = ctx.target_accuracy or 0.95
    local max_n = ctx.max_n or 15
    local conf_threshold = ctx.confidence_threshold or 0.7
    local do_scaling = ctx.scaling_check ~= false
    local gen_tokens = ctx.gen_tokens or 400

    -- Majority vote requires an odd panel of >= 3. Enforcing this at the
    -- input boundary avoids silent odd-enforcement overriding max_n below.
    if type(max_n) ~= "number" or max_n < 3 then
        error(string.format(
            "recipe_safe_panel: max_n must be >= 3 for a meaningful majority "
                .. "vote panel (got %s). Use a direct single-agent call for "
                .. "smaller sizes.",
            tostring(max_n)
        ))
    end

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

    -- Caveat: Anti-Jury / coin-flip check.
    -- is_anti_jury returns true only for p < 0.5. We additionally treat
    -- p == 0.5 as abort-worthy: Condorcet at p = 0.5 gives majority = 0.5
    -- exactly, regardless of n, so adding agents is pure waste. Without
    -- this gate the recipe would fall through to optimal_n (which returns
    -- nil for p ≤ 0.5) → max_n fallback → silently run a useless panel.
    if p_est <= 0.5 then
        alc.log("error", string.format(
            "recipe_safe_panel: ABORT — p=%.2f ≤ 0.5. Majority vote cannot "
                .. "improve accuracy (p<0.5 degrades, p=0.5 stays at 0.5).",
            p_est
        ))

        local is_anti = p_est < 0.5
        local abort_reason
        if is_anti then
            abort_reason = string.format(
                "Anti-Jury: p=%.2f < 0.5. Condorcet Jury Theorem guarantees "
                    .. "that majority vote accuracy → 0 as N → ∞. "
                    .. "Do NOT use panel voting. Consider: "
                    .. "(1) improve individual agent quality, "
                    .. "(2) use expert routing instead of voting, "
                    .. "(3) use pairwise_rank for comparison-based selection.",
                p_est
            )
        else
            abort_reason = string.format(
                "Coin-flip: p=%.2f = 0.5. Majority vote accuracy is 0.5 for "
                    .. "every n — adding agents does nothing. Improve agent "
                    .. "quality before using any voting-based strategy.",
                p_est
            )
        end

        -- Emit the SAME result shape as the main path so consumers can
        -- read any field without branching on `aborted`. Voting-signal
        -- fields are zero/empty (no panel was run); safety fields reflect
        -- the abort.
        ctx.result = {
            answer = nil,
            confidence = 0,
            panel_size = 0,
            plurality_fraction = 0,
            margin_gap = 0,
            vote_counts = {},
            n_distinct_answers = 0,
            expected_accuracy = 0,
            target_met = false,
            is_safe = false,
            anti_jury = is_anti,
            aborted = true,
            needs_investigation = true,
            unanimous = false,
            total_llm_calls = 0,
            abort_reason = abort_reason,
            stages = { {
                name = is_anti and "condorcet_anti_jury"
                    or "condorcet_coin_flip",
                p_estimate = p_est,
                is_anti_jury = is_anti,
            } },
        }
        return ctx
    end

    -- Compute optimal panel size
    local recommended_n, optimal_prob = condorcet.optimal_n(p_est, target)

    -- Caveat: optimal_n returns nil when p <= 0.5 or target unreachable
    -- within the search ceiling. Anti-Jury above catches p < 0.5; here we
    -- handle p == 0.5 and unreachable-target cases by degrading to max_n.
    if recommended_n == nil then
        alc.log("warn", string.format(
            "recipe_safe_panel: optimal_n unreachable (p=%.2f, target=%.2f). "
                .. "Falling back to max_n=%d and reporting actual expected accuracy.",
            p_est, target, max_n
        ))
        recommended_n = max_n
        optimal_prob = nil
    end

    -- Caveat: correlation adjustment for low competence.
    -- 1.5x is a recipe-level HEURISTIC (see M.caveats) corresponding to
    -- intra-panel correlation ρ ≈ 0.2–0.3 under the effective-sample-size
    -- formula N_eff = N / (1 + (N-1)·ρ). Not a theorem.
    if p_est < 0.65 then
        local adjusted = math.ceil(recommended_n * 1.5)
        alc.log("info", string.format(
            "recipe_safe_panel: low p=%.2f, applying 1.5x correlation "
                .. "adjustment (heuristic, ρ≈0.2-0.3): %d → %d",
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

    -- Ensure odd for clean majority. If rounding up would exceed max_n, we
    -- must step down by 2 — but that is a silent accuracy reduction, so log
    -- it explicitly rather than absorbing the downgrade.
    if recommended_n % 2 == 0 then
        local bumped = recommended_n + 1
        if bumped > max_n then
            local downgraded = recommended_n - 1
            if downgraded < 3 then downgraded = 3 end
            alc.log("warn", string.format(
                "recipe_safe_panel: odd-enforcement cannot round up %d within "
                    .. "max_n=%d → downgrading to %d. Expected accuracy will "
                    .. "be lower than the capped-even target. Raise max_n to "
                    .. "%d to avoid this downgrade.",
                recommended_n, max_n, downgraded, bumped
            ))
            recommended_n = downgraded
        else
            recommended_n = bumped
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
    -- sc always emits total_llm_calls (2n reasoning+extract + 1 consensus);
    -- keep a conservative legacy fallback for pre-refactor sc versions.
    local sc_calls = sc_result.result.total_llm_calls
        or (2 * recommended_n + 1)
    total_llm_calls = total_llm_calls + sc_calls

    -- Analyze vote distribution
    local vote_info = analyze_votes(vote_counts, recommended_n)

    stages[2] = {
        name = "sc",
        panel_size = recommended_n,
        answer = answer,
        -- plurality_fraction: top-answer share (max_count / n).
        plurality_fraction = vote_info.plurality_fraction,
        -- margin_gap: strict (top - runner-up) / n. Zero on a top tie.
        margin_gap = vote_info.margin_gap,
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
        "recipe_safe_panel: Stage 2 — answer='%s', plurality=%.0f%% "
            .. "(gap=%.0f%%), %d distinct answers (%d calls)",
        tostring(answer):sub(1, 50),
        vote_info.plurality_fraction * 100,
        vote_info.margin_gap * 100,
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
        alc.log("info",
            "recipe_safe_panel: ═══ Stage 3/4 — vote-prefix stability "
                .. "(inverse_u on single-run prefix) ═══"
        )

        local inverse_u = require("inverse_u")

        -- Build accuracy proxy series from progressive vote subsets.
        -- votes[i] are normalized, so compare against answer_norm.
        local series = build_accuracy_proxy(votes, answer_norm or answer)

        if #series >= 3 then
            peak_info = inverse_u.detect(series)
            scaling_safe = not peak_info.is_declining

            if not scaling_safe then
                alc.log("warn", string.format(
                    "recipe_safe_panel: vote-prefix DECLINE DETECTED — the "
                        .. "progressive-majority series dropped from its peak "
                        .. "at point %d for %d consecutive steps. This is a "
                        .. "weak signal of panel instability, not a true "
                        .. "inverse-U; verify with independent re-runs.",
                    peak_info.peak_idx or 0,
                    peak_info.consecutive_drops or 0
                ))
            end

            stages[3] = {
                name = "vote_prefix_stability",
                signal_type = "single_run_prefix_proxy",
                series_length = #series,
                is_safe = scaling_safe,
                peak_idx = peak_info and peak_info.peak_idx,
                consecutive_drops = peak_info and peak_info.consecutive_drops,
            }
        else
            alc.log("info",
                "recipe_safe_panel: Stage 3 — insufficient data points "
                    .. "for prefix stability analysis"
            )
            -- Unify with the outer-else skip branch: when the series is
            -- too short for inverse_u.detect, Stage 3 is effectively
            -- skipped. Using the `_skipped` suffix lets consumers test
            -- `stages[3].name:find("skipped")` without also inspecting
            -- `series_length`.
            stages[3] = {
                name = "vote_prefix_stability_skipped",
                signal_type = "single_run_prefix_proxy",
                reason = string.format(
                    "insufficient data points (need series length >= 3, got %d)",
                    #series
                ),
                series_length = #series,
                is_safe = true,
            }
        end
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
            name = "vote_prefix_stability_skipped",
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
            .. "  Plurality: %.0f%% (%d/%d agents picked this answer)\n"
            .. "  Margin over runner-up: %.0f%%\n"
            .. "  Distinct answers: %d\n"
            .. "  Expected accuracy (Condorcet, p=%.2f): %.1f%%\n"
            .. "  Vote-prefix stability: %s\n\n"
            .. "Based on this information, how confident should we be "
            .. "in the panel's answer?",
        recommended_n,
        task,
        tostring(answer),
        vote_info.plurality_fraction * 100,
        vote_info.max_count,
        recommended_n,
        vote_info.margin_gap * 100,
        vote_info.n_distinct,
        p_est,
        expected_acc * 100,
        scaling_safe and "STABLE (no decline in prefix series)"
            or "UNSTABLE (prefix majority declined from its peak)"
    )

    -- Use calibrate.assess: the recipe consumes only the confidence reading
    -- and applies its own conf_threshold gate below via needs_investigation.
    -- calibrate.run's built-in escalation would be wrong here — its retry
    -- path does NOT reassess confidence, so it cannot improve the signal
    -- this recipe uses; previously we worked around that by forcing
    -- threshold=0 on calibrate.run, but assess() makes the intent explicit
    -- and removes the dead `fallback` parameter from the call site.
    local cal_result = calibrate.assess({
        task = cal_task,
        gen_tokens = 300,
    })

    local confidence = cal_result.result.confidence or 0.5
    local cal_calls = cal_result.result.total_llm_calls or 1
    total_llm_calls = total_llm_calls + cal_calls

    -- Recipe-level gate. calibrate.assess has no escalation concept, so
    -- escalation is necessarily absent here; the recipe decides on its own
    -- whether to surface `needs_investigation` based on conf_threshold.
    local needs_investigation = confidence < conf_threshold

    stages[4] = {
        name = "calibrate",
        confidence = confidence,
        threshold = conf_threshold,
        needs_investigation = needs_investigation,
        -- `escalated` kept false-valued for stages[] shape parity with
        -- earlier versions; assess() has no escalation path.
        escalated = false,
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
            .. "panel=%d, plurality=%.0f%% (gap=%.0f%%), %d total calls",
        tostring(answer):sub(1, 50),
        confidence,
        recommended_n,
        vote_info.plurality_fraction * 100,
        vote_info.margin_gap * 100,
        total_llm_calls
    ))

    ctx.result = {
        answer = answer,
        confidence = confidence,
        panel_size = recommended_n,
        plurality_fraction = vote_info.plurality_fraction,
        margin_gap = vote_info.margin_gap,
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

-- ─── Test hooks ───
-- Expose pure helpers for unit testing. Not part of the public API.
M._internal = {
    analyze_votes = analyze_votes,
    build_accuracy_proxy = build_accuracy_proxy,
}

return M
