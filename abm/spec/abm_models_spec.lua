--- Tests for concrete ABM model packages:
--- opinion_abm, evogame_abm, epidemic_abm, schelling_abm
--- Pure computation tests (no LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────
-- Per README §"Adding a new test file": `package.path` is set by the MCP
-- harness via `search_paths=[REPO]`. Do NOT prepend os.getenv("PWD") here
-- — in worktree context PWD points at the parent repo, which silently
-- shadows the worktree's code and produces false-green pass reports.

local PKG_NAMES = {
    "abm", "abm.frame.agent", "abm.frame.model",
    "abm.frame.scheduler", "abm.mc", "abm.sweep", "abm.stats",
    "opinion_abm", "evogame_abm", "epidemic_abm", "schelling_abm",
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
-- opinion_abm — Hegselmann-Krause
-- ================================================================
describe("opinion_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("opinion_abm")
        expect(m.meta.name).to.equal("opinion_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("opinion_abm")
        local result = m.run_single({
            n_agents = 20,
            epsilon = 0.25,
            steps = 30,
        }, 42)
        expect(type(result.clusters)).to.equal("number")
        expect(result.clusters >= 1).to.equal(true)
        expect(type(result.variance)).to.equal("number")
        expect(type(result.converged)).to.equal("boolean")
    end)

    it("high epsilon produces consensus", function()
        mock_alc()
        local m = require("opinion_abm")
        -- epsilon > 0.5 should lead to consensus in most cases
        local consensus_count = 0
        for seed = 1, 10 do
            local result = m.run_single({
                n_agents = 30,
                epsilon = 0.6,
                steps = 100,
            }, seed * 1000)
            if result.consensus then consensus_count = consensus_count + 1 end
        end
        -- Most runs should converge to consensus
        expect(consensus_count >= 7).to.equal(true)
    end)

    it("low epsilon produces fragmentation", function()
        mock_alc()
        local m = require("opinion_abm")
        local result = m.run_single({
            n_agents = 30,
            epsilon = 0.05,
            steps = 50,
        }, 42)
        expect(result.clusters > 3).to.equal(true)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("opinion_abm")
        local ctx = m.run({
            task = "Test opinion dynamics",
            n_agents = 15,
            epsilon = 0.3,
            steps = 20,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.params.epsilon).to.equal(0.3)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.clusters_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)

-- ================================================================
-- evogame_abm — Evolutionary Game Theory
-- ================================================================
describe("evogame_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("evogame_abm")
        expect(m.meta.name).to.equal("evogame_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("exposes payoff matrices", function()
        mock_alc()
        local m = require("evogame_abm")
        expect(m.PD_PAYOFF).to_not.equal(nil)
        expect(m.PD_PAYOFF.CC[1]).to.equal(3)
        expect(m.PD_PAYOFF.DD[1]).to.equal(1)
        expect(m.HD_PAYOFF).to_not.equal(nil)
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("evogame_abm")
        local result = m.run_single({
            n_agents = 20,
            generations = 10,
            rounds_per_gen = 5,
            mutation_rate = 0.05,
        }, 42)
        expect(type(result.dominant_strategy)).to.equal("string")
        expect(result.dominant_fraction > 0).to.equal(true)
        expect(result.dominant_fraction <= 1).to.equal(true)
        expect(result.cooperation_rate >= 0).to.equal(true)
        expect(result.cooperation_rate <= 1).to.equal(true)
        expect(result.n_strategies_surviving >= 1).to.equal(true)
    end)

    it("all-defect population stays defective", function()
        mock_alc()
        local m = require("evogame_abm")
        local result = m.run_single({
            n_agents = 20,
            generations = 10,
            rounds_per_gen = 5,
            mutation_rate = 0.0,  -- no mutation
            strategies = { "always_defect" },
        }, 42)
        expect(result.dominant_strategy).to.equal("always_defect")
        expect(result.cooperation_rate).to.equal(0)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("evogame_abm")
        local ctx = m.run({
            task = "Test evolutionary dynamics",
            n_agents = 15,
            generations = 8,
            rounds_per_gen = 3,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.cooperation_rate_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)

-- ================================================================
-- epidemic_abm — SIR Model
-- ================================================================
describe("epidemic_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("epidemic_abm")
        expect(m.meta.name).to.equal("epidemic_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("epidemic_abm")
        local result = m.run_single({
            n_agents = 100,
            initial_infected = 3,
            beta = 0.3,
            gamma = 0.1,
            contacts_per_step = 5,
            steps = 50,
        }, 42)
        expect(result.attack_rate >= 0).to.equal(true)
        expect(result.attack_rate <= 1).to.equal(true)
        expect(result.peak_infected >= 1).to.equal(true)
        expect(type(result.epidemic_occurred)).to.equal("boolean")
        expect(result.r0_empirical > 0).to.equal(true)
    end)

    it("high R0 produces epidemic", function()
        mock_alc()
        local m = require("epidemic_abm")
        -- R0 = beta * contacts / gamma = 0.5 * 8 / 0.1 = 40
        local epidemic_count = 0
        for seed = 1, 10 do
            local result = m.run_single({
                n_agents = 100,
                initial_infected = 3,
                beta = 0.5,
                gamma = 0.1,
                contacts_per_step = 8,
                steps = 100,
            }, seed * 1000)
            if result.epidemic_occurred then epidemic_count = epidemic_count + 1 end
        end
        expect(epidemic_count >= 8).to.equal(true)
    end)

    it("R0 < 1 suppresses epidemic", function()
        mock_alc()
        local m = require("epidemic_abm")
        -- R0 = 0.05 * 2 / 0.5 = 0.2
        local no_epidemic_count = 0
        for seed = 1, 10 do
            local result = m.run_single({
                n_agents = 100,
                initial_infected = 2,
                beta = 0.05,
                gamma = 0.5,
                contacts_per_step = 2,
                steps = 50,
            }, seed * 1000)
            if not result.epidemic_occurred then no_epidemic_count = no_epidemic_count + 1 end
        end
        expect(no_epidemic_count >= 7).to.equal(true)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("epidemic_abm")
        local ctx = m.run({
            task = "Test epidemic spread",
            n_agents = 50,
            initial_infected = 2,
            beta = 0.3,
            gamma = 0.1,
            steps = 30,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.attack_rate_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)

-- ================================================================
-- schelling_abm — Schelling Segregation
-- ================================================================
describe("schelling_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("schelling_abm")
        expect(m.meta.name).to.equal("schelling_abm")
        expect(m.meta.category).to.equal("simulation")
    end)

    it("run_single produces valid output", function()
        mock_alc()
        local m = require("schelling_abm")
        local result = m.run_single({
            grid_size = 10,
            threshold = 0.375,
            density = 0.8,
            steps = 30,
        }, 42)
        expect(result.initial_segregation >= 0).to.equal(true)
        expect(result.initial_segregation <= 1).to.equal(true)
        expect(result.final_segregation >= 0).to.equal(true)
        expect(result.final_segregation <= 1).to.equal(true)
        expect(type(result.converged)).to.equal("boolean")
        expect(result.steps_to_converge >= 1).to.equal(true)
    end)

    it("threshold=0 means everyone is happy (no movement)", function()
        mock_alc()
        local m = require("schelling_abm")
        local result = m.run_single({
            grid_size = 10,
            threshold = 0.0,
            density = 0.8,
            steps = 50,
        }, 42)
        -- With threshold=0, everyone is satisfied immediately
        expect(result.converged).to.equal(true)
        expect(result.steps_to_converge).to.equal(1)
    end)

    it("moderate threshold increases segregation", function()
        mock_alc()
        local m = require("schelling_abm")
        local result = m.run_single({
            grid_size = 15,
            threshold = 0.4,
            density = 0.8,
            steps = 100,
        }, 42)
        -- Segregation should increase from random initial state
        expect(result.segregation_increase >= 0).to.equal(true)
        expect(result.final_segregation > result.initial_segregation).to.equal(true)
    end)

    it("M.run(ctx) returns complete result", function()
        mock_alc()
        local m = require("schelling_abm")
        local ctx = m.run({
            task = "Test segregation dynamics",
            grid_size = 8,
            threshold = 0.375,
            density = 0.7,
            steps = 20,
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.simulation.runs).to.equal(10)
        expect(ctx.result.simulation.final_segregation_median).to_not.equal(nil)
        expect(ctx.result.sensitivity).to_not.equal(nil)
    end)
end)
