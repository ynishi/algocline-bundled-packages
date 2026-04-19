--- recipe_deep_panel — Deep-reasoning diverse panel with resume
---
--- Recipe package: composes ab_mcts × N + ensemble_div + condorcet +
--- calibrate on top of flow. Fills the gap between recipe_safe_panel
--- (cheap sc-based majority vote) and single-agent ab_mcts: when each
--- individual opinion requires tree-search-quality reasoning AND the
--- panel is large enough to need checkpoint-resume, this recipe is
--- the right composition.
---
--- Pipeline:
---   Stage 1: condorcet — Panel feasibility + Anti-Jury gate
---     Same gate as recipe_safe_panel: if p_estimate <= 0.5, majority
---     vote is provably harmful (anti-jury) or useless (coin-flip).
---     Aborts with zero LLM cost when the gate blocks.
---
---   Stage 2: flow fan-out of ab_mcts — N independent tree searches
---     Uses flow.state_new + per-branch flow.state_get to checkpoint
---     each ab_mcts invocation. A crash mid-panel resumes at the first
---     incomplete branch. Each branch is a full ab_mcts run (2*budget+1
---     LLM calls in the NeurIPS 2025 Spotlight formula), differentiated
---     by a distinct approach-prompt. flow.token_wrap / token_verify
---     tag each call with a unique slot so a mis-routed response across
---     parallel branches is detected at the Frame boundary.
---
---   Stage 3: ensemble_div — Panel diversity diagnostic
---     3a (always): answer-level distinctness on normalized answers
---          (n_distinct / n). This is a structural diversity signal.
---     3b (conditional): when ctx.ground_truth is numeric AND every
---          branch's answer parses as a number, call
---          ensemble_div.decompose to verify E = E_bar - A_bar and
---          report A_bar (ambiguity) on the numeric predictions.
---          Skipped with an explicit reason for non-numeric tasks —
---          see M.caveats.
---
---   Stage 4: condorcet.prob_majority — Expected panel accuracy
---     Plurality vote + Condorcet expected-accuracy under independence
---     at the declared p_estimate. Feeds into Stage 5.
---
---   Stage 5: calibrate.assess — Meta-confidence gate
---     Single-call assessment given panel summary (answer, plurality,
---     expected_acc, diversity). Recipe-level needs_investigation flag
---     fires when confidence < ctx.confidence_threshold.
---
--- Theory:
---   Inoue et al. "Wider or Deeper? Scaling LLM Inference-Time Compute
---     with Adaptive Branching Tree Search". NeurIPS 2025 Spotlight,
---     arXiv:2503.04412. AB-MCTS replaces UCB1 with Thompson Sampling
---     on Beta posteriors and adds a GEN node to decide between wider
---     (new candidate) and deeper (refine existing).
---
---   Condorcet, M. "Essai sur l'application de l'analyse à la
---     probabilité des décisions rendues à la pluralité des voix",
---     1785. Anti-Jury corollary: p < 0.5 ⇒ P(Maj_n) → 0 as n → ∞.
---
---   Krogh, Vedelsby. "Neural Network Ensembles, Cross Validation,
---     and Active Learning". NeurIPS 7, pp.231-238, 1995. Eq. 6:
---     E = E_bar - A_bar (ambiguity identity, independence-free).
---
---   Wang et al. "Self-Consistency Improves Chain of Thought Reasoning
---     in Language Models". 2022. arXiv:2203.11171. Justifies
---     majority-vote aggregation over diverse reasoning paths.
---
--- Caveats:
---   See M.caveats. Key: anti-jury abort, cost explosion with N×budget,
---   resume replay semantics, ensemble_div numeric-only Stage 3b.
---
--- Usage:
---   local deep_panel = require("recipe_deep_panel")
---   return deep_panel.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.task_id (required): Stable id for flow state persistence — the
---     checkpoint is keyed on this. Resuming an interrupted run requires
---     passing the same task_id with ctx.resume = true.
--- ctx.p_estimate (required): Per-agent accuracy in (0, 1]. REQUIRED
---     with no default: a silent default (e.g. 0.7) would bypass the
---     Anti-Jury gate on tasks where the real p < 0.5.
--- ctx.n_branches: Panel size (default: 3). Must be odd and >= 3 for
---     a meaningful majority vote.
--- ctx.budget: Per-branch ab_mcts budget (default: 8). Total LLM cost
---     is approximately N × (2*budget + 1) + 1 (calibrate).
--- ctx.max_depth: Per-branch ab_mcts max tree depth (default: 3).
--- ctx.approaches: Array of reasoning-style prompts, one per branch
---     (default: recipe-provided diverse set, up to 7). When
---     n_branches exceeds the default list length, ctx.approaches
---     MUST be provided explicitly.
--- ctx.resume: Set true to resume an interrupted run (default: false).
--- ctx.ground_truth: Optional number — enables ensemble_div.decompose
---     in Stage 3b. Only meaningful for numeric-answer tasks.
--- ctx.answer_normalizer: Optional callable string → string. Used for
---     vote bucketing (default: trim + lower).
--- ctx.confidence_threshold: calibrate gate threshold (default: 0.7).
--- ctx.gen_tokens: Max tokens per LLM call (default: 400).

local M = {}

---@type AlcMeta
M.meta = {
    name = "recipe_deep_panel",
    version = "0.1.0",
    description = "Deep-reasoning diverse panel — N × ab_mcts (Thompson "
        .. "Sampling tree search) fan-out via flow (resume-safe), followed "
        .. "by ensemble_div diversity diagnostic, condorcet expected-accuracy, "
        .. "and calibrate meta-confidence. The heavy-compute counterpart of "
        .. "recipe_safe_panel (which uses sc instead of ab_mcts).",
    category = "recipe",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            result = "deep_paneled",
        },
    },
}

--- Packages composed by this recipe, in execution order.
M.ingredients = {
    "flow",          -- Substrate: state + token + resume
    "condorcet",     -- Stage 1 + Stage 4: anti-jury gate + expected accuracy
    "ab_mcts",       -- Stage 2: per-branch tree-search reasoning (fan-out)
    "ensemble_div",  -- Stage 3b: ambiguity decomposition (numeric tasks only)
    "calibrate",     -- Stage 5: meta-confidence gate
}

--- Known failure conditions discovered through design review.
M.caveats = {
    "p_estimate <= 0.5 (Anti-Jury / coin-flip) makes majority vote "
        .. "provably useless or harmful — Condorcet (1785) guarantees "
        .. "P(Maj_n) → 0 as n → ∞ when p < 0.5, and exactly 0.5 for "
        .. "every n when p = 0.5"
        .. " → recipe ABORTs at Stage 1 with zero LLM cost; consumers "
        .. "receive the unified result shape with aborted = true.",
    "Cost grows as N × (2*budget + 1) + 1 — at N=3, budget=8 this is "
        .. "52 LLM calls; at N=5, budget=8 it is 86. This is 10×+ the "
        .. "cost of recipe_safe_panel (which uses sc at ~2*n+2 calls)"
        .. " → use this recipe ONLY when per-branch tree-search reasoning "
        .. "is actually needed. For cheap factual voting, prefer "
        .. "recipe_safe_panel.",
    "Resume replays Stage 5 (calibrate.assess) unconditionally — the "
        .. "recipe only checkpoints Stage 2 branches, not the final "
        .. "confidence assessment. A crash after Stage 2 completes but "
        .. "before Stage 5 finishes will re-issue the calibrate call on "
        .. "resume (one extra LLM call)"
        .. " → this is deliberate: calibrate.assess is cheap (1 call) "
        .. "and its prompt depends on the final panel summary, which is "
        .. "trivial to rebuild from persisted branches. If you need "
        .. "strict Stage-5 idempotence, persist the confidence before "
        .. "returning in your own wrapper.",
    "ab_mcts is non-deterministic (Thompson Sampling) — two runs with "
        .. "the same task and budget may produce different answers. "
        .. "Resume invariance is per-BRANCH: a branch completed in run 1 "
        .. "stays in the state; a branch started fresh in run 2 samples "
        .. "independently"
        .. " → treat resume as 'skip completed branches', not as "
        .. "'deterministic restart of the entire pipeline'.",
    "Resume with changed run parameters is REJECTED by flow 0.2.0+: "
        .. "the recipe passes identity = { task, n_branches, budget, "
        .. "max_depth } to flow.state_new, and flow compares it to the "
        .. "persisted checkpoint on resume. A mismatch raises an error "
        .. "from flow.state_new — no silent panel-parameter drift"
        .. " → to change any of those parameters mid-run, pass a fresh "
        .. "ctx.task_id (or ctx.resume=false) so a new checkpoint is "
        .. "created. Note that ctx.approaches is intentionally NOT part "
        .. "of identity: each branch's approach is pinned into "
        .. "branches[bkey].approach when that branch runs, so approach "
        .. "drift for not-yet-run branches is allowed. Legacy "
        .. "checkpoints written by flow 0.1.0 (no persisted identity) "
        .. "are accepted with a warning for one-migration-release "
        .. "backward compatibility.",
    "Stage 3b (ensemble_div.decompose) only fires when ctx.ground_truth "
        .. "is a number AND every branch answer parses as a number. For "
        .. "free-form text answers the decomposition has no sensible "
        .. "meaning (V^a must be a prediction of a numeric target)"
        .. " → Stage 3a (answer distinctness) always runs and provides a "
        .. "structural diversity signal; Stage 3b is optional. Users who "
        .. "want ensemble_div on text should embed their own grader "
        .. "upstream and pass scalar scores as pseudo-answers.",
    "ctx.approaches controls per-branch diversification. Identical "
        .. "approach strings across branches collapse the panel into "
        .. "correlated runs, violating Condorcet's independence "
        .. "assumption and degrading the Stage 4 expected-accuracy "
        .. "guarantee"
        .. " → the recipe asserts that ctx.approaches has no duplicates "
        .. "before dispatch; the default set is pre-checked.",
    "Slot verification runs at the Frame boundary on every "
        .. "ab_mcts.run return, BUT as of flow 0.1.0 no bundled pkg "
        .. "(ab_mcts included) has opted in to the v1 Frame contract "
        .. "(flow/doc/contract.md). flow.token_verify is fail-open: a "
        .. "result without _flow_token / _flow_slot passes verification; "
        .. "only a PRESENT-but-MISMATCHED echo fails"
        .. " → against the real ab_mcts, per-branch token verification "
        .. "degenerates to 'boundary-verified only' (no cross-branch "
        .. "mis-routing detection). Strict verification kicks in only "
        .. "after ab_mcts applies the migration diff in contract.md. "
        .. "The token tampering test in tests/test_recipe_deep_panel.lua "
        .. "uses a stub that echoes tokens and therefore exercises the "
        .. "flow layer itself, not the real ab_mcts integration.",
    "needs_investigation is a recipe-level flag, not a hard abort. "
        .. "When confidence < confidence_threshold the recipe still "
        .. "returns the panel answer — it just marks the result for "
        .. "human or downstream review"
        .. " → consumers who want a hard-abort semantics should check "
        .. "needs_investigation themselves and raise on true.",
}

--- Default reasoning-style approaches. Seven distinct angles cover
--- n_branches up to 7 without requiring the caller to supply a list.
--- Beyond 7 the caller must pass ctx.approaches explicitly (otherwise
--- the recipe errors rather than silently duplicating).
local DEFAULT_APPROACHES = {
    "analytical / first-principles reasoning, working top-down from "
        .. "fundamental constraints",
    "pragmatic / empirical reasoning, working bottom-up from known "
        .. "working examples and real-world constraints",
    "contrarian / devil's-advocate, actively searching for hidden "
        .. "assumptions and failure modes",
    "historical / precedent-driven, anchoring on how similar problems "
        .. "were solved in documented cases",
    "systems / holistic, mapping second-order effects and interactions "
        .. "before proposing a local decision",
    "empirical / data-driven, prioritizing measurable evidence over "
        .. "theoretical elegance",
    "inverted / worst-case, deriving the answer by first enumerating "
        .. "what NOT to do",
}

--- Empirical verification status.
---
--- The Stage 1 abort path and the Stage 3a distinctness path are
--- exercised by the accompanying smoke-test (tests/test_recipe_deep_panel.lua)
--- with mocked alc.llm / ab_mcts.run. Stages 2 (real ab_mcts fan-out),
--- 3b (ensemble_div.decompose on numeric answers), and 5 (calibrate on
--- real LLM) require a full e2e run with real backends; those slots
--- are marked not_exercised until such a run is captured.
---
--- Shape contract mirrors recipe_safe_panel.M.verified.stage_coverage:
---   status ∈ { "verified", "not_exercised", "theoretical_only" }
---   evidence = array of run_id strings; empty when not_exercised.
M.verified = {
    theoretical_basis = {
        "Inoue et al. NeurIPS 2025 Spotlight (arXiv:2503.04412): "
            .. "AB-MCTS with Thompson Sampling outperforms UCB1-MCTS "
            .. "and repeated sampling on inference-time scaling.",
        "Condorcet Jury Theorem (1785): P(Maj_n) → 1 as n → ∞ when "
            .. "p > 0.5 under independence; Anti-Jury when p < 0.5.",
        "Krogh-Vedelsby (NeurIPS 1995 Eq. 6): E = E_bar - A_bar holds "
            .. "identically without an independence assumption.",
        "Wang et al. 2022 (arXiv:2203.11171): majority-vote over "
            .. "diverse reasoning paths lifts accuracy via "
            .. "self-consistency.",
    },
    stage_coverage = {
        {
            stage = 1,
            name = "condorcet_gate",
            status = "verified",
            evidence = { "smoke:anti_jury_abort" },
        },
        {
            stage = 2,
            name = "flow_fanout_ab_mcts",
            status = "not_exercised",
            reason = "Smoke test stubs ab_mcts.run so the real "
                .. "Thompson-sampling tree search is not exercised; "
                .. "integration between flow.state_set/token_verify "
                .. "and real ab_mcts requires an e2e run.",
            to_verify = "run recipe_deep_panel end-to-end against a "
                .. "real alc.llm with ab_mcts un-mocked (budget=4, "
                .. "n_branches=3); confirm each branch's answer is "
                .. "distinct and that a crash-and-resume skips the "
                .. "completed branches.",
            evidence = { "smoke:flow_fanout_with_stub_ab_mcts" },
        },
        {
            stage = 3,
            name = "ensemble_div",
            status = "not_exercised",
            reason = "Stage 3a distinctness is covered by smoke, but "
                .. "Stage 3b (ensemble_div.decompose on numeric "
                .. "answers with ground_truth) needs a numeric-task "
                .. "e2e run; the smoke test exercises only text "
                .. "answers.",
            to_verify = "run recipe_deep_panel with ctx.ground_truth "
                .. "set to a number and verify decomp.identity_holds "
                .. "and decomp.A_bar > 0 on non-unanimous panels.",
            evidence = { "smoke:stage3a_distinctness" },
        },
        {
            stage = 4,
            name = "condorcet_expected_accuracy",
            status = "verified",
            evidence = { "smoke:plurality_and_prob_majority" },
        },
        {
            stage = 5,
            name = "calibrate_assess",
            status = "not_exercised",
            reason = "Smoke test stubs calibrate.assess; confidence "
                .. "parsing under a real LLM self-assessment has not "
                .. "been captured.",
            to_verify = "run recipe_deep_panel end-to-end; confirm "
                .. "calibrate.assess returns a parsed confidence in "
                .. "[0, 1] and that needs_investigation fires when "
                .. "confidence < confidence_threshold.",
            evidence = { "smoke:stage5_with_stub_calibrate" },
        },
    },
    e2e_runs = {},
    alc_eval_runs = {},
}

-- ─── Internal helpers ───

local function default_normalizer(s)
    if type(s) ~= "string" then return tostring(s) end
    return (s:gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

--- Count votes, returning top-answer share and margin over runner-up.
local function tally_votes(answers, normalizer)
    local counts = {}
    local total = 0
    for _, raw in ipairs(answers) do
        local key = normalizer(raw)
        counts[key] = (counts[key] or 0) + 1
        total = total + 1
    end
    local top_key, top_count = nil, 0
    local runner_up = 0
    local n_distinct = 0
    for k, c in pairs(counts) do
        n_distinct = n_distinct + 1
        if c > top_count then
            runner_up = top_count
            top_key, top_count = k, c
        elseif c > runner_up then
            runner_up = c
        end
    end
    return {
        top_key = top_key,
        top_count = top_count,
        runner_up = runner_up,
        n_distinct = n_distinct,
        total = total,
        counts = counts,
        plurality_fraction = total > 0 and top_count / total or 0,
        margin_gap = total > 0 and (top_count - runner_up) / total or 0,
    }
end

--- Try to parse each answer as a number. Returns (nums, all_numeric).
local function try_parse_numbers(answers)
    local nums = {}
    for i, a in ipairs(answers) do
        if type(a) == "number" then
            nums[i] = a
        elseif type(a) == "string" then
            local m = a:match("(-?%d+%.?%d*)")
            local n = m and tonumber(m)
            if n == nil then return nil, false end
            nums[i] = n
        else
            return nil, false
        end
    end
    return nums, true
end

--- Assert ctx.approaches has no duplicate entries (duplicate prompts
--- collapse branches into correlated runs, defeating panel independence).
local function assert_unique_approaches(approaches)
    local seen = {}
    for i, a in ipairs(approaches) do
        if seen[a] then
            error(string.format(
                "recipe_deep_panel: ctx.approaches[%d] duplicates "
                    .. "ctx.approaches[%d] (%q). Duplicate approach "
                    .. "prompts collapse the panel into correlated "
                    .. "runs and violate Condorcet's independence "
                    .. "assumption. Use distinct prompts per branch.",
                i, seen[a], a), 2)
        end
        seen[a] = i
    end
end

-- ─── Main pipeline ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error(
        "recipe_deep_panel: ctx.task is required", 2)
    local task_id = ctx.task_id or error(
        "recipe_deep_panel: ctx.task_id is required (stable id for "
            .. "flow state persistence; required for resume)", 2)

    -- p_estimate is REQUIRED. A silent default would bypass the
    -- Anti-Jury gate exactly like recipe_safe_panel.
    local p_est = ctx.p_estimate
    if p_est == nil then
        error(
            "recipe_deep_panel: ctx.p_estimate is REQUIRED (no default). "
                .. "A silent fallback would bypass the Anti-Jury gate on "
                .. "tasks where the real p < 0.5. Run a pilot and feed "
                .. "condorcet.estimate_p() in, or pass an explicit value.",
            2)
    end
    if type(p_est) ~= "number" or p_est <= 0 or p_est > 1 then
        error(string.format(
            "recipe_deep_panel: ctx.p_estimate must be a number in "
                .. "(0, 1], got %s", tostring(p_est)), 2)
    end

    local n_branches = ctx.n_branches or 3
    if type(n_branches) ~= "number" or n_branches < 3
        or n_branches % 2 ~= 1 then
        error(string.format(
            "recipe_deep_panel: n_branches must be an odd number >= 3 "
                .. "for a meaningful majority vote (got %s). Use "
                .. "single-agent ab_mcts for smaller panels.",
            tostring(n_branches)), 2)
    end

    local budget = ctx.budget or 8
    local max_depth = ctx.max_depth or 3
    local conf_threshold = ctx.confidence_threshold or 0.7
    local gen_tokens = ctx.gen_tokens or 400
    local normalizer = ctx.answer_normalizer or default_normalizer
    local resume = ctx.resume or false

    local approaches = ctx.approaches
    if approaches == nil then
        if n_branches > #DEFAULT_APPROACHES then
            error(string.format(
                "recipe_deep_panel: n_branches=%d exceeds the default "
                    .. "approach list (%d). Pass ctx.approaches "
                    .. "explicitly with n_branches distinct prompts.",
                n_branches, #DEFAULT_APPROACHES), 2)
        end
        approaches = {}
        for i = 1, n_branches do approaches[i] = DEFAULT_APPROACHES[i] end
    end
    if #approaches ~= n_branches then
        error(string.format(
            "recipe_deep_panel: #ctx.approaches (%d) must equal "
                .. "n_branches (%d).", #approaches, n_branches), 2)
    end
    assert_unique_approaches(approaches)

    local stages = {}
    local total_llm_calls = 0

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 1: condorcet — Panel feasibility + Anti-Jury gate
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_deep_panel: ═══ Stage 1/5 — condorcet gate "
            .. "(p=%.2f, n=%d) ═══", p_est, n_branches))

    local condorcet = require("condorcet")

    if p_est <= 0.5 then
        local is_anti = p_est < 0.5
        local abort_reason
        if is_anti then
            abort_reason = string.format(
                "Anti-Jury: p=%.2f < 0.5. Condorcet Jury Theorem "
                    .. "guarantees majority-vote accuracy → 0 as N → ∞. "
                    .. "Do NOT run a deep panel. Consider: "
                    .. "(1) improve individual agent quality, "
                    .. "(2) route to an expert model, "
                    .. "(3) use pairwise_rank for comparison-based "
                    .. "selection.", p_est)
        else
            abort_reason = string.format(
                "Coin-flip: p=%.2f = 0.5. Majority vote accuracy is "
                    .. "0.5 for every n — a deep panel would burn "
                    .. "N × (2*budget+1) LLM calls for no signal. "
                    .. "Improve agent quality first.", p_est)
        end

        alc.log("error",
            "recipe_deep_panel: ABORT — " .. abort_reason)

        -- Same result shape as the main path so consumers can read
        -- any field without branching on `aborted`.
        ctx.result = {
            answer = nil,
            confidence = 0,
            panel_size = 0,
            n_branches_completed = 0,
            plurality_fraction = 0,
            margin_gap = 0,
            vote_counts = {},
            n_distinct_answers = 0,
            branches = {},
            expected_accuracy = 0,
            target_met = false,
            anti_jury = is_anti,
            aborted = true,
            needs_investigation = true,
            unanimous = false,
            diversity = nil,
            decomp = nil,
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

    stages[1] = {
        name = "condorcet_gate",
        p_estimate = p_est,
        is_anti_jury = false,
    }

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 2: flow fan-out — N × ab_mcts.run with resume
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", string.format(
        "recipe_deep_panel: ═══ Stage 2/5 — flow fan-out "
            .. "(N=%d, budget=%d, max_depth=%d) ═══",
        n_branches, budget, max_depth))

    local flow = require("flow")
    local ab_mcts = require("ab_mcts")

    local st = flow.state_new({
        key_prefix = "recipe_deep_panel",
        id         = task_id,
        identity   = {
            task       = task,
            n_branches = n_branches,
            budget     = budget,
            max_depth  = max_depth,
        },
        resume     = resume,
    })
    local tok = flow.token_issue(st)

    local branches = flow.state_get(st, "branches") or {}
    local ab_mcts_calls_per_branch = 2 * budget + 1

    for i = 1, n_branches do
        local bkey = "branch_" .. i
        if branches[bkey] == nil then
            local approach = approaches[i]
            local branch_task = string.format(
                "%s\n\n[Approach for this branch: %s]",
                task, approach)
            local req = flow.token_wrap(tok, {
                slot = bkey,
                payload = {
                    task       = branch_task,
                    budget     = budget,
                    max_depth  = max_depth,
                    gen_tokens = gen_tokens,
                },
            })
            local out = ab_mcts.run(req.payload)
            assert(flow.token_verify(tok, out, req),
                "recipe_deep_panel: branch " .. bkey
                    .. " token/slot mismatch — possible cross-branch "
                    .. "response routing error")
            local result = out.result or out
            branches[bkey] = {
                approach   = approach,
                answer     = result.answer,
                best_score = result.best_score,
                tree_stats = result.tree_stats,
            }
            flow.state_set(st, "branches", branches)
            flow.state_save(st)
            total_llm_calls = total_llm_calls + ab_mcts_calls_per_branch
        else
            alc.log("info", string.format(
                "recipe_deep_panel: %s already persisted — skipping "
                    .. "(resume)", bkey))
        end
    end

    -- Collect answers in canonical order.
    local answers = {}
    local scores = {}
    for i = 1, n_branches do
        local b = branches["branch_" .. i]
        answers[i] = b and b.answer
        scores[i] = b and b.best_score
    end

    stages[2] = {
        name = "flow_fanout_ab_mcts",
        n_branches = n_branches,
        budget = budget,
        max_depth = max_depth,
        branches = branches,
        llm_calls = total_llm_calls,
    }

    alc.log("info", string.format(
        "recipe_deep_panel: Stage 2 — %d branches complete (%d calls)",
        n_branches, total_llm_calls))

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 3: ensemble_div — diversity diagnostic
    -- ═══════════════════════════════════════════════════════════════
    local vote = tally_votes(answers, normalizer)
    local distinctness = n_branches > 0
        and vote.n_distinct / n_branches or 0

    alc.log("info", string.format(
        "recipe_deep_panel: ═══ Stage 3/5 — diversity "
            .. "(distinct=%d/%d=%.2f) ═══",
        vote.n_distinct, n_branches, distinctness))

    local decomp = nil
    local decomp_status
    local gt = ctx.ground_truth
    if type(gt) == "number" then
        local nums, all_numeric = try_parse_numbers(answers)
        if all_numeric and nums and #nums == n_branches then
            local ensemble_div = require("ensemble_div")
            decomp = ensemble_div.decompose(nums, gt)
            decomp_status = "computed"
            alc.log("info", string.format(
                "recipe_deep_panel: Stage 3b — E=%.4f, E_bar=%.4f, "
                    .. "A_bar=%.4f (identity_holds=%s)",
                decomp.E, decomp.E_bar, decomp.A_bar,
                tostring(decomp.identity_holds)))
        else
            decomp_status = "skipped: not all branch answers parse as numbers"
        end
    else
        decomp_status = "skipped: ctx.ground_truth not provided"
    end

    stages[3] = {
        name = "ensemble_div",
        n_distinct_answers = vote.n_distinct,
        distinctness = distinctness,
        unanimous = (vote.n_distinct == 1),
        decomp = decomp,
        decomp_status = decomp_status,
    }

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 4: condorcet.prob_majority — expected accuracy
    -- ═══════════════════════════════════════════════════════════════
    local expected_acc = condorcet.prob_majority(n_branches, p_est)
    stages[4] = {
        name = "condorcet_expected_accuracy",
        panel_size = n_branches,
        p_estimate = p_est,
        plurality_fraction = vote.plurality_fraction,
        margin_gap = vote.margin_gap,
        expected_accuracy = expected_acc,
    }

    -- Pick the plurality answer from the ORIGINAL (un-normalized) set
    -- so callers see the raw text. When multiple raw answers share the
    -- same normalized key, the first occurrence wins.
    local plurality_answer = nil
    for i = 1, n_branches do
        if answers[i] ~= nil
            and normalizer(answers[i]) == vote.top_key then
            plurality_answer = answers[i]
            break
        end
    end

    alc.log("info", string.format(
        "recipe_deep_panel: Stage 4 — plurality=%.0f%% (gap=%.0f%%), "
            .. "expected_acc=%.3f",
        vote.plurality_fraction * 100,
        vote.margin_gap * 100,
        expected_acc))

    -- ═══════════════════════════════════════════════════════════════
    -- Stage 5: calibrate.assess — meta-confidence
    -- ═══════════════════════════════════════════════════════════════
    alc.log("info", "recipe_deep_panel: ═══ Stage 5/5 — calibrate ═══")

    local calibrate = require("calibrate")

    local diversity_line
    if decomp then
        diversity_line = string.format(
            "Diversity: %d distinct answers; A_bar=%.4f, "
                .. "identity_holds=%s (Krogh-Vedelsby)",
            vote.n_distinct, decomp.A_bar,
            tostring(decomp.identity_holds))
    else
        diversity_line = string.format(
            "Diversity: %d distinct answers (distinctness=%.2f); "
                .. "numeric decomposition not applicable",
            vote.n_distinct, distinctness)
    end

    local cal_task = string.format(
        "A panel of %d independent deep-reasoning agents "
            .. "(each running AB-MCTS tree search) voted on the "
            .. "following task:\n"
            .. "Task: %s\n\n"
            .. "Panel result:\n"
            .. "  Answer: %s\n"
            .. "  Plurality: %.0f%% (%d/%d agents picked this answer)\n"
            .. "  Margin over runner-up: %.0f%%\n"
            .. "  %s\n"
            .. "  Expected accuracy (Condorcet, p=%.2f): %.1f%%\n\n"
            .. "Based on this information, how confident should we be "
            .. "in the panel's answer?",
        n_branches, task,
        tostring(plurality_answer),
        vote.plurality_fraction * 100,
        vote.top_count, n_branches,
        vote.margin_gap * 100,
        diversity_line,
        p_est, expected_acc * 100)

    local cal_result = calibrate.assess({
        task = cal_task,
        gen_tokens = 300,
    })
    local cal_out = cal_result.result or cal_result
    local confidence = cal_out.confidence or 0.5
    local cal_calls = cal_out.total_llm_calls or 1
    total_llm_calls = total_llm_calls + cal_calls

    local needs_investigation = confidence < conf_threshold

    stages[5] = {
        name = "calibrate_assess",
        confidence = confidence,
        threshold = conf_threshold,
        needs_investigation = needs_investigation,
        llm_calls = cal_calls,
    }

    alc.log("info", string.format(
        "recipe_deep_panel: Stage 5 — confidence=%.2f (%s, threshold=%.2f)",
        confidence,
        needs_investigation and "NEEDS INVESTIGATION" or "OK",
        conf_threshold))

    -- Persist final summary for observability on resume.
    flow.state_set(st, "result_summary", {
        answer = plurality_answer,
        confidence = confidence,
        plurality_fraction = vote.plurality_fraction,
        margin_gap = vote.margin_gap,
        expected_accuracy = expected_acc,
    })
    flow.state_save(st)

    alc.log("info", string.format(
        "recipe_deep_panel: DONE — answer=%q, confidence=%.2f, "
            .. "panel=%d, plurality=%.0f%% (gap=%.0f%%), %d total calls",
        tostring(plurality_answer):sub(1, 50),
        confidence, n_branches,
        vote.plurality_fraction * 100,
        vote.margin_gap * 100,
        total_llm_calls))

    ctx.result = {
        answer = plurality_answer,
        confidence = confidence,
        panel_size = n_branches,
        n_branches_completed = n_branches,
        plurality_fraction = vote.plurality_fraction,
        margin_gap = vote.margin_gap,
        vote_counts = vote.counts,
        n_distinct_answers = vote.n_distinct,
        branches = branches,
        expected_accuracy = expected_acc,
        target_met = expected_acc >= (ctx.target_accuracy or 0),
        anti_jury = false,
        aborted = false,
        needs_investigation = needs_investigation,
        unanimous = (vote.n_distinct == 1),
        diversity = {
            n_distinct = vote.n_distinct,
            distinctness = distinctness,
            decomp_status = decomp_status,
        },
        decomp = decomp,
        total_llm_calls = total_llm_calls,
        stages = stages,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    tally_votes = tally_votes,
    try_parse_numbers = try_parse_numbers,
    default_normalizer = default_normalizer,
    DEFAULT_APPROACHES = DEFAULT_APPROACHES,
}

-- Malli-style self-decoration: asserts ret.result against the "deep_paneled"
-- shape alias when ALC_SHAPE_CHECK=1. Alias must be registered under
-- alc_shapes (see recipe_safe_panel's "safe_paneled" for precedent).
M.run = require("alc_shapes").instrument(M, "run")

return M
