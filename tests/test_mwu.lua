--- Tests for mwu (Multiplicative Weights Update) package.
--- Pure computation — no LLM mocking needed.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local mwu = require("mwu")

local function approx(a, b, tol)
    tol = tol or 1e-9
    return math.abs(a - b) < tol
end

-- ═══════════════════════════════════════════════════════════════════
-- Updater: new + update + weights + stats
-- ═══════════════════════════════════════════════════════════════════

describe("mwu.new", function()
    it("creates updater with fixed T", function()
        local u = mwu.new({ n = 3, T = 100 })
        local w = u:weights()
        expect(#w).to.equal(3)
        -- Initially uniform
        expect(approx(w[1], 1/3)).to.equal(true)
        expect(approx(w[2], 1/3)).to.equal(true)
        expect(approx(w[3], 1/3)).to.equal(true)
    end)

    it("creates updater with explicit eta", function()
        local u = mwu.new({ n = 2, eta = 0.1 })
        expect(u.eta).to.equal(0.1)
    end)

    it("creates updater with doubling trick (no T, no eta)", function()
        local u = mwu.new({ n = 4 })
        expect(u.use_doubling).to.equal(true)
    end)

    it("errors on invalid n", function()
        expect(function() mwu.new({ n = 0 }) end).to.fail()
        expect(function() mwu.new({ n = -1 }) end).to.fail()
        expect(function() mwu.new({ n = 1.5 }) end).to.fail()
    end)

    it("errors on invalid eta", function()
        expect(function() mwu.new({ n = 2, eta = 0 }) end).to.fail()
        expect(function() mwu.new({ n = 2, eta = 1 }) end).to.fail()
        expect(function() mwu.new({ n = 2, eta = -0.1 }) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Regret bound verification
-- ═══════════════════════════════════════════════════════════════════

describe("regret bound", function()
    -- Adversarial sequence: agent 1 always has loss 0.2, others oscillate
    it("regret ≤ 2√(T ln N) with fixed T", function()
        local n = 5
        local T = 100
        local u = mwu.new({ n = n, T = T })

        for t = 1, T do
            local losses = {}
            for i = 1, n do
                if i == 1 then
                    losses[i] = 0.2
                else
                    -- Adversarial oscillation
                    losses[i] = (t + i) % 2 == 0 and 0.9 or 0.1
                end
            end
            u:update(losses)
        end

        local s = u:stats()
        expect(s.regret_within_bound).to.equal(true)
        expect(s.best_agent).to.equal(1)
    end)

    -- Worst-case: losses designed to maximize regret
    it("regret stays within bound under worst-case losses", function()
        local n = 3
        local T = 200
        local u = mwu.new({ n = n, T = T })

        for t = 1, T do
            -- Cycle which agent has high loss
            local bad = (t % n) + 1
            local losses = {}
            for i = 1, n do
                losses[i] = i == bad and 1.0 or 0.0
            end
            u:update(losses)
        end

        local s = u:stats()
        expect(s.regret_within_bound).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Best-arm convergence
-- ═══════════════════════════════════════════════════════════════════

describe("best-arm convergence", function()
    it("concentrates weight on consistently best agent", function()
        local n = 4
        local T = 100
        local u = mwu.new({ n = n, T = T })

        for _ = 1, T do
            -- Agent 3 always best (loss=0), others bad
            u:update({ 0.8, 0.7, 0.0, 0.9 })
        end

        local w = u:weights()
        -- Agent 3 should have dominant weight
        expect(w[3] > 0.9).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Symmetry
-- ═══════════════════════════════════════════════════════════════════

describe("symmetry", function()
    it("equal losses produce equal weights", function()
        local u = mwu.new({ n = 3, T = 50 })

        for _ = 1, 50 do
            u:update({ 0.5, 0.5, 0.5 })
        end

        local w = u:weights()
        expect(approx(w[1], 1/3, 1e-6)).to.equal(true)
        expect(approx(w[2], 1/3, 1e-6)).to.equal(true)
        expect(approx(w[3], 1/3, 1e-6)).to.equal(true)
    end)

    it("swapping loss sequences swaps weights", function()
        local u1 = mwu.new({ n = 2, T = 10 })
        local u2 = mwu.new({ n = 2, T = 10 })

        for _ = 1, 10 do
            u1:update({ 0.2, 0.8 })
            u2:update({ 0.8, 0.2 })
        end

        local w1 = u1:weights()
        local w2 = u2:weights()
        expect(approx(w1[1], w2[2], 1e-9)).to.equal(true)
        expect(approx(w1[2], w2[1], 1e-9)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Doubling trick
-- ═══════════════════════════════════════════════════════════════════

describe("doubling trick", function()
    it("works without T specified", function()
        local u = mwu.new({ n = 3 })

        for t = 1, 100 do
            local losses = {}
            for i = 1, 3 do
                losses[i] = i == 1 and 0.1 or 0.6
            end
            u:update(losses)
        end

        local s = u:stats()
        expect(s.round).to.equal(100)
        -- Regret should still be reasonable (doubling trick has slightly
        -- worse constant but same O(√T) order)
        expect(type(s.regret)).to.equal("number")
        expect(s.regret == s.regret).to.equal(true)  -- not NaN
    end)

    it("regret stays bounded under doubling trick", function()
        local n = 4
        local u = mwu.new({ n = n })

        for t = 1, 200 do
            local losses = {}
            for i = 1, n do
                losses[i] = i == 2 and 0.1 or 0.5
            end
            u:update(losses)
        end

        local s = u:stats()
        -- Doubling trick regret is O(√(T ln N)) with constant ~4
        -- We use a generous bound
        local generous_bound = 4 * math.sqrt(200 * math.log(n))
        expect(s.regret < generous_bound).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Underflow protection (log-space)
-- ═══════════════════════════════════════════════════════════════════

describe("underflow protection", function()
    it("agent with constant loss=1 does not produce NaN", function()
        local u = mwu.new({ n = 3, T = 100 })

        for _ = 1, 100 do
            -- Agent 1: always loss=1 → weight should approach 0
            u:update({ 1.0, 0.1, 0.2 })
        end

        local w = u:weights()
        for i = 1, 3 do
            expect(w[i] == w[i]).to.equal(true)  -- not NaN
            expect(w[i] >= 0).to.equal(true)
        end
        -- Agent 1 should have negligible weight
        expect(w[1] < 0.01).to.equal(true)
    end)

    it("handles extreme loss contrast without overflow", function()
        local u = mwu.new({ n = 2, T = 500 })

        for _ = 1, 500 do
            u:update({ 1.0, 0.0 })
        end

        local w = u:weights()
        expect(w[1] == w[1]).to.equal(true)
        expect(w[2] == w[2]).to.equal(true)
        -- Agent 2 should dominate
        expect(w[2] > 0.99).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- solve (one-shot)
-- ═══════════════════════════════════════════════════════════════════

describe("mwu.solve", function()
    it("produces same result as sequential new+update", function()
        local n = 3
        local T = 20
        local loss_matrix = {}
        for t = 1, T do
            loss_matrix[t] = {}
            for i = 1, n do
                loss_matrix[t][i] = ((t * 7 + i * 13) % 100) / 100
            end
        end

        -- Solve
        local r = mwu.solve(loss_matrix)

        -- Sequential
        local u = mwu.new({ n = n, T = T })
        for t = 1, T do
            u:update(loss_matrix[t])
        end
        local s = u:stats()
        local w = u:weights()

        -- Compare
        expect(approx(r.regret, s.regret, 1e-9)).to.equal(true)
        expect(approx(r.cumulative_loss, s.cumulative_loss, 1e-9)).to.equal(true)
        expect(r.best_agent).to.equal(s.best_agent)
        for i = 1, n do
            expect(approx(r.final_weights[i], w[i], 1e-9)).to.equal(true)
        end
    end)

    it("returns weight_history with correct length", function()
        local loss_matrix = {
            { 0.5, 0.5 },
            { 0.3, 0.7 },
            { 0.1, 0.9 },
        }
        local r = mwu.solve(loss_matrix)
        expect(#r.weight_history).to.equal(3)
        expect(r.T).to.equal(3)
        expect(r.n).to.equal(2)
    end)

    it("errors on empty loss matrix", function()
        expect(function() mwu.solve({}) end).to.fail()
    end)

    it("errors on inconsistent dimensions", function()
        expect(function()
            mwu.solve({ { 0.5, 0.5 }, { 0.5 } })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- accuracy_to_loss utility
-- ═══════════════════════════════════════════════════════════════════

describe("mwu.accuracy_to_loss", function()
    it("converts accuracies to losses", function()
        local losses = mwu.accuracy_to_loss({ 0.9, 0.6, 1.0, 0.0 })
        expect(approx(losses[1], 0.1)).to.equal(true)
        expect(approx(losses[2], 0.4)).to.equal(true)
        expect(approx(losses[3], 0.0)).to.equal(true)
        expect(approx(losses[4], 1.0)).to.equal(true)
    end)

    it("errors on out-of-range accuracy", function()
        expect(function() mwu.accuracy_to_loss({ 1.5 }) end).to.fail()
        expect(function() mwu.accuracy_to_loss({ -0.1 }) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Input validation
-- ═══════════════════════════════════════════════════════════════════

describe("input validation", function()
    it("update errors on wrong number of losses", function()
        local u = mwu.new({ n = 3, T = 10 })
        expect(function() u:update({ 0.5, 0.5 }) end).to.fail()
    end)

    it("update errors on loss out of [0,1]", function()
        local u = mwu.new({ n = 2, T = 10 })
        expect(function() u:update({ 0.5, 1.5 }) end).to.fail()
        expect(function() u:update({ -0.1, 0.5 }) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- N=1 edge case
-- ═══════════════════════════════════════════════════════════════════

describe("edge: N=1", function()
    it("single agent always has weight 1.0", function()
        local u = mwu.new({ n = 1, T = 10 })
        u:update({ 0.5 })
        u:update({ 0.8 })

        local w = u:weights()
        expect(approx(w[1], 1.0)).to.equal(true)
    end)

    it("regret is always 0 for single agent", function()
        local u = mwu.new({ n = 1, T = 10 })
        for _ = 1, 10 do
            u:update({ 0.5 })
        end
        local s = u:stats()
        expect(approx(s.regret, 0, 1e-9)).to.equal(true)
    end)
end)
