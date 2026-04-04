--- Tests for sugarscape_abm and boids_abm
--- Pure computation tests (no LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local PKG_NAMES = {
    "abm", "abm.frame.agent", "abm.frame.model",
    "abm.frame.scheduler", "abm.mc", "abm.sweep", "abm.stats",
    "sugarscape_abm", "boids_abm",
}

local function test_rng(seed)
    local state = seed or 12345
    return function()
        state = state ~ (state << 13)
        state = state ~ (state >> 17)
        state = state ~ (state << 5)
        state = state & 0xFFFFFFFF
        return state / 0x100000000
    end
end

local function mock_alc()
    _G.alc = {
        llm = function() return "mock" end,
        llm_json = function() return {} end,
        log = function() end,
        math = {
            rng_create = function(seed)
                return { _rng = test_rng(seed) }
            end,
            rng_float = function(r)
                return r._rng()
            end,
            median = function(data)
                local sorted = {}
                for i, v in ipairs(data) do sorted[i] = v end
                table.sort(sorted)
                local n = #sorted
                if n % 2 == 1 then return sorted[math.ceil(n / 2)] end
                return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
            end,
            percentile = function(data, p)
                local sorted = {}
                for i, v in ipairs(data) do sorted[i] = v end
                table.sort(sorted)
                local idx = math.ceil(#sorted * p / 100)
                if idx < 1 then idx = 1 end
                if idx > #sorted then idx = #sorted end
                return sorted[idx]
            end,
            wilson_ci = function(count, total, _)
                local rate = total > 0 and count / total or 0
                return { lower = math.max(0, rate - 0.05), upper = math.min(1, rate + 0.05) }
            end,
        },
    }
end

local function reset()
    _G.alc = nil
    for _, name in ipairs(PKG_NAMES) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- sugarscape_abm
-- ================================================================
describe("sugarscape_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("sugarscape_abm")
        expect(m.meta.name).to.equal("sugarscape_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("sugarscape_abm")
        local result = m.run_single({
            grid_size = 15,
            n_agents = 30,
            max_sugar = 4,
            steps = 30,
        }, 42)
        expect(result.survival_rate >= 0).to.equal(true)
        expect(result.survival_rate <= 1).to.equal(true)
        expect(result.gini >= 0).to.equal(true)
        expect(result.gini <= 1).to.equal(true)
        expect(result.alive_count >= 0).to.equal(true)
        expect(type(result.high_inequality)).to.equal("boolean")
        expect(type(result.population_collapsed)).to.equal("boolean")
    end)

    it("high metabolism causes population collapse", function()
        mock_alc()
        local m = require("sugarscape_abm")
        local collapse_count = 0
        for seed = 1, 10 do
            local result = m.run_single({
                grid_size = 15,
                n_agents = 50,
                max_sugar = 2,
                regrow_rate = 1,
                metabolism_range = { 4, 6 },
                vision_range = { 1, 2 },
                initial_wealth_range = { 3, 8 },
                steps = 50,
            }, seed * 1000)
            if result.population_collapsed then
                collapse_count = collapse_count + 1
            end
        end
        expect(collapse_count >= 5).to.equal(true)
    end)

    it("produces wealth inequality", function()
        mock_alc()
        local m = require("sugarscape_abm")
        -- With heterogeneous metabolism/vision, Gini should be > 0
        local result = m.run_single({
            grid_size = 20,
            n_agents = 60,
            max_sugar = 4,
            metabolism_range = { 1, 4 },
            vision_range = { 1, 6 },
            steps = 80,
        }, 42)
        expect(result.gini > 0).to.equal(true)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("sugarscape_abm")
        local ctx = m.run({
            grid_size = 10,
            n_agents = 20,
            steps = 15,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.gini_median).to_not.equal(nil)
        expect(ctx.result.simulation.survival_rate_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)

-- ================================================================
-- boids_abm
-- ================================================================
describe("boids_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("boids_abm")
        expect(m.meta.name).to.equal("boids_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("boids_abm")
        local result = m.run_single({
            n_boids = 20,
            steps = 30,
            world_size = 200,
        }, 42)
        expect(type(result.avg_nearest_distance)).to.equal("number")
        expect(result.avg_nearest_distance >= 0).to.equal(true)
        expect(result.alignment_score >= -1).to.equal(true)
        expect(result.alignment_score <= 1).to.equal(true)
        expect(result.clusters >= 1).to.equal(true)
        expect(type(result.cohesive_flock)).to.equal("boolean")
        expect(type(result.scattered)).to.equal("boolean")
    end)

    it("strong cohesion produces fewer clusters", function()
        mock_alc()
        local m = require("boids_abm")
        -- High cohesion weight → should tend toward fewer clusters
        local cohesive_clusters = 0
        local scattered_clusters = 0
        for seed = 1, 5 do
            local r1 = m.run_single({
                n_boids = 30, steps = 80, world_size = 200,
                separation_weight = 0.5, alignment_weight = 1.0,
                cohesion_weight = 3.0, perception_radius = 80,
            }, seed * 1000)
            local r2 = m.run_single({
                n_boids = 30, steps = 80, world_size = 200,
                separation_weight = 3.0, alignment_weight = 0.2,
                cohesion_weight = 0.1, perception_radius = 20,
            }, seed * 1000)
            cohesive_clusters = cohesive_clusters + r1.clusters
            scattered_clusters = scattered_clusters + r2.clusters
        end
        -- On average, high cohesion should produce fewer clusters
        expect(cohesive_clusters <= scattered_clusters).to.equal(true)
    end)

    it("zero-boid edge case", function()
        mock_alc()
        local m = require("boids_abm")
        local result = m.run_single({
            n_boids = 1,
            steps = 10,
            world_size = 100,
        }, 42)
        expect(result.clusters).to.equal(1)
        expect(result.alignment_score).to.equal(1.0)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("boids_abm")
        local ctx = m.run({
            n_boids = 15,
            steps = 20,
            world_size = 150,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.alignment_score_median).to_not.equal(nil)
        expect(ctx.result.simulation.clusters_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)
