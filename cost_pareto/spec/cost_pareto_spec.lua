--- Tests for cost_pareto.
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
