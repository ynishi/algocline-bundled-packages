--- Tests for shapley package.
--- Pure computation — no LLM mocking needed.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local shapley = require("shapley")

-- ─── Helper: approximate equality ───

local function approx(a, b, tol)
    tol = tol or 1e-9
    return math.abs(a - b) < tol
end

-- ═══════════════════════════════════════════════════════════════════
-- Exact computation
-- ═══════════════════════════════════════════════════════════════════

describe("shapley.exact", function()

    -- Classic 3-player voting game (Shapley 1953):
    -- v(S) = 1 if |S| >= 2, else 0 (simple majority of 3)
    describe("classic 3-player majority game", function()
        local agents = { "a", "b", "c" }
        local function v_majority(set, _list)
            local count = 0
            for _ in pairs(set) do count = count + 1 end
            return count >= 2 and 1 or 0
        end

        local r = shapley.exact(agents, v_majority)

        it("returns equal values for symmetric agents", function()
            expect(approx(r.values["a"], r.values["b"])).to.equal(true)
            expect(approx(r.values["b"], r.values["c"])).to.equal(true)
        end)

        it("each agent gets 1/3", function()
            expect(approx(r.values["a"], 1/3)).to.equal(true)
        end)

        it("efficiency holds: sum = v(N) - v(empty)", function()
            expect(r.efficiency_check).to.equal(true)
        end)

        it("v(N)=1, v(empty)=0", function()
            expect(r.v_N).to.equal(1)
            expect(r.v_empty).to.equal(0)
        end)
    end)

    -- Asymmetric game: dictator
    -- v(S) = 1 if "king" in S, else 0
    describe("dictator game", function()
        local agents = { "king", "pawn1", "pawn2" }
        local function v_dictator(set, _list)
            return set["king"] and 1 or 0
        end

        local r = shapley.exact(agents, v_dictator)

        it("king gets all value", function()
            expect(approx(r.values["king"], 1.0)).to.equal(true)
        end)

        it("pawns are dummy players (phi=0)", function()
            expect(approx(r.values["pawn1"], 0.0)).to.equal(true)
            expect(approx(r.values["pawn2"], 0.0)).to.equal(true)
        end)

        it("efficiency holds", function()
            expect(r.efficiency_check).to.equal(true)
        end)
    end)

    -- Additive game: v(S) = sum of individual values
    -- phi_i should equal individual value
    describe("additive game", function()
        local agents = { 1, 2, 3 }
        local individual = { [1] = 0.5, [2] = 0.3, [3] = 0.2 }
        local function v_additive(set, _list)
            local s = 0
            for a, _ in pairs(set) do s = s + (individual[a] or 0) end
            return s
        end

        local r = shapley.exact(agents, v_additive)

        it("phi_i equals individual value", function()
            expect(approx(r.values[1], 0.5)).to.equal(true)
            expect(approx(r.values[2], 0.3)).to.equal(true)
            expect(approx(r.values[3], 0.2)).to.equal(true)
        end)

        it("efficiency holds", function()
            expect(r.efficiency_check).to.equal(true)
        end)
    end)

    -- Edge: n=1
    describe("single agent", function()
        local agents = { "solo" }
        local function v_solo(set, _list)
            return set["solo"] and 0.75 or 0
        end

        local r = shapley.exact(agents, v_solo)

        it("phi = v({solo}) - v(empty)", function()
            expect(approx(r.values["solo"], 0.75)).to.equal(true)
        end)

        it("efficiency holds", function()
            expect(r.efficiency_check).to.equal(true)
        end)
    end)

    -- Edge: n=2 with synergy
    describe("2-player synergy game", function()
        local agents = { "x", "y" }
        -- v({}) = 0, v({x}) = 0.3, v({y}) = 0.2, v({x,y}) = 1.0
        -- Synergy: 1.0 - 0.3 - 0.2 = 0.5 shared equally
        -- phi_x = 0.3 + 0.25 = 0.55, phi_y = 0.2 + 0.25 = 0.45
        local function v_synergy(set, _list)
            local has_x = set["x"] and true or false
            local has_y = set["y"] and true or false
            if has_x and has_y then return 1.0 end
            if has_x then return 0.3 end
            if has_y then return 0.2 end
            return 0
        end

        local r = shapley.exact(agents, v_synergy)

        it("phi_x = 0.55", function()
            expect(approx(r.values["x"], 0.55)).to.equal(true)
        end)

        it("phi_y = 0.45", function()
            expect(approx(r.values["y"], 0.45)).to.equal(true)
        end)

        it("efficiency holds", function()
            expect(r.efficiency_check).to.equal(true)
        end)
    end)

    -- Error: n > 12
    describe("rejects n > 12", function()
        it("errors with helpful message", function()
            local agents = {}
            for i = 1, 13 do agents[i] = i end
            expect(function()
                shapley.exact(agents, function() return 0 end)
            end).to.fail()
        end)
    end)

    -- Error: invalid inputs
    describe("input validation", function()
        it("errors on empty agents", function()
            expect(function()
                shapley.exact({}, function() return 0 end)
            end).to.fail()
        end)

        it("errors on non-function v_fn", function()
            expect(function()
                shapley.exact({ "a" }, "not a function")
            end).to.fail()
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Monte Carlo approximation
-- ═══════════════════════════════════════════════════════════════════

describe("shapley.montecarlo", function()

    -- Same 3-player majority game: MC should approximate exact
    describe("MC vs exact on 3-player majority", function()
        local agents = { "a", "b", "c" }
        local function v_majority(set, _list)
            local count = 0
            for _ in pairs(set) do count = count + 1 end
            return count >= 2 and 1 or 0
        end

        local exact = shapley.exact(agents, v_majority)
        local mc = shapley.montecarlo(agents, v_majority, {
            samples = 10000, seed = 123,
        })

        it("MC values within CI of exact values", function()
            for _, a in ipairs(agents) do
                local diff = math.abs(mc.values[a] - exact.values[a])
                -- With 10000 samples, should be very close
                expect(diff < 0.05).to.equal(true)
            end
        end)

        it("CI95 contains exact value", function()
            for _, a in ipairs(agents) do
                local lo = mc.ci95[a][1]
                local hi = mc.ci95[a][2]
                local ex = exact.values[a]
                expect(lo <= ex + 1e-9 and ex - 1e-9 <= hi).to.equal(true)
            end
        end)

        it("std is reported and finite", function()
            for _, a in ipairs(agents) do
                expect(type(mc.std[a])).to.equal("number")
                expect(mc.std[a] >= 0).to.equal(true)
                expect(mc.std[a] == mc.std[a]).to.equal(true)  -- not NaN
            end
        end)
    end)

    -- MC on 5-player game
    describe("MC on 5-player weighted game", function()
        local agents = { 1, 2, 3, 4, 5 }
        -- v(S) = 1 if total weight >= 6, weights = {4, 3, 2, 1, 1}
        local weights = { [1]=4, [2]=3, [3]=2, [4]=1, [5]=1 }
        local function v_weighted(set, _list)
            local total = 0
            for a, _ in pairs(set) do total = total + (weights[a] or 0) end
            return total >= 6 and 1 or 0
        end

        local exact = shapley.exact(agents, v_weighted)
        local mc = shapley.montecarlo(agents, v_weighted, {
            samples = 5000, seed = 99,
        })

        it("MC approximates exact within tolerance", function()
            for _, a in ipairs(agents) do
                local diff = math.abs(mc.values[a] - exact.values[a])
                expect(diff < 0.05).to.equal(true)
            end
        end)

        it("efficiency approximately holds", function()
            -- MC efficiency is approximate
            expect(mc.efficiency_error < 0.01).to.equal(true)
        end)
    end)

    -- Determinism with same seed
    describe("deterministic with same seed", function()
        local agents = { "a", "b" }
        local function v(set, _list)
            local n = 0
            for _ in pairs(set) do n = n + 1 end
            return n / 2
        end

        local r1 = shapley.montecarlo(agents, v, { samples = 100, seed = 42 })
        local r2 = shapley.montecarlo(agents, v, { samples = 100, seed = 42 })

        it("same seed produces same results", function()
            expect(r1.values["a"]).to.equal(r2.values["a"])
            expect(r1.values["b"]).to.equal(r2.values["b"])
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- accuracy_coalition helper
-- ═══════════════════════════════════════════════════════════════════

describe("shapley.accuracy_coalition", function()

    -- 3 agents, 4 cases
    describe("3 agents with known outputs", function()
        local outputs = {
            { 1, 1, 0, 0 },  -- agent 1
            { 1, 0, 1, 0 },  -- agent 2
            { 1, 1, 1, 0 },  -- agent 3
        }
        local truth = { 1, 1, 1, 0 }

        local v_fn, agents = shapley.accuracy_coalition(outputs, truth)

        it("returns agents list", function()
            expect(#agents).to.equal(3)
        end)

        it("v(all) = majority vote accuracy of all 3", function()
            -- Case 1: 1,1,1 → maj=1, truth=1 ✓
            -- Case 2: 1,0,1 → maj=1, truth=1 ✓
            -- Case 3: 0,1,1 → maj=1, truth=1 ✓
            -- Case 4: 0,0,0 → maj=0, truth=0 ✓
            local all_set = { [1]=true, [2]=true, [3]=true }
            expect(v_fn(all_set, {1,2,3})).to.equal(1.0)
        end)

        it("v(empty) = 0", function()
            expect(v_fn({}, {})).to.equal(0)
        end)

        it("v({1}) = agent 1 solo accuracy", function()
            -- Case 1: 1=1 ✓, Case 2: 1=1 ✓, Case 3: 0≠1 ✗, Case 4: 0=0 ✓
            expect(v_fn({ [1]=true }, {1})).to.equal(0.75)
        end)

        it("v({2}) = agent 2 solo accuracy", function()
            -- Case 1: 1=1 ✓, Case 2: 0≠1 ✗, Case 3: 1=1 ✓, Case 4: 0=0 ✓
            expect(v_fn({ [2]=true }, {2})).to.equal(0.75)
        end)

        it("v({3}) = agent 3 solo accuracy", function()
            -- Case 1: 1=1 ✓, Case 2: 1=1 ✓, Case 3: 1=1 ✓, Case 4: 0=0 ✓
            expect(v_fn({ [3]=true }, {3})).to.equal(1.0)
        end)

        -- Integration: exact Shapley on this v_fn
        it("exact Shapley efficiency holds", function()
            local r = shapley.exact(agents, v_fn)
            expect(r.efficiency_check).to.equal(true)
        end)
    end)

    -- Named agents (map style)
    describe("named agents", function()
        local outputs = {
            alice = { 1, 1, 0 },
            bob   = { 0, 1, 1 },
        }
        local truth = { 1, 1, 1 }
        local agent_list = { "alice", "bob" }

        local v_fn, agents = shapley.accuracy_coalition(outputs, truth, agent_list)

        it("returns correct agents list", function()
            expect(agents[1]).to.equal("alice")
            expect(agents[2]).to.equal("bob")
        end)

        it("v_fn works with named agents", function()
            local val = v_fn({ alice=true, bob=true }, { "alice", "bob" })
            -- Case 1: 1,0 → tie → 0, truth=1 ✗
            -- Case 2: 1,1 → 1, truth=1 ✓
            -- Case 3: 0,1 → tie → 0, truth=1 ✗
            expect(approx(val, 1/3)).to.equal(true)
        end)
    end)

    -- Tie-breaking: even number of agents, split vote → 0 (conservative)
    describe("tie-breaking", function()
        local outputs = {
            { 1, 0 },
            { 0, 1 },
        }
        local truth = { 1, 1 }

        local v_fn, _ = shapley.accuracy_coalition(outputs, truth)

        it("tie breaks to 0 (conservative)", function()
            -- Both cases are ties (1 vs 1), tie→0
            -- Case 1: maj=0, truth=1 ✗
            -- Case 2: maj=0, truth=1 ✗
            local val = v_fn({ [1]=true, [2]=true }, {1, 2})
            expect(val).to.equal(0)
        end)
    end)

    -- Error: mismatched lengths
    describe("input validation", function()
        it("errors on mismatched prediction lengths", function()
            expect(function()
                shapley.accuracy_coalition(
                    { { 1, 0 }, { 1, 0, 1 } },
                    { 1, 0 }
                )
            end).to.fail()
        end)

        it("errors on empty ground truth", function()
            expect(function()
                shapley.accuracy_coalition({ { 1 } }, {})
            end).to.fail()
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Axiom verification (comprehensive)
-- ═══════════════════════════════════════════════════════════════════

describe("Shapley axioms", function()

    -- Symmetry: interchangeable agents get equal value
    describe("symmetry", function()
        it("symmetric agents in majority game get equal phi", function()
            local agents = { "a", "b", "c", "d" }
            local function v(set, _list)
                local n = 0
                for _ in pairs(set) do n = n + 1 end
                return n >= 3 and 1 or 0
            end
            local r = shapley.exact(agents, v)
            -- All agents are symmetric
            expect(approx(r.values["a"], r.values["b"])).to.equal(true)
            expect(approx(r.values["b"], r.values["c"])).to.equal(true)
            expect(approx(r.values["c"], r.values["d"])).to.equal(true)
        end)
    end)

    -- Dummy: agent that adds nothing to any coalition gets phi=0
    describe("dummy", function()
        it("dummy agent gets phi=0", function()
            local agents = { "worker", "dummy" }
            local function v(set, _list)
                return set["worker"] and 1 or 0
            end
            local r = shapley.exact(agents, v)
            expect(approx(r.values["dummy"], 0)).to.equal(true)
            expect(approx(r.values["worker"], 1)).to.equal(true)
        end)
    end)

    -- Additivity: phi(v+w) = phi(v) + phi(w)
    describe("additivity", function()
        it("phi(v+w) = phi(v) + phi(w)", function()
            local agents = { "a", "b" }

            local function v1(set, _list)
                local n = 0
                for _ in pairs(set) do n = n + 1 end
                return n * 0.3
            end
            local function v2(set, _list)
                return (set["a"] and set["b"]) and 1 or 0
            end
            local function v_sum(set, list)
                return v1(set, list) + v2(set, list)
            end

            local r1 = shapley.exact(agents, v1)
            local r2 = shapley.exact(agents, v2)
            local r_sum = shapley.exact(agents, v_sum)

            for _, a in ipairs(agents) do
                local expected = r1.values[a] + r2.values[a]
                expect(approx(r_sum.values[a], expected)).to.equal(true)
            end
        end)
    end)
end)
