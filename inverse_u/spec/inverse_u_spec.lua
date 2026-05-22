--- Tests for inverse_u.
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

        it("detects noisy when peak at end but non-monotonic", function()
            -- 0.7 → 0.8 → 0.6 → 0.9: peak at idx 4 (end), not monotone up
            local r = iu.detect({0.7, 0.8, 0.6, 0.9})
            expect(r.trend).to.equal("noisy")
            expect(r.peak_idx).to.equal(4)
        end)

        it("detects noisy when peak at start but non-monotonic", function()
            -- 0.9 → 0.7 → 0.8 → 0.6: peak at idx 1 (start), not monotone down
            local r = iu.detect({0.9, 0.7, 0.8, 0.6})
            expect(r.trend).to.equal("noisy")
            expect(r.peak_idx).to.equal(1)
        end)
    end)

    describe("detect with opts", function()
        it("uses custom flat_epsilon", function()
            -- Range = 0.001, default epsilon 1e-6 would NOT be flat
            local r1 = iu.detect({0.700, 0.701, 0.700})
            expect(r1.trend).to_not.equal("flat")
            -- But with large epsilon it IS flat
            local r2 = iu.detect({0.700, 0.701, 0.700}, { flat_epsilon = 0.01 })
            expect(r2.trend).to.equal("flat")
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
