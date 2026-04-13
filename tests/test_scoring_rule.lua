--- Tests for scoring_rule (Proper Scoring Rules) package.
--- Pure computation — no LLM mocking needed.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local sr = require("scoring_rule")

local function approx(a, b, tol)
    tol = tol or 1e-6
    return math.abs(a - b) < tol
end

-- ═══════════════════════════════════════════════════════════════════
-- Brier score
-- ═══════════════════════════════════════════════════════════════════

describe("sr.brier", function()
    it("confident correct: -(0.8-1)^2 = -0.04", function()
        expect(approx(sr.brier(0.8, 1), -0.04)).to.equal(true)
    end)

    it("confident wrong: -(0.8-0)^2 = -0.64", function()
        expect(approx(sr.brier(0.8, 0), -0.64)).to.equal(true)
    end)

    it("perfect prediction: -(1-1)^2 = 0", function()
        expect(sr.brier(1.0, 1)).to.equal(0)
    end)

    it("worst prediction: -(0-1)^2 = -1", function()
        expect(sr.brier(0.0, 1)).to.equal(-1)
    end)

    it("coin flip: -(0.5-1)^2 = -0.25", function()
        expect(approx(sr.brier(0.5, 1), -0.25)).to.equal(true)
    end)

    it("accepts boolean outcomes", function()
        expect(approx(sr.brier(0.8, true), -0.04)).to.equal(true)
        expect(approx(sr.brier(0.8, false), -0.64)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Log score
-- ═══════════════════════════════════════════════════════════════════

describe("sr.log_score", function()
    it("confident correct: ln(0.8) ≈ -0.2231", function()
        local s, clamped = sr.log_score(0.8, 1)
        expect(approx(s, math.log(0.8))).to.equal(true)
        expect(clamped).to.equal(false)
    end)

    it("confident wrong: ln(0.2) ≈ -1.6094", function()
        local s, _ = sr.log_score(0.8, 0)
        expect(approx(s, math.log(0.2))).to.equal(true)
    end)

    it("clamps p=0 to avoid -inf", function()
        local s, clamped = sr.log_score(0.0, 1)
        expect(clamped).to.equal(true)
        expect(s == s).to.equal(true)  -- not NaN
        expect(s < -30).to.equal(true)  -- very negative but finite
    end)

    it("clamps p=1 for y=0 to avoid -inf", function()
        local s, clamped = sr.log_score(1.0, 0)
        expect(clamped).to.equal(true)
        expect(s == s).to.equal(true)
    end)

    it("perfect prediction p=1 y=1 is near 0 (clamped)", function()
        local s, _ = sr.log_score(1.0, 1)
        expect(approx(s, 0, 1e-10)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Spherical score
-- ═══════════════════════════════════════════════════════════════════

describe("sr.spherical", function()
    it("perfect prediction: p=1, y=1 → score=1", function()
        expect(approx(sr.spherical(1.0, 1), 1.0)).to.equal(true)
    end)

    it("worst prediction: p=0, y=1 → score=0", function()
        -- numerator = 0*1 + 1*0 = 0, denominator = √(0+1) = 1
        expect(approx(sr.spherical(0.0, 1), 0)).to.equal(true)
    end)

    it("coin flip: p=0.5 → score=1/√2", function()
        -- numerator = 0.5*1 + 0.5*0 = 0.5 (for y=1)
        -- denominator = √(0.25 + 0.25) = √0.5
        -- score = 0.5 / √0.5 = 1/√2
        expect(approx(sr.spherical(0.5, 1), 1 / math.sqrt(2))).to.equal(true)
    end)

    it("confident correct is better than coin flip", function()
        expect(sr.spherical(0.9, 1) > sr.spherical(0.5, 1)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Properness verification (Monte Carlo)
-- ═══════════════════════════════════════════════════════════════════

describe("properness", function()
    -- For a strictly proper rule, E_q[S(q,Y)] > E_q[S(p,Y)] for all p≠q
    -- We verify this for Brier at q=0.7

    it("Brier is proper: E_q[S(q,Y)] ≥ E_q[S(p,Y)] at q=0.7", function()
        local q = 0.7
        -- E_q[S(p,Y)] = q * S(p,1) + (1-q) * S(p,0)
        --             = q * (-(p-1)^2) + (1-q) * (-(p-0)^2)
        --             = -q*(p-1)^2 - (1-q)*p^2

        local function expected_brier(p)
            return q * sr.brier(p, 1) + (1 - q) * sr.brier(p, 0)
        end

        local e_at_q = expected_brier(q)

        -- Check 10 different p values: all should score ≤ e_at_q
        for _, p in ipairs({ 0.0, 0.1, 0.2, 0.3, 0.5, 0.6, 0.8, 0.9, 1.0 }) do
            expect(expected_brier(p) <= e_at_q + 1e-12).to.equal(true)
        end
    end)

    it("Log score is proper: E_q[S(q,Y)] ≥ E_q[S(p,Y)] at q=0.7", function()
        local q = 0.7

        local function expected_log(p)
            local s1, _ = sr.log_score(p, 1)
            local s0, _ = sr.log_score(p, 0)
            return q * s1 + (1 - q) * s0
        end

        local e_at_q = expected_log(q)

        for _, p in ipairs({ 0.1, 0.2, 0.3, 0.5, 0.6, 0.8, 0.9 }) do
            expect(expected_log(p) <= e_at_q + 1e-12).to.equal(true)
        end
    end)

    it("Spherical is proper: E_q[S(q,Y)] ≥ E_q[S(p,Y)] at q=0.7", function()
        local q = 0.7

        local function expected_sph(p)
            return q * sr.spherical(p, 1) + (1 - q) * sr.spherical(p, 0)
        end

        local e_at_q = expected_sph(q)

        for _, p in ipairs({ 0.1, 0.2, 0.3, 0.5, 0.6, 0.8, 0.9 }) do
            expect(expected_sph(p) <= e_at_q + 1e-12).to.equal(true)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Batch evaluate
-- ═══════════════════════════════════════════════════════════════════

describe("sr.evaluate", function()
    local preds = { 0.9, 0.7, 0.6, 0.8, 0.3 }
    local outs  = { 1,   1,   0,   1,   0   }

    it("computes mean Brier score", function()
        local r = sr.evaluate(preds, outs, { rule = "brier" })
        expect(r.n).to.equal(5)
        expect(type(r.mean_score)).to.equal("number")
        -- Manual: -0.01 + -0.09 + -0.36 + -0.04 + -0.09 = -0.59 / 5 = -0.118
        expect(approx(r.mean_score, -0.118)).to.equal(true)
    end)

    it("computes log scores with clamp count", function()
        local r = sr.evaluate(preds, outs, { rule = "log" })
        expect(r.clamped_count).to.equal(0)
    end)

    it("computes spherical scores", function()
        local r = sr.evaluate(preds, outs, { rule = "spherical" })
        expect(r.n).to.equal(5)
    end)

    it("errors on unknown rule", function()
        expect(function()
            sr.evaluate(preds, outs, { rule = "unknown" })
        end).to.fail()
    end)

    it("errors on mismatched lengths", function()
        expect(function()
            sr.evaluate({ 0.5 }, { 1, 0 })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Calibration
-- ═══════════════════════════════════════════════════════════════════

describe("sr.calibration", function()
    it("perfect calibration gives ECE ≈ 0", function()
        -- All predictions match outcomes exactly
        local preds = { 1.0, 0.0, 1.0, 0.0 }
        local outs  = { 1,   0,   1,   0   }
        local cal = sr.calibration(preds, outs, { bins = 2 })
        expect(cal.ece < 0.01).to.equal(true)
    end)

    it("overconfident predictions detected", function()
        -- Predict high but outcomes are mixed
        local preds = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9 }
        local outs  = { 1,   0,   1,   0,   1,   0,   1,   0,   1,   0   }
        -- conf = 0.9 but acc = 0.5 → overconfident
        local cal = sr.calibration(preds, outs, { bins = 10 })
        expect(cal.overconfident).to.equal(true)
        expect(cal.ece > 0.3).to.equal(true)
    end)

    it("underconfident predictions detected", function()
        -- Predict low but outcomes are mostly positive
        local preds = { 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3 }
        local outs  = { 1,   1,   1,   1,   1,   1,   1,   1,   0,   0   }
        -- conf = 0.3 but acc = 0.8 → underconfident
        local cal = sr.calibration(preds, outs, { bins = 10 })
        expect(cal.underconfident).to.equal(true)
    end)

    it("returns bin details", function()
        local preds = { 0.1, 0.2, 0.8, 0.9 }
        local outs  = { 0,   0,   1,   1   }
        local cal = sr.calibration(preds, outs, { bins = 2 })
        expect(#cal.bins >= 1).to.equal(true)
        for _, bin in ipairs(cal.bins) do
            expect(type(bin.conf)).to.equal("number")
            expect(type(bin.acc)).to.equal("number")
            expect(type(bin.count)).to.equal("number")
            expect(bin.count > 0).to.equal(true)
        end
    end)

    it("adjusts bins when more bins than samples", function()
        local preds = { 0.5, 0.6 }
        local outs  = { 1, 0 }
        local cal = sr.calibration(preds, outs, { bins = 100 })
        expect(cal.n_bins).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Compare
-- ═══════════════════════════════════════════════════════════════════

describe("sr.compare", function()
    it("ranks better-calibrated agent first", function()
        local cmp = sr.compare({
            {
                name = "good",
                predictions = { 0.9, 0.8, 0.2, 0.1 },
                outcomes = { 1, 1, 0, 0 },
            },
            {
                name = "bad",
                predictions = { 0.5, 0.5, 0.5, 0.5 },
                outcomes = { 1, 1, 0, 0 },
            },
        }, { rule = "brier" })

        expect(cmp.best).to.equal("good")
        expect(cmp.ranking[1]).to.equal("good")
        expect(cmp.scores["good"] > cmp.scores["bad"]).to.equal(true)
    end)

    it("works with log rule", function()
        local cmp = sr.compare({
            {
                name = "a",
                predictions = { 0.9, 0.1 },
                outcomes = { 1, 0 },
            },
            {
                name = "b",
                predictions = { 0.5, 0.5 },
                outcomes = { 1, 0 },
            },
        }, { rule = "log" })

        expect(cmp.best).to.equal("a")
    end)

    it("errors on missing name", function()
        expect(function()
            sr.compare({ { predictions = {0.5}, outcomes = {1} } })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Input validation
-- ═══════════════════════════════════════════════════════════════════

describe("input validation", function()
    it("brier errors on p out of range", function()
        expect(function() sr.brier(1.5, 1) end).to.fail()
        expect(function() sr.brier(-0.1, 1) end).to.fail()
    end)

    it("brier errors on invalid outcome", function()
        expect(function() sr.brier(0.5, 0.5) end).to.fail()
        expect(function() sr.brier(0.5, "yes") end).to.fail()
    end)

    it("evaluate errors on empty predictions", function()
        expect(function() sr.evaluate({}, {}) end).to.fail()
    end)

    it("calibration errors on empty predictions", function()
        expect(function() sr.calibration({}, {}) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Edge: n=1
-- ═══════════════════════════════════════════════════════════════════

describe("edge: single sample", function()
    it("evaluate works with n=1", function()
        local r = sr.evaluate({ 0.8 }, { 1 })
        expect(r.n).to.equal(1)
        expect(approx(r.mean_score, -0.04)).to.equal(true)
    end)

    it("calibration works with n=1", function()
        local cal = sr.calibration({ 0.8 }, { 1 })
        expect(cal.n).to.equal(1)
    end)
end)
