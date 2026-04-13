--- Tests for foundation theory packages (bft, condorcet, ensemble_div,
--- inverse_u, cost_pareto, eval_guard).
--- Pure computation — no LLM mocking needed.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ═══════════════════════════════════════════════════════════════════
-- bft (F1 — Lamport-Shostak-Pease 1982)
-- ═══════════════════════════════════════════════════════════════════

describe("bft", function()
    local bft = require("bft")

    describe("validate", function()
        it("accepts n=4, f=1 (3*1+1=4)", function()
            local ok, _ = bft.validate(4, 1)
            expect(ok).to.equal(true)
        end)

        it("rejects n=3, f=1 (3*1+1=4 > 3)", function()
            local ok, _ = bft.validate(3, 1)
            expect(ok).to.equal(false)
        end)

        it("accepts n=7, f=2 (3*2+1=7)", function()
            local ok, _ = bft.validate(7, 2)
            expect(ok).to.equal(true)
        end)

        it("accepts f=0 for any n>=1", function()
            local ok, _ = bft.validate(1, 0)
            expect(ok).to.equal(true)
        end)
    end)

    describe("threshold", function()
        it("returns 2f+1 for valid configs", function()
            expect(bft.threshold(4, 1)).to.equal(3)
            expect(bft.threshold(7, 2)).to.equal(5)
            expect(bft.threshold(10, 3)).to.equal(7)
        end)

        it("returns 1 for f=0", function()
            expect(bft.threshold(3, 0)).to.equal(1)
        end)

        it("errors on invalid config", function()
            expect(function() bft.threshold(3, 1) end).to.fail()
        end)
    end)

    describe("max_faults", function()
        it("computes floor((n-1)/3)", function()
            expect(bft.max_faults(1)).to.equal(0)
            expect(bft.max_faults(3)).to.equal(0)
            expect(bft.max_faults(4)).to.equal(1)
            expect(bft.max_faults(7)).to.equal(2)
            expect(bft.max_faults(10)).to.equal(3)
        end)
    end)

    describe("signed messages", function()
        it("validate_signed accepts n=3, f=1 (f+2=3)", function()
            local ok, _ = bft.validate_signed(3, 1)
            expect(ok).to.equal(true)
        end)

        it("validate_signed rejects n=2, f=1 (f+2=3 > 2)", function()
            local ok, _ = bft.validate_signed(2, 1)
            expect(ok).to.equal(false)
        end)

        it("signed_threshold returns f+1", function()
            expect(bft.signed_threshold(3, 1)).to.equal(2)
            expect(bft.signed_threshold(5, 2)).to.equal(3)
        end)

        it("max_faults_signed returns n-2", function()
            expect(bft.max_faults_signed(5)).to.equal(3)
            expect(bft.max_faults_signed(2)).to.equal(0)
        end)
    end)

    describe("summary", function()
        it("returns all fields for n=7, f=2", function()
            local s = bft.summary(7, 2)
            expect(s.n).to.equal(7)
            expect(s.f).to.equal(2)
            expect(s.oral_ok).to.equal(true)
            expect(s.oral_quorum).to.equal(5)
            expect(s.signed_ok).to.equal(true)
            expect(s.signed_quorum).to.equal(3)
            expect(s.max_f_oral).to.equal(2)
            expect(s.max_f_signed).to.equal(5)
        end)
    end)

    describe("input validation", function()
        it("errors on non-integer n", function()
            expect(function() bft.validate(3.5, 1) end).to.fail()
        end)
        it("errors on negative f", function()
            expect(function() bft.validate(4, -1) end).to.fail()
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- condorcet (F3 — Condorcet 1785)
-- ═══════════════════════════════════════════════════════════════════

describe("condorcet", function()
    local condorcet = require("condorcet")

    describe("prob_majority", function()
        it("returns 1.0 for p=1.0", function()
            local p = condorcet.prob_majority(5, 1.0)
            expect(math.abs(p - 1.0) < 1e-10).to.equal(true)
        end)

        it("returns 0.0 for p=0.0", function()
            local p = condorcet.prob_majority(5, 0.0)
            expect(math.abs(p) < 1e-10).to.equal(true)
        end)

        it("returns 0.5 for p=0.5 (coin flip)", function()
            local p = condorcet.prob_majority(5, 0.5)
            expect(math.abs(p - 0.5) < 1e-6).to.equal(true)
        end)

        it("P(Maj_5, p=0.7) ~ 0.8369 (known value)", function()
            -- C(5,3)*0.7^3*0.3^2 + C(5,4)*0.7^4*0.3 + C(5,5)*0.7^5
            -- = 10*0.343*0.09 + 5*0.2401*0.3 + 0.16807
            -- = 0.3087 + 0.36015 + 0.16807 = 0.83692
            local p = condorcet.prob_majority(5, 0.7)
            expect(math.abs(p - 0.83692) < 0.001).to.equal(true)
        end)

        it("increases with n when p > 0.5", function()
            local p3 = condorcet.prob_majority(3, 0.6)
            local p5 = condorcet.prob_majority(5, 0.6)
            local p9 = condorcet.prob_majority(9, 0.6)
            expect(p5 > p3).to.equal(true)
            expect(p9 > p5).to.equal(true)
        end)

        it("decreases with n when p < 0.5 (Anti-Jury)", function()
            local p3 = condorcet.prob_majority(3, 0.4)
            local p5 = condorcet.prob_majority(5, 0.4)
            local p9 = condorcet.prob_majority(9, 0.4)
            expect(p5 < p3).to.equal(true)
            expect(p9 < p5).to.equal(true)
        end)
    end)

    describe("is_anti_jury", function()
        it("returns true for p < 0.5", function()
            local anti, _ = condorcet.is_anti_jury(0.4)
            expect(anti).to.equal(true)
        end)

        it("returns false for p > 0.5", function()
            local anti, _ = condorcet.is_anti_jury(0.7)
            expect(anti).to.equal(false)
        end)

        it("returns false for p = 0.5", function()
            local anti, _ = condorcet.is_anti_jury(0.5)
            expect(anti).to.equal(false)
        end)
    end)

    describe("optimal_n", function()
        it("finds n=1 for p=0.99, target=0.95", function()
            local n, _ = condorcet.optimal_n(0.99, 0.95)
            expect(n).to.equal(1)
        end)

        it("returns nil for p=0.4", function()
            local n, _ = condorcet.optimal_n(0.4, 0.95)
            expect(n).to.equal(nil)
        end)

        it("finds reasonable n for p=0.6, target=0.9", function()
            local n, prob = condorcet.optimal_n(0.6, 0.9)
            expect(n).to_not.equal(nil)
            expect(prob >= 0.9).to.equal(true)
            -- Verify n-2 doesn't meet target (minimality)
            if n > 1 then
                local prev = condorcet.prob_majority(n - 2, 0.6)
                expect(prev < 0.9).to.equal(true)
            end
        end)
    end)

    describe("correlation", function()
        it("returns 1.0 for identical vectors", function()
            local m, avg = condorcet.correlation({{1,2,3}, {1,2,3}})
            expect(math.abs(m[1][2] - 1.0) < 1e-6).to.equal(true)
            expect(math.abs(avg - 1.0) < 1e-6).to.equal(true)
        end)

        it("returns -1.0 for perfectly anti-correlated", function()
            local m, _ = condorcet.correlation({{1,2,3}, {3,2,1}})
            expect(math.abs(m[1][2] - (-1.0)) < 1e-6).to.equal(true)
        end)

        it("returns near 0 for uncorrelated", function()
            -- Orthogonal-ish vectors
            local m, _ = condorcet.correlation({{1,0,1,0}, {0,1,0,1}})
            expect(math.abs(m[1][2] - (-1.0)) < 1e-6).to.equal(true)
        end)

        it("errors on < 2 vectors", function()
            expect(function() condorcet.correlation({{1,2,3}}) end).to.fail()
        end)
    end)

    describe("estimate_p", function()
        it("estimates accuracy from numeric 0/1 outcomes", function()
            local p, ci = condorcet.estimate_p({1, 1, 1, 0, 1})
            expect(math.abs(p - 0.8) < 1e-6).to.equal(true)
            expect(ci > 0).to.equal(true)
        end)

        it("estimates accuracy from boolean outcomes", function()
            local p, ci = condorcet.estimate_p({true, true, false, true, true})
            expect(math.abs(p - 0.8) < 1e-6).to.equal(true)
            expect(ci > 0).to.equal(true)
        end)

        it("handles mixed boolean and numeric inputs", function()
            local p, _ = condorcet.estimate_p({true, 1, false, 0, true})
            expect(math.abs(p - 0.6) < 1e-6).to.equal(true)
        end)

        it("returns p=0 for all incorrect", function()
            local p, _ = condorcet.estimate_p({0, 0, 0, false, false})
            expect(math.abs(p) < 1e-6).to.equal(true)
        end)

        it("returns p=1 for all correct", function()
            local p, _ = condorcet.estimate_p({1, 1, true, true})
            expect(math.abs(p - 1.0) < 1e-6).to.equal(true)
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- ensemble_div (F4 — Krogh-Vedelsby 1995)
-- ═══════════════════════════════════════════════════════════════════

describe("ensemble_div", function()
    local ed = require("ensemble_div")

    describe("decompose", function()
        it("satisfies E = E_bar - A_bar identity", function()
            local r = ed.decompose({0.8, 0.6, 0.9}, 1.0)
            expect(r.identity_holds).to.equal(true)
            expect(math.abs(r.E - (r.E_bar - r.A_bar)) < 1e-10).to.equal(true)
        end)

        it("identity holds for varied scores", function()
            local r = ed.decompose({0.1, 0.5, 0.9, 0.3, 0.7}, 0.6)
            expect(r.identity_holds).to.equal(true)
        end)

        it("identity holds with non-uniform weights", function()
            local r = ed.decompose({0.2, 0.8, 0.5}, 0.4, {0.5, 0.3, 0.2})
            expect(r.identity_holds).to.equal(true)
        end)

        it("A_bar = 0 when all scores equal", function()
            local r = ed.decompose({0.7, 0.7, 0.7}, 1.0)
            expect(math.abs(r.A_bar) < 1e-10).to.equal(true)
            expect(r.identity_holds).to.equal(true)
        end)

        it("A_bar > 0 implies E < E_bar", function()
            local r = ed.decompose({0.5, 0.8, 0.3}, 0.6)
            expect(r.A_bar > 0).to.equal(true)
            expect(r.E < r.E_bar).to.equal(true)
        end)
    end)

    describe("ensemble", function()
        it("computes weighted average", function()
            local v = ed.ensemble({0.2, 0.8}, {0.5, 0.5})
            expect(math.abs(v - 0.5) < 1e-10).to.equal(true)
        end)

        it("computes uniform average by default", function()
            local v = ed.ensemble({0.3, 0.6, 0.9})
            expect(math.abs(v - 0.6) < 1e-10).to.equal(true)
        end)
    end)

    describe("ambiguity", function()
        it("is zero for identical scores", function()
            local a = ed.ambiguity({0.5, 0.5, 0.5})
            expect(math.abs(a) < 1e-10).to.equal(true)
        end)

        it("is positive for diverse scores", function()
            local a = ed.ambiguity({0.1, 0.5, 0.9})
            expect(a > 0).to.equal(true)
        end)
    end)

    describe("avg_error", function()
        it("computes correctly", function()
            -- scores = {1.0}, target = 0.0 => E_bar = 1.0
            local e = ed.avg_error({1.0}, 0.0)
            expect(math.abs(e - 1.0) < 1e-10).to.equal(true)
        end)
    end)

    describe("input validation", function()
        it("errors on empty scores", function()
            expect(function() ed.decompose({}, 1.0) end).to.fail()
        end)
        it("errors on mismatched weights", function()
            expect(function() ed.decompose({0.5, 0.5}, 1.0, {0.5}) end).to.fail()
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- inverse_u (N1 — Chen NeurIPS 2024)
-- ═══════════════════════════════════════════════════════════════════

describe("inverse_u", function()
    local iu = require("inverse_u")

    describe("detect", function()
        it("detects inverse-U pattern", function()
            local r = iu.detect({0.70, 0.75, 0.78, 0.76, 0.73})
            expect(r.trend).to.equal("inverse_u")
            expect(r.peak_idx).to.equal(3)
            expect(r.peak_acc).to.equal(0.78)
            expect(r.is_declining).to.equal(true)
            expect(r.consecutive_drops).to.equal(2)
        end)

        it("detects monotone increase", function()
            local r = iu.detect({0.60, 0.65, 0.70, 0.75})
            expect(r.trend).to.equal("monotone_up")
        end)

        it("detects monotone decrease", function()
            local r = iu.detect({0.80, 0.75, 0.70, 0.65})
            expect(r.trend).to.equal("monotone_down")
        end)

        it("detects flat", function()
            local r = iu.detect({0.70, 0.70, 0.70})
            expect(r.trend).to.equal("flat")
        end)

        it("handles single element", function()
            local r = iu.detect({0.70})
            expect(r.trend).to.equal("insufficient")
        end)
    end)

    describe("should_stop", function()
        it("stops on 2+ consecutive drops", function()
            local stop, _ = iu.should_stop({0.70, 0.75, 0.73, 0.71})
            expect(stop).to.equal(true)
        end)

        it("does not stop on single drop", function()
            local stop, _ = iu.should_stop({0.70, 0.75, 0.73})
            expect(stop).to.equal(false)
        end)

        it("does not stop on monotone increase", function()
            local stop, _ = iu.should_stop({0.60, 0.65, 0.70})
            expect(stop).to.equal(false)
        end)
    end)

    describe("chen_condition", function()
        it("predicts inverse-U when p1+p2>1 and alpha<1-1/t", function()
            -- p1=0.85, p2=0.4, alpha=0.4, t=10
            -- p1+p2=1.25>1, 1-1/10=0.9, alpha=0.4<0.9
            local inv, conds = iu.chen_condition(0.85, 0.4, 0.4, 10)
            expect(inv).to.equal(true)
            expect(conds.p_sum_gt_1).to.equal(true)
            expect(conds.alpha_lt_threshold).to.equal(true)
        end)

        it("does not predict when p1+p2<=1", function()
            local inv, _ = iu.chen_condition(0.5, 0.4, 0.3, 10)
            expect(inv).to.equal(false)
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- cost_pareto (N5 — Kapoor 2024)
-- ═══════════════════════════════════════════════════════════════════

describe("cost_pareto", function()
    local cp = require("cost_pareto")

    describe("dominates", function()
        it("warming dominates LATS (Kapoor Table 1)", function()
            -- Convention: higher is better, so use neg_cost
            local warming = { accuracy = 0.932, neg_cost = -2.45 }
            local lats    = { accuracy = 0.880, neg_cost = -134.50 }
            expect(cp.dominates(warming, lats)).to.equal(true)
            expect(cp.dominates(lats, warming)).to.equal(false)
        end)

        it("does not dominate when each wins on one axis", function()
            local a = { accuracy = 0.95, neg_cost = -100 }
            local b = { accuracy = 0.90, neg_cost = -10 }
            expect(cp.dominates(a, b)).to.equal(false)
            expect(cp.dominates(b, a)).to.equal(false)
        end)

        it("does not dominate when equal", function()
            local a = { accuracy = 0.90, neg_cost = -50 }
            local b = { accuracy = 0.90, neg_cost = -50 }
            expect(cp.dominates(a, b)).to.equal(false)
        end)
    end)

    describe("frontier", function()
        it("returns only non-dominated candidates", function()
            local candidates = {
                { accuracy = 0.932, neg_cost = -2.45 },   -- warming (frontier)
                { accuracy = 0.880, neg_cost = -134.50 },  -- LATS (dominated)
                { accuracy = 0.878, neg_cost = -3.90 },    -- Reflexion (dominated)
                { accuracy = 0.95,  neg_cost = -50 },      -- hypothetical (frontier)
            }
            local f = cp.frontier(candidates)
            expect(#f).to.equal(2)
        end)

        it("returns all when none dominated", function()
            local candidates = {
                { accuracy = 0.95, neg_cost = -100 },
                { accuracy = 0.90, neg_cost = -10 },
            }
            local f = cp.frontier(candidates)
            expect(#f).to.equal(2)
        end)
    end)

    describe("is_dominated", function()
        it("detects dominated candidate", function()
            local lats = { accuracy = 0.880, neg_cost = -134.50 }
            local warming = { accuracy = 0.932, neg_cost = -2.45 }
            local dom, _ = cp.is_dominated(lats, warming)
            expect(dom).to.equal(true)
        end)
    end)

    describe("layers", function()
        it("separates into Pareto layers", function()
            local candidates = {
                { accuracy = 0.95, neg_cost = -100 },
                { accuracy = 0.90, neg_cost = -10 },
                { accuracy = 0.85, neg_cost = -50 },   -- dominated by both above
            }
            local l = cp.layers(candidates)
            expect(#l).to.equal(2)
            expect(#l[1]).to.equal(2)  -- frontier
            expect(#l[2]).to.equal(1)  -- layer 1
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- eval_guard (N2 + N3 + N4)
-- ═══════════════════════════════════════════════════════════════════

describe("eval_guard", function()
    local eg = require("eval_guard")

    describe("self_critique (N2)", function()
        it("passes with external grader", function()
            local ok, _ = eg.self_critique({ has_external_grader = true })
            expect(ok).to.equal(true)
        end)

        it("fails without external grader", function()
            local ok, reason = eg.self_critique({ has_external_grader = false })
            expect(ok).to.equal(false)
            expect(reason:find("N2 FAIL")).to_not.equal(nil)
        end)
    end)

    describe("baseline (N3)", function()
        it("passes with baseline", function()
            local ok, _ = eg.baseline({ has_baseline = true })
            expect(ok).to.equal(true)
        end)

        it("fails without baseline", function()
            local ok, reason = eg.baseline({ has_baseline = false })
            expect(ok).to.equal(false)
            expect(reason:find("N3 FAIL")).to_not.equal(nil)
        end)

        it("fails when budget does not match", function()
            local ok, _ = eg.baseline({
                has_baseline = true,
                baseline_budget_matches = false
            })
            expect(ok).to.equal(false)
        end)
    end)

    describe("contamination (N4)", function()
        it("fails on absolute metric type", function()
            local ok, reason = eg.contamination({ metric_type = "absolute" })
            expect(ok).to.equal(false)
            expect(reason:find("N4 FAIL")).to_not.equal(nil)
        end)

        it("passes with delta + cost + pareto", function()
            local ok, _ = eg.contamination({
                metric_type = "delta",
                has_holdout = true,
                has_cost = true,
                has_pareto = true,
            })
            expect(ok).to.equal(true)
        end)

        it("fails when missing cost metric", function()
            local ok, _ = eg.contamination({
                metric_type = "delta",
                has_holdout = true,
                has_cost = false,
                has_pareto = true,
            })
            expect(ok).to.equal(false)
        end)
    end)

    describe("check_all", function()
        it("all pass scenario", function()
            local r = eg.check_all({
                has_external_grader = true,
                has_baseline = true,
                baseline_budget_matches = true,
                metric_type = "delta",
                has_holdout = true,
                has_cost = true,
                has_pareto = true,
            })
            expect(r.passed).to.equal(true)
            expect(r.n_failed).to.equal(0)
            expect(r.n_total).to.equal(3)
        end)

        it("reports multiple violations", function()
            local r = eg.check_all({
                has_external_grader = false,
                has_baseline = false,
                metric_type = "absolute",
            })
            expect(r.passed).to.equal(false)
            expect(r.n_failed).to.equal(3)
            expect(#r.violations).to.equal(3)
        end)
    end)
end)
