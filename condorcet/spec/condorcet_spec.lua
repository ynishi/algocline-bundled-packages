--- Tests for condorcet.
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

        it("returns near 0 for uncorrelated vectors", function()
            -- dx = {-2, 1, 0, 1, 0}, dy = {0, -1, 2, 0, -1}
            -- sum_xy = 0 + (-1) + 0 + 0 + 0 = -1
            -- sum_x2 = 6, sum_y2 = 6, r = -1/6 ≈ -0.167
            local m, _ = condorcet.correlation({{1,4,3,4,3}, {3,2,5,3,2}})
            expect(math.abs(m[1][2]) < 0.3).to.equal(true)
        end)

        it("returns -1.0 for alternating anti-correlated pattern", function()
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
