--- Shape conformance test — static validation of producer declarations.
--- Verifies M.spec.entries.run.result declarations match alc_shapes
--- dictionary entries without requiring live LLM calls.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- NOTE: do not prepend os.getenv("PWD") to package.path here. Under the
-- mlua-probe-mcp test runner, PWD points to the main repo (the server CWD)
-- even when tests are launched from a worktree, so forcing PWD-first would
-- shadow search_paths and load stale pkg versions. search_paths is already
-- passed by the caller — rely on that.

package.loaded["alc_shapes"]         = nil
package.loaded["alc_shapes.t"]       = nil
package.loaded["alc_shapes.check"]   = nil
package.loaded["alc_shapes.reflect"] = nil
package.loaded["alc_shapes.luacats"] = nil

local S = require("alc_shapes")
local T = S.T

local DECLARED_PACKAGES = {
    { name = "sc",                     shape = "voted" },
    { name = "panel",                  shape = "paneled" },
    { name = "calibrate",              shape = "calibrated" },
    { name = "rank",                   shape = "tournament" },
    { name = "listwise_rank",          shape = "listwise_ranked" },
    { name = "pairwise_rank",          shape = "pairwise_ranked" },
    { name = "recipe_ranking_funnel",  shape = "funnel_ranked" },
    { name = "recipe_safe_panel",      shape = "safe_paneled" },
    { name = "recipe_quick_vote",      shape = "quick_voted" },
}

local function resolve_shape_name(result)
    if type(result) == "string" then
        return result
    end
    if type(result) == "table" and rawget(result, "kind") == "ref" then
        return rawget(result, "name")
    end
    return nil
end

describe("shape conformance: spec declarations", function()
    for _, entry in ipairs(DECLARED_PACKAGES) do
        describe(entry.name, function()
            package.loaded[entry.name] = nil
            local pkg = require(entry.name)

            it("declares result in spec.entries.run", function()
                expect(pkg.spec).to.exist()
                expect(pkg.spec.entries).to.exist()
                expect(pkg.spec.entries.run).to.exist()
                local name = resolve_shape_name(pkg.spec.entries.run.result)
                expect(name).to.equal(entry.shape)
            end)

            it("shape name exists in alc_shapes dictionary", function()
                local shape = S[entry.shape]
                expect(shape).to.exist()
                expect(type(shape)).to.equal("table")
                expect(rawget(shape, "kind")).to.equal("shape")
            end)

            it("shape has non-empty fields", function()
                local shape = S[entry.shape]
                local entries = S.fields(shape)
                expect(#entries > 0).to.equal(true)
            end)
        end)
    end
end)

describe("shape conformance: secondary entry points", function()
    it("calibrate.assess documents assessed shape", function()
        local shape = S.assessed
        expect(shape).to.exist()
        expect(rawget(shape, "kind")).to.equal("shape")
        local entries = S.fields(shape)
        local names = {}
        for _, e in ipairs(entries) do names[e.name] = true end
        expect(names.answer).to.equal(true)
        expect(names.confidence).to.equal(true)
        expect(names.total_llm_calls).to.equal(true)
    end)
end)

describe("shape conformance: shape validation against mock data", function()
    it("voted shape accepts well-formed sc result", function()
        local mock = {
            consensus = "Tokyo is the capital",
            answer = "Tokyo",
            answer_norm = "tokyo",
            paths = { { reasoning = "...", answer = "Tokyo" } },
            votes = { "tokyo" },
            vote_counts = { tokyo = 1 },
            n_sampled = 1,
            total_llm_calls = 3,
        }
        local ok, reason = S.check(mock, S.voted)
        expect(ok).to.equal(true)
    end)

    it("voted shape accepts result with nil answer (no convergence)", function()
        -- answer/answer_norm are optional at top level, but each path
        -- always has both reasoning and answer (extract_answer always
        -- returns a string even if unhelpful).
        local mock = {
            consensus = "No clear answer",
            paths = { { reasoning = "...", answer = "unclear" } },
            votes = { "" },
            vote_counts = {},
            n_sampled = 1,
            total_llm_calls = 3,
        }
        local ok = S.check(mock, S.voted)
        expect(ok).to.equal(true)
    end)

    it("voted shape rejects missing required field", function()
        local ok, reason = S.check({ consensus = "x" }, S.voted)
        expect(ok).to.equal(false)
        expect(reason:match("shape violation")).to.exist()
    end)

    it("paneled shape accepts well-formed panel result", function()
        local mock = {
            arguments = { { role = "advocate", text = "I argue..." } },
            synthesis = "The panel concludes...",
        }
        expect(S.check(mock, S.paneled)).to.equal(true)
    end)

    it("assessed shape accepts well-formed assess result", function()
        local mock = {
            answer = "42",
            confidence = 0.85,
            total_llm_calls = 1,
        }
        expect(S.check(mock, S.assessed)).to.equal(true)
    end)

    it("calibrated shape accepts direct (non-escalated) result", function()
        local mock = {
            answer = "42",
            confidence = 0.9,
            escalated = false,
            strategy = "direct",
            total_llm_calls = 1,
        }
        expect(S.check(mock, S.calibrated)).to.equal(true)
    end)

    it("calibrated shape accepts escalated result with fallback_detail", function()
        local mock = {
            answer = "Tokyo",
            confidence = 0.3,
            escalated = true,
            strategy = "ensemble",
            total_llm_calls = 12,
            fallback_detail = { consensus = "Tokyo" },
        }
        expect(S.check(mock, S.calibrated)).to.equal(true)
    end)

    it("calibrated shape rejects invalid strategy", function()
        local mock = {
            answer = "x",
            confidence = 0.5,
            escalated = true,
            strategy = "invalid_strategy",
            total_llm_calls = 2,
        }
        local ok, reason = S.check(mock, S.calibrated)
        expect(ok).to.equal(false)
        expect(reason:match("expected one of")).to.exist()
    end)

    it("tournament shape accepts well-formed rank result", function()
        local mock = {
            best = "Tokyo is the capital of Japan",
            best_index = 2,
            total_wins = 3,
            candidates = { "answer1", "answer2", "answer3", "answer4" },
            matches = {
                { a = 1, b = 2, winner = 2, reason = "B is more accurate" },
                { a = 3, b = 4, winner = 3, reason = "A is more complete" },
                { a = 2, b = 3, winner = 2, reason = "A is better overall" },
            },
        }
        expect(S.check(mock, S.tournament)).to.equal(true)
    end)

    it("tournament shape rejects missing matches", function()
        local mock = {
            best = "x",
            best_index = 1,
            total_wins = 1,
            candidates = { "x" },
        }
        local ok, reason = S.check(mock, S.tournament)
        expect(ok).to.equal(false)
        expect(reason:match("matches")).to.exist()
    end)

    it("listwise_ranked shape accepts well-formed result", function()
        local item = { rank = 1, index = 2, text = "best answer" }
        local mock = {
            ranked = { item },
            top_k = { item },
            killed = {},
            best = "best answer",
            best_index = 2,
            n_candidates = 3,
            total_llm_calls = 1,
        }
        expect(S.check(mock, S.listwise_ranked)).to.equal(true)
    end)

    it("pairwise_ranked shape accepts well-formed result", function()
        local item = { rank = 1, index = 1, score = 4, text = "top" }
        local mock = {
            ranked = { item },
            top_k = { item },
            killed = {},
            best = "top",
            best_index = 1,
            method = "allpair",
            score_semantics = "copeland",
            n_candidates = 3,
            total_llm_calls = 12,
            position_bias_splits = 0,
            both_tie_pairs = 1,
        }
        expect(S.check(mock, S.pairwise_ranked)).to.equal(true)
    end)

    it("pairwise_ranked rejects invalid method", function()
        local item = { rank = 1, index = 1, score = 0, text = "x" }
        local mock = {
            ranked = { item },
            top_k = { item },
            killed = {},
            best = "x",
            best_index = 1,
            method = "bubble",
            score_semantics = "copeland",
            n_candidates = 1,
            total_llm_calls = 0,
            position_bias_splits = 0,
            both_tie_pairs = 0,
        }
        local ok, reason = S.check(mock, S.pairwise_ranked)
        expect(ok).to.equal(false)
        expect(reason:match("expected one of")).to.exist()
    end)

    it("funnel_ranked shape accepts bypass result", function()
        local r_item = { rank = 1, text = "best", original_index = 2, pairwise_score = 4 }
        local mock = {
            ranking = { r_item },
            best = "best",
            best_index = 2,
            funnel_bypassed = true,
            bypass_reason = "N < 6",
            total_llm_calls = 6,
            naive_baseline_calls = 6,
            naive_baseline_kind = "bypass_direct_pairwise_allpair_bidirectional",
            warnings = {},
            stages = {
                { name = "listwise_skipped", input_count = 3, output_count = 3, llm_calls = 0, reason = "N < 6 bypass" },
                { name = "scoring_skipped", input_count = 3, output_count = 3, llm_calls = 0, reason = "survivors <= top_k2" },
                { name = "direct_pairwise", input_count = 3, output_count = 3, llm_calls = 6, position_bias_splits = 0, both_tie_pairs = 0 },
            },
            funnel_shape = { 3, 3, 3 },
        }
        expect(S.check(mock, S.funnel_ranked)).to.equal(true)
    end)

    it("funnel_ranked shape accepts main path result", function()
        local r_item = { rank = 1, text = "top", original_index = 5, pairwise_score = 8 }
        local mock = {
            ranking = { r_item },
            best = "top",
            best_index = 5,
            funnel_bypassed = false,
            total_llm_calls = 20,
            naive_baseline_calls = 150,
            naive_baseline_kind = "pairwise_rank_allpair_bidirectional",
            savings_percent = 86.7,
            warnings = {
                { code = "stage_2_parse_failure_rate_high", severity = "warn",
                  data = { rate = 0.4 }, message = "40% parse failures" },
            },
            stages = {
                { name = "listwise_rank", input_count = 20, output_count = 7, llm_calls = 5, window_size = 10 },
                { name = "multi_axis_scoring", input_count = 7, output_count = 5, llm_calls = 7, axes_count = 3, parse_failures = 2, score_range = { min = 2.0, max = 8.5 } },
                { name = "pairwise_rank_allpair", input_count = 5, output_count = 5, llm_calls = 8, position_bias_splits = 2, both_tie_pairs = 1 },
            },
            funnel_shape = { 20, 7, 5 },
        }
        expect(S.check(mock, S.funnel_ranked)).to.equal(true)
    end)

    it("safe_paneled shape accepts abort result", function()
        local mock = {
            confidence = 0,
            panel_size = 0,
            plurality_fraction = 0,
            margin_gap = 0,
            vote_counts = {},
            n_distinct_answers = 0,
            expected_accuracy = 0,
            target_met = false,
            is_safe = false,
            anti_jury = true,
            aborted = true,
            needs_investigation = true,
            unanimous = false,
            total_llm_calls = 0,
            abort_reason = "anti-jury detected",
            stages = { { name = "condorcet_anti_jury", p_estimate = 0.3, is_anti_jury = true } },
        }
        expect(S.check(mock, S.safe_paneled)).to.equal(true)
    end)

    it("safe_paneled shape accepts main path result", function()
        local mock = {
            answer = "Tokyo",
            confidence = 0.85,
            panel_size = 7,
            plurality_fraction = 0.71,
            margin_gap = 0.43,
            vote_counts = { tokyo = 5, osaka = 2 },
            n_distinct_answers = 2,
            expected_accuracy = 0.94,
            target_met = true,
            is_safe = true,
            anti_jury = false,
            aborted = false,
            needs_investigation = false,
            unanimous = false,
            total_llm_calls = 8,
            stages = {
                { name = "condorcet", p_estimate = 0.8, recommended_n = 7, expected_accuracy = 0.94, target_accuracy = 0.9, target_met = true },
                { name = "sc", panel_size = 7, answer = "Tokyo", plurality_fraction = 0.71, margin_gap = 0.43, n_distinct_answers = 2, unanimous = false, llm_calls = 7 },
                { name = "vote_prefix_stability", signal_type = "single_run_prefix_proxy", series_length = 7, is_safe = true, peak_idx = 3, consecutive_drops = 0 },
                { name = "calibrate", confidence = 0.85, threshold = 0.3, needs_investigation = false, escalated = false, llm_calls = 1 },
            },
        }
        expect(S.check(mock, S.safe_paneled)).to.equal(true)
    end)

    it("safe_paneled rejects missing required field", function()
        local ok, reason = S.check({ answer = "x", confidence = 0.5 }, S.safe_paneled)
        expect(ok).to.equal(false)
        expect(reason:match("shape violation")).to.exist()
    end)

    it("quick_voted shape accepts confirmed result", function()
        local mock = {
            answer      = "42",
            leader_norm = "42",
            outcome     = "confirmed",
            verdict     = "accept_h1",
            n_samples   = 8,
            vote_counts = { ["42"] = 8 },
            samples     = {
                { reasoning = "r1", answer = "42", norm = "42" },
            },
            sprt = { log_lr = 3.29, n = 7, a_bound = 2.89, b_bound = -2.25 },
            params = {
                p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10,
                min_n = 3, max_n = 10,
            },
            total_llm_calls     = 16,
            needs_investigation = false,
        }
        expect(S.check(mock, S.quick_voted)).to.equal(true)
    end)

    it("quick_voted shape accepts rejected result", function()
        local mock = {
            answer      = "42",
            leader_norm = "42",
            outcome     = "rejected",
            verdict     = "accept_h0",
            n_samples   = 4,
            vote_counts = { ["42"] = 1, ["43"] = 3 },
            samples     = {},
            sprt = { log_lr = -2.75, n = 3, a_bound = 2.89, b_bound = -2.25 },
            params = {
                p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10,
                min_n = 3, max_n = 10,
            },
            total_llm_calls     = 8,
            needs_investigation = true,
        }
        expect(S.check(mock, S.quick_voted)).to.equal(true)
    end)

    it("quick_voted shape accepts truncated result", function()
        local mock = {
            answer      = "42",
            leader_norm = "42",
            outcome     = "truncated",
            verdict     = "continue",
            n_samples   = 5,
            vote_counts = { ["42"] = 3, ["43"] = 2 },
            samples     = {},
            sprt = { log_lr = -0.89, n = 4, a_bound = 2.89, b_bound = -2.25 },
            params = {
                p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10,
                min_n = 3, max_n = 5,
            },
            total_llm_calls     = 10,
            needs_investigation = true,
        }
        expect(S.check(mock, S.quick_voted)).to.equal(true)
    end)

    it("quick_voted rejects invalid outcome label", function()
        local mock = {
            answer = "42", leader_norm = "42",
            outcome = "unknown",   -- not in the one_of set
            verdict = "continue",
            n_samples = 1, vote_counts = { ["42"] = 1 }, samples = {},
            sprt = { log_lr = 0, n = 0, a_bound = 2.89, b_bound = -2.25 },
            params = {
                p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10,
                min_n = 3, max_n = 10,
            },
            total_llm_calls = 2, needs_investigation = true,
        }
        local ok, reason = S.check(mock, S.quick_voted)
        expect(ok).to.equal(false)
        expect(reason:match("expected one of")).to.exist()
    end)

    it("all shapes tolerate extra fields (open=true)", function()
        local shapes = {
            S.voted, S.paneled, S.assessed, S.calibrated,
            S.tournament, S.listwise_ranked, S.pairwise_ranked,
            S.funnel_ranked, S.safe_paneled, S.quick_voted,
        }
        for _, shape in ipairs(shapes) do
            expect(rawget(shape, "open")).to.equal(true)
        end
    end)
end)
