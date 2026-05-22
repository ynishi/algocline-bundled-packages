--- Tests for eval_guard.
--- Pure computation, no LLM mocking.
--- Extracted from tests/test_foundations.lua (Phase C decomposition).

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

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
