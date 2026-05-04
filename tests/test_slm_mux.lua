--- Tests for slm_mux (SLM-MUX subset selection) package.
--- Pure computation — no LLM mocking needed.
---
--- Reference: Wang et al. "SLM-MUX: Orchestrating Small Language
--- Models for Reasoning" (arXiv:2510.05077, ICLR 2026 Poster).

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function reset()
    package.loaded["slm_mux"] = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Toy fixture: 3 SLM × 5 question, paper §3.2 hand-computed reference.
-- ═══════════════════════════════════════════════════════════════════
--
-- correct:    q1=A   q2=B   q3=C   q4=D   q5=E
-- SLM_1 y*:   A      B      X      X      X       (correct on q1,q2 → a_1=0.4)
-- SLM_2 y*:   A      Y      C      Y      Y       (correct on q1,q3 → a_2=0.4)
-- SLM_3 y*:   Z      Z      Z      D      E       (correct on q4,q5 → a_3=0.4)
--
-- Hand-computed objective values (λ=1.0, threshold=0):
--   S = {1,2}: UA = 3/5 = 0.6, Con = 2/5 = 0.4, 𝒪 = 0.2  ← best
--   S = {1,3}: UA = 4/5 = 0.8, Con = 4/5 = 0.8, 𝒪 = 0.0
--   S = {2,3}: UA = 4/5 = 0.8, Con = 4/5 = 0.8, 𝒪 = 0.0
--
-- Singletons (K=1 subsets, no Contradiction since |S|=1 needs both
-- a wrong-consistent AND a correct in S):
--   S = {1}: UA = 0.4, Con = 0,   𝒪 = 0.4
--   S = {2}: UA = 0.4, Con = 0,   𝒪 = 0.4
--   S = {3}: UA = 0.4, Con = 0,   𝒪 = 0.4

local TOY = {
    {
        samples = {
            { "A", "A", "B" },  -- q1 → A
            { "B", "B", "X" },  -- q2 → B
            { "X", "X", "C" },  -- q3 → X
            { "X", "X", "D" },  -- q4 → X
            { "X", "X", "E" },  -- q5 → X
        },
        correct = { "A", "B", "C", "D", "E" },
    },
    {
        samples = {
            { "A", "A", "Z" },  -- q1 → A
            { "Y", "Y", "B" },  -- q2 → Y
            { "C", "C", "Y" },  -- q3 → C
            { "Y", "Y", "D" },  -- q4 → Y
            { "Y", "Y", "E" },  -- q5 → Y
        },
        correct = { "A", "B", "C", "D", "E" },
    },
    {
        samples = {
            { "Z", "Z", "A" },  -- q1 → Z
            { "Z", "Z", "B" },  -- q2 → Z
            { "Z", "Z", "C" },  -- q3 → Z
            { "D", "D", "Z" },  -- q4 → D
            { "E", "E", "Z" },  -- q5 → E
        },
        correct = { "A", "B", "C", "D", "E" },
    },
}

local function approx_eq(a, b, eps)
    eps = eps or 1e-9
    if math.abs(a - b) <= eps then return true end
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- meta
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local mux = require("slm_mux")
        expect(mux.meta.name).to.equal("slm_mux")
    end)

    it("has version 0.1.0", function()
        local mux = require("slm_mux")
        expect(mux.meta.version).to.equal("0.1.0")
    end)

    it("category is selection", function()
        local mux = require("slm_mux")
        expect(mux.meta.category).to.equal("selection")
    end)

    it("description mentions SLM-MUX paper", function()
        local mux = require("slm_mux")
        expect(mux.meta.description:find("SLM-MUX") ~= nil
            or mux.meta.description:find("2510.05077") ~= nil
            or mux.meta.description:find("Wang") ~= nil).to.equal(true)
    end)

    it("exposes confidence/score_subset/select_subset/inference_select/run", function()
        local mux = require("slm_mux")
        expect(type(mux.confidence)).to.equal("function")
        expect(type(mux.score_subset)).to.equal("function")
        expect(type(mux.select_subset)).to.equal("function")
        expect(type(mux.inference_select)).to.equal("function")
        expect(type(mux.run)).to.equal("function")
    end)

    it("has paper-faithful defaults", function()
        local mux = require("slm_mux")
        expect(mux._defaults.lambda).to.equal(1.0)
        expect(mux._defaults.search_method).to.equal("exhaustive")
        expect(mux._defaults.consistency_threshold).to.equal(0.0)
        expect(mux._defaults.s_tie_break).to.equal("validation_accuracy")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- confidence (§3.1 Algorithm 1 Lines 6-12, single model)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.confidence positive", function()
    lust.after(reset)

    it("unanimous samples → s = 1.0", function()
        local mux = require("slm_mux")
        local r = mux.confidence({ "A", "A", "A" })
        expect(r.y_star).to.equal("A")
        expect(r.s).to.equal(1.0)
        expect(r.k).to.equal(3)
    end)

    it("majority samples → s = max_count / k", function()
        local mux = require("slm_mux")
        local r = mux.confidence({ "A", "A", "B" })
        expect(r.y_star).to.equal("A")
        expect(approx_eq(r.s, 2 / 3)).to.equal(true)
    end)

    it("single sample → s = 1.0", function()
        local mux = require("slm_mux")
        local r = mux.confidence({ "X" })
        expect(r.y_star).to.equal("X")
        expect(r.s).to.equal(1.0)
        expect(r.k).to.equal(1)
    end)
end)

describe("slm_mux.confidence errors", function()
    lust.after(reset)

    it("empty samples errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.confidence({})
        end).to.fail()
    end)

    it("non-string samples errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.confidence({ "A", 1, "B" })
        end).to.fail()
    end)

    it("non-table samples errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.confidence("A")
        end).to.fail()
    end)
end)

describe("slm_mux.confidence edge", function()
    lust.after(reset)

    it("tie default lexicographic resolves to lex-min", function()
        local mux = require("slm_mux")
        local r = mux.confidence({ "B", "A" })
        -- both freq=1, tie; lexicographic → "A"
        expect(r.y_star).to.equal("A")
        expect(r.s).to.equal(0.5)
    end)

    it("tie with first_in_samples resolves to first occurrence", function()
        local mux = require("slm_mux")
        local r = mux.confidence({ "B", "A" }, { tie_break_yi = "first_in_samples" })
        expect(r.y_star).to.equal("B")
    end)

    it("tie with deterministic rng resolves to picked index", function()
        local mux = require("slm_mux")
        -- With rng() always returning 0, math.floor(0 * 2) + 1 = 1 → first sorted
        local r = mux.confidence({ "B", "A" },
            { tie_break_yi = "uniform_random", rng = function() return 0 end })
        expect(r.y_star).to.exist()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- score_subset (§3.2 𝒪 = UnionAcc − λ·Contradiction)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.score_subset positive", function()
    lust.after(reset)

    it("toy S={1,2}: UA=0.6, Con=0.4, 𝒪=0.2", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 2 })
        expect(approx_eq(r.union_acc, 0.6)).to.equal(true)
        expect(approx_eq(r.contradiction, 0.4)).to.equal(true)
        expect(approx_eq(r.objective, 0.2)).to.equal(true)
    end)

    it("toy S={1,3}: UA=0.8, Con=0.8, 𝒪=0.0", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 3 })
        expect(approx_eq(r.union_acc, 0.8)).to.equal(true)
        expect(approx_eq(r.contradiction, 0.8)).to.equal(true)
        expect(approx_eq(r.objective, 0.0)).to.equal(true)
    end)

    it("toy S={2,3}: UA=0.8, Con=0.8, 𝒪=0.0", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 2, 3 })
        expect(approx_eq(r.union_acc, 0.8)).to.equal(true)
        expect(approx_eq(r.contradiction, 0.8)).to.equal(true)
        expect(approx_eq(r.objective, 0.0)).to.equal(true)
    end)

    it("singleton S={1}: UA=0.4, Con=0, 𝒪=0.4", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1 })
        expect(approx_eq(r.union_acc, 0.4)).to.equal(true)
        expect(approx_eq(r.contradiction, 0.0)).to.equal(true)
        expect(approx_eq(r.objective, 0.4)).to.equal(true)
    end)

    it("full subset S={1,2,3}: UA=1.0", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 2, 3 })
        expect(approx_eq(r.union_acc, 1.0)).to.equal(true)
    end)
end)

describe("slm_mux.score_subset invariants", function()
    lust.after(reset)

    it("UnionAcc ∈ [0, 1]", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 2, 3 })
        expect(r.union_acc >= 0).to.equal(true)
        expect(r.union_acc <= 1).to.equal(true)
    end)

    it("Contradiction ∈ [0, 1]", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 2, 3 })
        expect(r.contradiction >= 0).to.equal(true)
        expect(r.contradiction <= 1).to.equal(true)
    end)

    it("𝒪 = UnionAcc − λ · Contradiction (λ=2.0)", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 3 }, { lambda = 2.0 })
        -- UA=0.8, Con=0.8, λ=2 → 𝒪 = 0.8 - 1.6 = -0.8
        expect(approx_eq(r.objective, r.union_acc - 2.0 * r.contradiction)).to.equal(true)
        expect(approx_eq(r.objective, -0.8)).to.equal(true)
    end)

    it("λ=0 → 𝒪 = UnionAcc", function()
        local mux = require("slm_mux")
        local r = mux.score_subset(TOY, { 1, 3 }, { lambda = 0 })
        expect(approx_eq(r.objective, r.union_acc)).to.equal(true)
    end)
end)

describe("slm_mux.score_subset errors", function()
    lust.after(reset)

    it("profiles with mismatched M errors", function()
        local mux = require("slm_mux")
        local bad = {
            { samples = { { "A" }, { "B" } }, correct = { "A", "B" } },
            { samples = { { "A" } },          correct = { "A" } },     -- different M
        }
        expect(function()
            mux.score_subset(bad, { 1, 2 })
        end).to.fail()
    end)

    it("subset_indices out of range errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.score_subset(TOY, { 1, 4 })
        end).to.fail()
    end)

    it("duplicate subset_indices errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.score_subset(TOY, { 1, 1 })
        end).to.fail()
    end)

    it("consistency_threshold > 1 errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.score_subset(TOY, { 1, 2 }, { consistency_threshold = 1.5 })
        end).to.fail()
    end)

    it("negative lambda errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.score_subset(TOY, { 1, 2 }, { lambda = -0.1 })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- select_subset (§3.2 K-subset search)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.select_subset positive (paper-faithful)", function()
    lust.after(reset)

    it("toy K=2 → best subset {1,2}", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2)
        -- {1,2} is the unique max with 𝒪=0.2
        expect(#r.selected_indices).to.equal(2)
        expect(r.selected_indices[1]).to.equal(1)
        expect(r.selected_indices[2]).to.equal(2)
        expect(approx_eq(r.objective, 0.2)).to.equal(true)
    end)

    it("toy K=2 returns search_log of size C(3,2)=3", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2)
        expect(#r.search_log).to.equal(3)
    end)

    it("toy K=1 returns 1 element subset", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 1)
        expect(#r.selected_indices).to.equal(1)
        expect(approx_eq(r.objective, 0.4)).to.equal(true)
        expect(#r.search_log).to.equal(3)  -- all singletons evaluated
    end)

    it("toy K=N=3 returns full subset", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 3)
        expect(#r.selected_indices).to.equal(3)
        expect(#r.search_log).to.equal(1)
    end)

    it("search_method='exhaustive' is default and recorded in result", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2)
        expect(r.search_method).to.equal("exhaustive")
    end)

    it("lambda echoed in result", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2, { lambda = 0.5 })
        expect(r.lambda).to.equal(0.5)
    end)
end)

describe("slm_mux.select_subset NOT paper-faithful", function()
    lust.after(reset)

    it("greedy_forward returns a valid K-subset", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2, { search_method = "greedy_forward" })
        expect(#r.selected_indices).to.equal(2)
        expect(r.search_method).to.equal("greedy_forward")
    end)

    it("greedy_backward returns a valid K-subset", function()
        local mux = require("slm_mux")
        local r = mux.select_subset(TOY, 2, { search_method = "greedy_backward" })
        expect(#r.selected_indices).to.equal(2)
        expect(r.search_method).to.equal("greedy_backward")
    end)

    it("unknown search_method errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.select_subset(TOY, 2, { search_method = "cheating" })
        end).to.fail()
    end)
end)

describe("slm_mux.select_subset edge", function()
    lust.after(reset)

    it("k > N errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.select_subset(TOY, 4)
        end).to.fail()
    end)

    it("k = 0 errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.select_subset(TOY, 0)
        end).to.fail()
    end)

    it("subset_tie_break='lexicographic_on_indices' picks lex-min on tie", function()
        local mux = require("slm_mux")
        -- Three identical profiles → all subsets have same 𝒪.
        local p = TOY[1]
        local same = { p, p, p }
        local r = mux.select_subset(same, 2, { subset_tie_break = "lexicographic_on_indices" })
        expect(r.selected_indices[1]).to.equal(1)
        expect(r.selected_indices[2]).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- inference_select (§3.1 Algorithm 1 end)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.inference_select positive", function()
    lust.after(reset)

    it("unique max s → that model wins", function()
        local mux = require("slm_mux")
        local r = mux.inference_select({
            { y_star = "A", s = 1.0,  validation_accuracy = 0.5 },
            { y_star = "B", s = 0.66, validation_accuracy = 0.7 },
        })
        expect(r.selected_model_idx).to.equal(1)
        expect(r.selected_y).to.equal("A")
        expect(r.tie_size).to.equal(1)
        expect(r.tie_break_used).to.equal("no_tie")
    end)

    it("s tie → argmax validation_accuracy wins (paper §3.1)", function()
        local mux = require("slm_mux")
        local r = mux.inference_select({
            { y_star = "X", s = 0.66, validation_accuracy = 0.4 },
            { y_star = "Y", s = 0.66, validation_accuracy = 0.7 },
            { y_star = "Z", s = 0.66, validation_accuracy = 0.5 },
        })
        expect(r.selected_model_idx).to.equal(2)
        expect(r.selected_y).to.equal("Y")
        expect(r.tie_size).to.equal(3)
        expect(r.tie_break_used).to.equal("validation_accuracy")
    end)

    it("complete tie (s + a_i) → first_found (validation_accuracy path)", function()
        local mux = require("slm_mux")
        local r = mux.inference_select({
            { y_star = "X", s = 0.5, validation_accuracy = 0.5 },
            { y_star = "Y", s = 0.5, validation_accuracy = 0.5 },
        })
        expect(r.selected_model_idx).to.equal(1)
        expect(r.tie_break_used).to.equal("validation_accuracy")
    end)

    it("missing validation_accuracy treated as 0", function()
        local mux = require("slm_mux")
        local r = mux.inference_select({
            { y_star = "A", s = 0.66 },
            { y_star = "B", s = 0.66, validation_accuracy = 0.1 },
        })
        expect(r.selected_model_idx).to.equal(2)
        expect(r.tie_break_used).to.equal("validation_accuracy")
    end)

    it("s tie + all validation_accuracy nil → first_found_fallback_no_validation_accuracy", function()
        local mux = require("slm_mux")
        local r = mux.inference_select({
            { y_star = "X", s = 0.66 },
            { y_star = "Y", s = 0.66 },
            { y_star = "Z", s = 0.66 },
        })
        expect(r.tie_break_used).to.equal("first_found_fallback_no_validation_accuracy")
        expect(r.selected_model_idx).to.equal(1)
        expect(r.tie_size).to.equal(3)
    end)
end)

describe("slm_mux.inference_select errors", function()
    lust.after(reset)

    it("empty input errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.inference_select({})
        end).to.fail()
    end)

    it("missing s errors", function()
        local mux = require("slm_mux")
        expect(function()
            mux.inference_select({ { y_star = "A" } })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- run (alias of select_subset)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux.run", function()
    lust.after(reset)

    it("run is equivalent to select_subset for the same args", function()
        local mux = require("slm_mux")
        local rs = mux.select_subset(TOY, 2)
        local rr = mux.run(TOY, 2)
        expect(rs.selected_indices[1]).to.equal(rr.selected_indices[1])
        expect(rs.selected_indices[2]).to.equal(rr.selected_indices[2])
        expect(approx_eq(rs.objective, rr.objective)).to.equal(true)
    end)

    it("run accepts opts pass-through", function()
        local mux = require("slm_mux")
        local r = mux.run(TOY, 2, { lambda = 0 })
        expect(r.lambda).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Internal helpers (numerical hand-checks)
-- ═══════════════════════════════════════════════════════════════════

describe("slm_mux._internal", function()
    lust.after(reset)

    it("enumerate_subsets(3,2) yields {1,2}, {1,3}, {2,3}", function()
        local mux = require("slm_mux")
        local got = {}
        for s in mux._internal.enumerate_subsets(3, 2) do
            got[#got + 1] = table.concat(s, ",")
        end
        expect(got[1]).to.equal("1,2")
        expect(got[2]).to.equal("1,3")
        expect(got[3]).to.equal("2,3")
        expect(#got).to.equal(3)
    end)

    it("enumerate_subsets(4,2) yields C(4,2)=6", function()
        local mux = require("slm_mux")
        local count = 0
        for _ in mux._internal.enumerate_subsets(4, 2) do count = count + 1 end
        expect(count).to.equal(6)
    end)

    it("enumerate_subsets(5,3) yields C(5,3)=10", function()
        local mux = require("slm_mux")
        local count = 0
        for _ in mux._internal.enumerate_subsets(5, 3) do count = count + 1 end
        expect(count).to.equal(10)
    end)

    it("union_acc on toy S={1,2} = 0.6", function()
        local mux = require("slm_mux")
        local ua, _ = mux._internal.union_acc(TOY, { 1, 2 }, {})
        expect(approx_eq(ua, 0.6)).to.equal(true)
    end)

    it("contradiction on toy S={1,3} = 0.8", function()
        local mux = require("slm_mux")
        local cn, _ = mux._internal.contradiction(TOY, { 1, 3 }, {})
        expect(approx_eq(cn, 0.8)).to.equal(true)
    end)

    it("compute_validation_accuracy returns 0.4 for each toy SLM", function()
        local mux = require("slm_mux")
        for i = 1, 3 do
            local a = mux._internal.compute_validation_accuracy(
                TOY[i], "lexicographic", "error", nil)
            expect(approx_eq(a, 0.4)).to.equal(true)
        end
    end)
end)
