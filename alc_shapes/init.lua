--- alc_shapes — SSoT for the result shape convention.
---
--- Usage:
---   local S = require("alc_shapes")
---   local ok, reason = S.check(value, S.voted)
---   local x = S.assert(value, "voted", "where")
---
--- Core concept: Schema-as-Data (after Malli's TypeSchemaAsData doctrine).
--- Schemas are plain kind-tagged Lua tables. They are the single AST used
--- by every consumer (validator / reflector / codegen / docs projector)
--- and are persistable without loss — JSON-encode, JSON-decode, still
--- valid. Metatables carry combinator sugar only; `rawget` is the
--- universal reader. Parallel representations (e.g. a separate "TypeExpr"
--- AST) are prohibited: downstream consumers must project, not mirror.
--- See README.md §Core concept.
---
--- NOTE: meta.result_shape is a single string today. Packages with
--- multiple entry points (e.g. calibrate.run vs calibrate.assess)
--- declare the primary shape in meta and document secondary shapes
--- in docstrings. A future `meta.shapes("key")` accessor is a
--- possible extension — tracked in design.md §将来検討.

local T = require("alc_shapes.t")
local check = require("alc_shapes.check")
local reflect = require("alc_shapes.reflect")
local luacats = require("alc_shapes.luacats")

local M = {}

-- ── shape dictionary ─────────────────────────────────────────────────

M.voted = T.shape({
    consensus       = T.string:describe("LLM-synthesized majority summary"),
    answer          = T.string:is_optional():describe("Majority answer (nil when no paths converge)"),
    answer_norm     = T.string:is_optional():describe("Normalized vote key"),
    paths           = T.array_of(T.shape({
        reasoning = T.string,
        answer    = T.string,
    })):describe("Per-path reasoning + extracted answer"),
    votes           = T.array_of(T.string):describe("Normalized vote per path, 1-indexed"),
    vote_counts     = T.map_of(T.string, T.number):describe("{ [norm] = count } tally"),
    n_sampled       = T.number:describe("Number of sampled paths"),
    total_llm_calls = T.number,
}, { open = true })

M.paneled = T.shape({
    arguments = T.array_of(T.shape({
        role = T.string,
        text = T.string,
    })):describe("Per-role position statements"),
    synthesis = T.string:describe("Moderator synthesis"),
}, { open = true })

M.assessed = T.shape({
    answer          = T.string,
    confidence      = T.number:describe("Self-assessed confidence 0.0–1.0"),
    total_llm_calls = T.number,
}, { open = true })

M.calibrated = T.shape({
    answer          = T.string,
    confidence      = T.number:describe("Initial self-assessed confidence"),
    escalated       = T.boolean:describe("Whether fallback was triggered"),
    strategy        = T.one_of({ "direct", "retry", "panel", "ensemble" }),
    total_llm_calls = T.number,
    fallback_detail = T.table:is_optional():describe("Fallback strategy result (voted/paneled)"),
}, { open = true })

-- ── ranking shapes ───────────────────────────────────────────────────

local ranked_item_3 = T.shape({
    rank  = T.number,
    index = T.number,
    text  = T.string,
})

local ranked_item_4 = T.shape({
    rank  = T.number,
    index = T.number,
    score = T.number,
    text  = T.string,
})

M.tournament = T.shape({
    best        = T.string:describe("Winner text"),
    best_index  = T.number:describe("Winner original index (1-based)"),
    total_wins  = T.number:describe("Winner's win count"),
    candidates  = T.array_of(T.string):describe("Input candidate texts"),
    matches     = T.array_of(T.shape({
        a      = T.number:describe("Index of first candidate"),
        b      = T.number:describe("Index of second candidate"),
        winner = T.number:describe("Index of the winner"),
        reason = T.string:describe("Judge verdict explanation"),
    })):describe("Pairwise match log"),
}, { open = true })

M.listwise_ranked = T.shape({
    ranked      = T.array_of(ranked_item_3):describe("Full ranking"),
    top_k       = T.array_of(ranked_item_3):describe("Top-k subset"),
    killed      = T.array_of(ranked_item_3):describe("Eliminated candidates"),
    best        = T.string:describe("Top-ranked text"),
    best_index  = T.number:describe("Top-ranked original index (1-based)"),
    n_candidates    = T.number,
    total_llm_calls = T.number,
}, { open = true })

M.pairwise_ranked = T.shape({
    ranked      = T.array_of(ranked_item_4):describe("Full ranking with scores"),
    top_k       = T.array_of(ranked_item_4):describe("Top-k subset"),
    killed      = T.array_of(ranked_item_4):describe("Eliminated candidates"),
    best        = T.string:describe("Top-ranked text"),
    best_index  = T.number:describe("Top-ranked original index (1-based)"),
    method          = T.one_of({ "allpair", "sorting" }):describe("Comparison strategy"),
    score_semantics = T.one_of({ "copeland", "rank_inverse" }):describe("Score interpretation"),
    n_candidates        = T.number,
    total_llm_calls     = T.number,
    position_bias_splits = T.number:describe("Position-bias correction splits"),
    both_tie_pairs       = T.number:describe("Pairs that tied in both directions"),
}, { open = true })

-- ── recipe shapes ────────────────────────────────────────────────────

local funnel_stage = T.discriminated("name", {
    listwise_rank = T.shape({
        name         = T.one_of({ "listwise_rank" }),
        input_count  = T.number,
        output_count = T.number,
        llm_calls    = T.number,
        window_size  = T.number,
    }),
    listwise_skipped = T.shape({
        name         = T.one_of({ "listwise_skipped" }),
        input_count  = T.number,
        output_count = T.number,
        llm_calls    = T.number,
        reason       = T.string,
    }),
    multi_axis_scoring = T.shape({
        name           = T.one_of({ "multi_axis_scoring" }),
        input_count    = T.number,
        output_count   = T.number,
        llm_calls      = T.number,
        axes_count     = T.number,
        parse_failures = T.number,
        score_range    = T.shape({ min = T.number, max = T.number }),
    }),
    scoring_skipped = T.shape({
        name         = T.one_of({ "scoring_skipped" }),
        input_count  = T.number,
        output_count = T.number,
        llm_calls    = T.number,
        reason       = T.string,
    }),
    pairwise_rank_allpair = T.shape({
        name                 = T.one_of({ "pairwise_rank_allpair" }),
        input_count          = T.number,
        output_count         = T.number,
        llm_calls            = T.number,
        position_bias_splits = T.number,
        both_tie_pairs       = T.number,
    }),
    direct_pairwise = T.shape({
        name                 = T.one_of({ "direct_pairwise" }),
        input_count          = T.number,
        output_count         = T.number,
        llm_calls            = T.number,
        position_bias_splits = T.number,
        both_tie_pairs       = T.number,
    }),
})

M.funnel_ranked = T.shape({
    ranking     = T.array_of(T.shape({
        rank           = T.number,
        text           = T.string,
        original_index = T.number:describe("Pre-funnel candidate index (1-based)"),
        pairwise_score = T.number:describe("Copeland score from pairwise stage"),
    })):describe("Final ranking"),
    best            = T.string:describe("Top-ranked text"),
    best_index      = T.number:describe("Top-ranked original index (1-based)"),
    funnel_bypassed = T.boolean:describe("True when N < 6 bypasses funnel stages"),
    bypass_reason   = T.string:is_optional():describe("Reason for bypass (nil when not bypassed)"),
    total_llm_calls     = T.number,
    naive_baseline_calls = T.number:describe("Hypothetical full-pairwise call count"),
    naive_baseline_kind  = T.string:describe("Baseline method identifier"),
    savings_percent = T.number:is_optional():describe("LLM call savings vs baseline (nil on bypass)"),
    warnings        = T.array_of(T.shape({
        code     = T.string:describe("Machine-readable warning identifier"),
        severity = T.one_of({ "warn", "critical" }),
        data     = T.table:describe("Diagnostic payload (structure varies by code)"),
        message  = T.string:describe("Human-readable summary"),
    })):describe("Diagnostic warnings"),
    stages       = T.array_of(funnel_stage):describe("Per-stage detail (discriminated by name)"),
    funnel_shape = T.array_of(T.number):describe("Candidate counts per stage [N, s1_out, s2_out]"),
}, { open = true })

local safe_panel_stage = T.discriminated("name", {
    condorcet = T.shape({
        name              = T.one_of({ "condorcet" }),
        p_estimate        = T.number,
        recommended_n     = T.number,
        expected_accuracy = T.number,
        target_accuracy   = T.number,
        target_met        = T.boolean,
    }),
    condorcet_anti_jury = T.shape({
        name         = T.one_of({ "condorcet_anti_jury" }),
        p_estimate   = T.number,
        is_anti_jury = T.boolean,
    }),
    condorcet_coin_flip = T.shape({
        name         = T.one_of({ "condorcet_coin_flip" }),
        p_estimate   = T.number,
        is_anti_jury = T.boolean,
    }),
    sc = T.shape({
        name               = T.one_of({ "sc" }),
        panel_size         = T.number,
        answer             = T.string,
        plurality_fraction = T.number,
        margin_gap         = T.number,
        n_distinct_answers = T.number,
        unanimous          = T.boolean,
        llm_calls          = T.number,
    }),
    vote_prefix_stability = T.shape({
        name              = T.one_of({ "vote_prefix_stability" }),
        signal_type       = T.string,
        series_length     = T.number,
        is_safe           = T.boolean,
        peak_idx          = T.number,
        consecutive_drops = T.number,
    }),
    vote_prefix_stability_skipped = T.shape({
        name          = T.one_of({ "vote_prefix_stability_skipped" }),
        signal_type   = T.string,
        reason        = T.string,
        series_length = T.number,
        is_safe       = T.boolean,
    }),
    calibrate = T.shape({
        name                = T.one_of({ "calibrate" }),
        confidence          = T.number,
        threshold           = T.number,
        needs_investigation = T.boolean,
        escalated           = T.boolean,
        llm_calls           = T.number,
    }),
})

M.safe_paneled = T.shape({
    answer       = T.string:is_optional():describe("Consensus answer (nil on abort)"),
    confidence   = T.number:describe("Meta-confidence estimate"),
    panel_size   = T.number:describe("Actual panel size used"),
    plurality_fraction = T.number:describe("Top-answer vote fraction"),
    margin_gap   = T.number:describe("(top - runner_up) / n"),
    vote_counts  = T.map_of(T.string, T.number):describe("{ [normalized_answer] = count } tally"),
    n_distinct_answers = T.number:describe("Count of unique answers"),
    expected_accuracy  = T.number:describe("Condorcet expected majority accuracy"),
    target_met         = T.boolean:describe("Whether expected accuracy >= target"),
    is_safe            = T.boolean:describe("Vote-prefix stability safe flag"),
    anti_jury          = T.boolean:describe("Condorcet anti-jury detection"),
    aborted            = T.boolean:describe("True if early-abort triggered"),
    needs_investigation = T.boolean:describe("True if meta-confidence below threshold"),
    unanimous          = T.boolean:describe("All votes identical"),
    total_llm_calls    = T.number,
    abort_reason       = T.string:is_optional():describe("Abort reason (nil when not aborted)"),
    stages             = T.array_of(safe_panel_stage):describe("Per-stage detail (discriminated by name)"),
}, { open = true })

-- ── public API re-export ─────────────────────────────────────────────
M.check        = check.check
M.assert       = check.assert
M.assert_dev   = check.assert_dev
M.is_dev_mode  = check.is_dev_mode
M.fields       = reflect.fields
M.walk         = reflect.walk

-- Combinator namespace (so callers can write `S.T.string` without a
-- separate require).
M.T = T

-- Codegen namespace (used by scripts/gen_shapes_luacats.lua).
M.LuaCats = luacats

-- ── reserved-name guard ──────────────────────────────────────────────
-- Certain names collide with `check.assert` shortcut semantics:
--   `M.assert(v, "any")` is always a no-op pass-through. Registering a
-- shape under such a name would silently shadow the shortcut (check.lua).
-- tableshape / Zod avoid this by namespace-separating built-ins from user
-- schemas; we enforce the same invariant via a load-time loud-fail.
-- Re-exported functions / combinator namespaces (M.T, M.LuaCats, etc.)
-- are not shape-kind and therefore never trip this check.
-- See workspace/tasks/shape-convention/design.md §P0 修正メモ Q3.
local RESERVED_SHAPE_NAMES = { "any" }

local function assert_no_reserved_shapes(mod)
    for i = 1, #RESERVED_SHAPE_NAMES do
        local name = RESERVED_SHAPE_NAMES[i]
        local v = rawget(mod, name)
        if type(v) == "table" and rawget(v, "kind") == "shape" then
            error(string.format(
                "alc_shapes: '%s' is reserved (assert shortcut); cannot register a shape under this name",
                name), 2)
        end
    end
end

assert_no_reserved_shapes(M)

M._internal = {
    assert_no_reserved_shapes = assert_no_reserved_shapes,
    RESERVED_SHAPE_NAMES      = RESERVED_SHAPE_NAMES,
}

return M
