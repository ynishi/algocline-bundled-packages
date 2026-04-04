--- Tests for abm framework + hybrid_abm
--- Structural tests + simulation logic tests (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local PKG_NAMES = {
    "abm", "abm.frame.agent", "abm.frame.model",
    "abm.frame.scheduler", "abm.mc", "abm.sweep", "abm.stats",
    "hybrid_abm",
}

--- Simple xorshift32 PRNG for tests (no alc.math dependency).
local function test_rng(seed)
    local state = seed or 12345
    return function()
        state = state ~ (state << 13)
        state = state ~ (state >> 17)
        state = state ~ (state << 5)
        -- Lua 5.4 integers: mask to 32 bits, normalize to [0,1)
        state = state & 0xFFFFFFFF
        return state / 0x100000000
    end
end

--- Build a mock alc global with alc.math and alc.llm_json.
local function mock_alc(opts)
    opts = opts or {}
    local call_log = {}

    local llm_fn = opts.llm_fn or function() return "mock" end
    local llm_json_fn = opts.llm_json_fn or function() return {} end

    local a = {
        llm = function(prompt, o)
            call_log[#call_log + 1] = { type = "llm", prompt = prompt, opts = o }
            return llm_fn(prompt, o, #call_log)
        end,
        llm_json = function(prompt, o)
            call_log[#call_log + 1] = { type = "llm_json", prompt = prompt, opts = o }
            return llm_json_fn(prompt, o, #call_log)
        end,
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
                if n % 2 == 1 then
                    return sorted[math.ceil(n / 2)]
                else
                    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
                end
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
            wilson_ci = function(count, total, confidence)
                -- Simplified mock: just return rate ± 0.05
                local rate = total > 0 and count / total or 0
                return {
                    lower = math.max(0, rate - 0.05),
                    upper = math.min(1, rate + 0.05),
                }
            end,
        },
    }
    _G.alc = a
    return call_log
end

--- Reset alc and unload all packages from cache.
local function reset()
    _G.alc = nil
    for _, name in ipairs(PKG_NAMES) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- abm.frame.agent
-- ================================================================
describe("abm.frame.agent", function()
    lust.after(reset)

    it("define validates step function", function()
        mock_alc()
        local Agent = require("abm.frame.agent")
        local ok, err = pcall(Agent.define, {})
        expect(ok).to.equal(false)
        expect(err:match("step must be a function")).to_not.equal(nil)
    end)

    it("define + new creates agent with state", function()
        mock_alc()
        local Agent = require("abm.frame.agent")
        local spec = Agent.define {
            state = { hp = 100, tag = "warrior" },
            step = function(self, model)
                self.state.hp = self.state.hp - 10
            end,
        }
        local a = Agent.new(spec)
        expect(a.state.hp).to.equal(100)
        expect(a.state.tag).to.equal("warrior")
        expect(Agent.is_agent(a)).to.equal(true)
    end)

    it("new applies state override", function()
        mock_alc()
        local Agent = require("abm.frame.agent")
        local spec = Agent.define {
            state = { hp = 100 },
            step = function() end,
        }
        local a = Agent.new(spec, { hp = 50, name = "weak" })
        expect(a.state.hp).to.equal(50)
        expect(a.state.name).to.equal("weak")
    end)

    it("populate creates N independent instances", function()
        mock_alc()
        local Agent = require("abm.frame.agent")
        local spec = Agent.define {
            state = { budget = 0 },
            step = function() end,
        }
        local agents = Agent.populate(spec, 5, function(i)
            return { budget = i * 100 }
        end)
        expect(#agents).to.equal(5)
        expect(agents[1].state.budget).to.equal(100)
        expect(agents[5].state.budget).to.equal(500)
        -- Verify independence (mutating one doesn't affect another)
        agents[1].state.budget = 999
        expect(agents[2].state.budget).to.equal(200)
    end)

    it("is_agent rejects spec and non-agents", function()
        mock_alc()
        local Agent = require("abm.frame.agent")
        local spec = Agent.define { step = function() end }
        expect(Agent.is_agent(spec)).to.equal(false)
        expect(Agent.is_agent({})).to.equal(false)
        expect(Agent.is_agent("string")).to.equal(false)
    end)
end)

-- ================================================================
-- abm.frame.scheduler
-- ================================================================
describe("abm.frame.scheduler", function()
    lust.after(reset)

    it("sequential preserves order", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = { { id = 1 }, { id = 2 }, { id = 3 } }
        local result = S.sequential(agents, test_rng(1))
        expect(result[1].id).to.equal(1)
        expect(result[3].id).to.equal(3)
    end)

    it("shuffle returns same elements, possibly different order", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = {}
        for i = 1, 20 do agents[i] = { id = i } end
        local result = S.shuffle(agents, test_rng(42))
        expect(#result).to.equal(20)
        -- All elements present
        local seen = {}
        for _, a in ipairs(result) do seen[a.id] = true end
        for i = 1, 20 do expect(seen[i]).to.equal(true) end
    end)

    it("reverse reverses order", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = { { id = 1 }, { id = 2 }, { id = 3 } }
        local result = S.reverse(agents, test_rng(1))
        expect(result[1].id).to.equal(3)
        expect(result[3].id).to.equal(1)
    end)

    it("filter_tag selects matching agents", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = {
            { state = { tag = "buyer" } },
            { state = { tag = "seller" } },
            { state = { tag = "buyer" } },
        }
        local result = S.filter_tag("buyer", S.sequential)(agents, test_rng(1))
        expect(#result).to.equal(2)
    end)

    it("concat joins two schedulers", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = {
            { state = { tag = "a" } },
            { state = { tag = "b" } },
            { state = { tag = "a" } },
            { state = { tag = "b" } },
        }
        local sched = S.concat(
            S.filter_tag("a", S.sequential),
            S.filter_tag("b", S.sequential)
        )
        local result = sched(agents, test_rng(1))
        expect(#result).to.equal(4)
        expect(result[1].state.tag).to.equal("a")
        expect(result[2].state.tag).to.equal("a")
        expect(result[3].state.tag).to.equal("b")
        expect(result[4].state.tag).to.equal("b")
    end)

    it("pipe composes schedulers sequentially", function()
        mock_alc()
        local S = require("abm.frame.scheduler")
        local agents = {
            { state = { tag = "x" } },
            { state = { tag = "y" } },
            { state = { tag = "x" } },
        }
        -- filter to tag=x, then reverse
        local sched = S.pipe(
            S.filter_tag("x", S.sequential),
            S.reverse
        )
        local result = sched(agents, test_rng(1))
        expect(#result).to.equal(2)
    end)
end)

-- ================================================================
-- abm.frame.model
-- ================================================================
describe("abm.frame.model", function()
    lust.after(reset)

    it("creates model with defaults", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local m = Model.new()
        expect(m._tag).to.equal("abm.model")
        expect(#m.agents).to.equal(0)
        expect(m.step_count).to.equal(0)
    end)

    it("add_agents accepts array", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")
        local spec = Agent.define { step = function() end }
        local m = Model.new()
        Model.add_agents(m, Agent.populate(spec, 3))
        expect(#m.agents).to.equal(3)
    end)

    it("step calls agent step functions", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")
        local S = require("abm.frame.scheduler")

        local spec = Agent.define {
            state = { count = 0 },
            step = function(self, model)
                self.state.count = self.state.count + 1
            end,
        }

        local m = Model.new({ scheduler = S.sequential })
        Model.set_seed(m, 42)
        Model.add_agents(m, Agent.populate(spec, 3))
        Model.step(m)

        expect(m.step_count).to.equal(1)
        expect(m.agents[1].state.count).to.equal(1)
        expect(m.agents[3].state.count).to.equal(1)
    end)

    it("run executes N steps", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")
        local S = require("abm.frame.scheduler")

        local spec = Agent.define {
            state = { count = 0 },
            step = function(self, model)
                self.state.count = self.state.count + 1
            end,
        }

        local m = Model.new({ scheduler = S.sequential })
        Model.set_seed(m, 42)
        Model.add_agents(m, Agent.populate(spec, 2))
        Model.run(m, 10)

        expect(m.step_count).to.equal(10)
        expect(m.agents[1].state.count).to.equal(10)
    end)

    it("on_step hook fires each step", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")
        local S = require("abm.frame.scheduler")

        local hook_calls = {}
        local spec = Agent.define { step = function() end }
        local m = Model.new({
            scheduler = S.sequential,
            on_step = function(model, step_num)
                hook_calls[#hook_calls + 1] = step_num
            end,
        })
        Model.set_seed(m, 1)
        Model.add_agents(m, Agent.populate(spec, 1))
        Model.run(m, 3)

        expect(#hook_calls).to.equal(3)
        expect(hook_calls[1]).to.equal(1)
        expect(hook_calls[3]).to.equal(3)
    end)

    it("get_by_tag filters correctly", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")

        local buyer_spec = Agent.define {
            state = { tag = "buyer" },
            step = function() end,
        }
        local seller_spec = Agent.define {
            state = { tag = "seller" },
            step = function() end,
        }

        local m = Model.new()
        Model.add_agents(m, Agent.populate(buyer_spec, 3))
        Model.add_agents(m, Agent.populate(seller_spec, 2))

        expect(Model.count(m)).to.equal(5)
        expect(#Model.get_by_tag(m, "buyer")).to.equal(3)
        expect(#Model.get_by_tag(m, "seller")).to.equal(2)
    end)

    it("remove_agents removes matching", function()
        mock_alc()
        local Model = require("abm.frame.model")
        local Agent = require("abm.frame.agent")

        local spec = Agent.define {
            state = { hp = 0 },
            step = function() end,
        }

        local m = Model.new()
        Model.add_agents(m, Agent.populate(spec, 5, function(i)
            return { hp = i * 10 }
        end))

        local removed = Model.remove_agents(m, function(a)
            return a.state.hp <= 20
        end)
        expect(removed).to.equal(2)
        expect(#m.agents).to.equal(3)
    end)
end)

-- ================================================================
-- abm.stats
-- ================================================================
describe("abm.stats", function()
    lust.after(reset)

    it("mean computes correctly", function()
        mock_alc()
        local stats = require("abm.stats")
        expect(stats.mean({ 10, 20, 30 })).to.equal(20)
        expect(stats.mean({})).to.equal(0)
    end)

    it("std computes correctly", function()
        mock_alc()
        local stats = require("abm.stats")
        -- std of {2, 4, 4, 4, 5, 5, 7, 9} ≈ 2.138
        local s = stats.std({ 2, 4, 4, 4, 5, 5, 7, 9 })
        expect(s > 2.0).to.equal(true)
        expect(s < 2.3).to.equal(true)
    end)

    it("converged detects stability", function()
        mock_alc()
        local stats = require("abm.stats")
        -- Stable series
        local stable = { 0.5, 0.5, 0.5, 0.5, 0.5 }
        expect(stats.converged(stable, 3, 0.01)).to.equal(true)
        -- Unstable series
        local unstable = { 0.1, 0.9, 0.1, 0.9, 0.1 }
        expect(stats.converged(unstable, 3, 0.01)).to.equal(false)
        -- Too short
        expect(stats.converged({ 1 }, 3, 0.01)).to.equal(false)
    end)

    it("bool_aggregate computes rate and CI", function()
        mock_alc()
        local stats = require("abm.stats")
        local result = stats.bool_aggregate({ true, true, false, true, false })
        expect(result.count).to.equal(3)
        expect(result.total).to.equal(5)
        expect(result.rate).to.equal(0.6)
        expect(result.ci_lower).to_not.equal(nil)
        expect(result.ci_upper).to_not.equal(nil)
    end)

    it("num_aggregate computes median and percentiles", function()
        mock_alc()
        local stats = require("abm.stats")
        local result = stats.num_aggregate({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
        expect(result.median).to_not.equal(nil)
        expect(result.p25).to_not.equal(nil)
        expect(result.p75).to_not.equal(nil)
        expect(result.mean).to.equal(5.5)
    end)
end)

-- ================================================================
-- abm.mc (Monte Carlo runner)
-- ================================================================
describe("abm.mc", function()
    lust.after(reset)

    it("errors without sim_fn", function()
        mock_alc()
        local mc = require("abm.mc")
        local ok, err = pcall(mc.run, { extract = { "x" } })
        expect(ok).to.equal(false)
        expect(err:match("sim_fn required")).to_not.equal(nil)
    end)

    it("aggregates boolean results", function()
        mock_alc()
        local mc = require("abm.mc")
        -- Sim where seed < 150 survives (about 75% of runs 1-200)
        local result = mc.run({
            sim_fn = function(seed)
                return { survived = seed < 150 }
            end,
            runs = 20,
            extract = { "survived" },
            seed_fn = function(i) return i end,
        })
        expect(result.runs).to.equal(20)
        expect(result.survived_rate).to_not.equal(nil)
        expect(type(result.survived_rate)).to.equal("number")
        expect(result.survived_ci).to_not.equal(nil)
    end)

    it("aggregates numeric results", function()
        mock_alc()
        local mc = require("abm.mc")
        local result = mc.run({
            sim_fn = function(seed)
                return { score = seed * 2 }
            end,
            runs = 10,
            extract = { "score" },
            seed_fn = function(i) return i end,
        })
        expect(result.score_median).to_not.equal(nil)
        expect(result.score_p25).to_not.equal(nil)
        expect(result.score_p75).to_not.equal(nil)
        expect(result.score_mean).to_not.equal(nil)
    end)

    it("handles mixed boolean and numeric extract", function()
        mock_alc()
        local mc = require("abm.mc")
        local result = mc.run({
            sim_fn = function(seed)
                return {
                    survived = seed % 2 == 0,
                    users = seed * 10,
                }
            end,
            runs = 20,
            extract = { "survived", "users" },
            seed_fn = function(i) return i end,
        })
        expect(result.survived_rate).to_not.equal(nil)
        expect(result.users_median).to_not.equal(nil)
    end)

    it("calls classify_fn when provided", function()
        mock_alc()
        local mc = require("abm.mc")
        local result = mc.run({
            sim_fn = function(seed) return { v = seed } end,
            runs = 5,
            extract = { "v" },
            classify_fn = function(agg)
                return { position = "test", score = agg.v_median }
            end,
            seed_fn = function(i) return i end,
        })
        expect(result.equilibrium).to_not.equal(nil)
        expect(result.equilibrium.position).to.equal("test")
    end)

    it("run_model integrates Model lifecycle", function()
        mock_alc()
        local mc = require("abm.mc")
        local Agent = require("abm.frame.agent")
        local Model = require("abm.frame.model")
        local S = require("abm.frame.scheduler")

        local counter_spec = Agent.define {
            state = { count = 0 },
            step = function(self, model)
                self.state.count = self.state.count + 1
            end,
        }

        local result = mc.run_model({
            model_fn = function(seed)
                local m = Model.new({ scheduler = S.sequential })
                Model.add_agents(m, Agent.populate(counter_spec, 3))
                return m
            end,
            steps = 10,
            runs = 5,
            extract_fn = function(model)
                return { total_steps = model.agents[1].state.count }
            end,
            extract = { "total_steps" },
        })
        -- Each agent does 10 steps, so total_steps = 10 for all runs
        expect(result.total_steps_median).to.equal(10)
    end)
end)

-- ================================================================
-- abm.sweep (Sensitivity analysis)
-- ================================================================
describe("abm.sweep", function()
    lust.after(reset)

    it("errors without required opts", function()
        mock_alc()
        local sweep = require("abm.sweep")
        local ok, err = pcall(sweep.run, { base_params = { x = 1 } })
        expect(ok).to.equal(false)
        expect(err:match("param_names required")).to_not.equal(nil)
    end)

    it("detects sensitive parameter", function()
        mock_alc()
        local sweep = require("abm.sweep")
        local results = sweep.run({
            base_params = { threshold = 0.5, noise = 0.1 },
            param_names = { "threshold", "noise" },
            eval_fn = function(p)
                -- Only threshold affects outcome
                return p.threshold > 0.6 and 0.0 or 1.0
            end,
        })
        expect(#results > 0).to.equal(true)
        -- threshold should have highest delta
        expect(results[1].param).to.equal("threshold")
        expect(results[1].delta > 0).to.equal(true)
    end)

    it("escalates to wider tier when narrow is flat", function()
        mock_alc()
        local sweep = require("abm.sweep")
        local results = sweep.run({
            base_params = { x = 0.5 },
            param_names = { "x" },
            eval_fn = function(p)
                -- Only sensitive at ±50% (x < 0.25 or x > 0.75)
                if p.x < 0.25 or p.x > 0.75 then return 0.0 end
                return 1.0
            end,
            tiers = { 0.20, 0.50 },
        })
        expect(#results > 0).to.equal(true)
        -- Should be from the 0.50 tier
        expect(results[1].factor).to.equal(0.50)
    end)

    it("returns empty when fully stable", function()
        mock_alc()
        local sweep = require("abm.sweep")
        local results = sweep.run({
            base_params = { x = 0.5 },
            param_names = { "x" },
            eval_fn = function(p) return 1.0 end,
        })
        -- Returns last tier results with zero deltas
        expect(#results > 0).to.equal(true)
        expect(results[1].delta).to.equal(0)
    end)
end)

-- ================================================================
-- abm (integration — init.lua re-exports)
-- ================================================================
describe("abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local abm = require("abm")
        expect(abm.meta).to_not.equal(nil)
        expect(abm.meta.name).to.equal("abm")
        expect(abm.meta.category).to.equal("simulation")
    end)

    it("re-exports all submodules", function()
        mock_alc()
        local abm = require("abm")
        expect(abm.Agent).to_not.equal(nil)
        expect(abm.Model).to_not.equal(nil)
        expect(abm.Scheduler).to_not.equal(nil)
        expect(abm.mc).to_not.equal(nil)
        expect(abm.sweep).to_not.equal(nil)
        expect(abm.stats).to_not.equal(nil)
    end)
end)

-- ================================================================
-- hybrid_abm
-- ================================================================
describe("hybrid_abm", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc()
        local m = require("hybrid_abm")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("hybrid_abm")
        expect(m.meta.category).to.equal("simulation")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc()
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.sim_fn", function()
        mock_alc()
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.sim_fn is required")).to_not.equal(nil)
    end)

    it("runs with pre-supplied params (no LLM)", function()
        mock_alc()
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ctx = m.run({
            task = "Test simulation",
            params = { rate = 0.5 },
            sim_fn = function(params, seed)
                return {
                    survived = params.rate > 0.3,
                    score = params.rate * seed,
                }
            end,
            extract = { "survived", "score" },
            runs = 10,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.params.rate).to.equal(0.5)
        expect(ctx.result.simulation.survived_rate).to.equal(1.0)
        expect(ctx.result.simulation.score_median).to_not.equal(nil)
    end)

    it("extracts params via LLM when param_prompt given", function()
        local log = mock_alc({
            llm_json_fn = function(prompt)
                return { rate = 0.7, threshold = 0.3 }
            end,
        })
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ctx = m.run({
            task = "Test product",
            param_prompt = "Extract params for: %s",
            param_schema = {
                { name = "rate", min = 0.1, max = 1.0, default = 0.5 },
                { name = "threshold", min = 0.0, max = 1.0, default = 0.5 },
            },
            sim_fn = function(params, seed)
                return { survived = params.rate > 0.5 }
            end,
            extract = { "survived" },
            runs = 5,
        })
        -- LLM was called once for param extraction
        expect(#log).to.equal(1)
        expect(log[1].type).to.equal("llm_json")
        -- Params were extracted
        expect(ctx.result.params.rate).to.equal(0.7)
    end)

    it("clamps params to schema bounds", function()
        mock_alc({
            llm_json_fn = function()
                return { rate = 999, threshold = -5 }
            end,
        })
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ctx = m.run({
            task = "Test",
            param_prompt = "Extract: %s",
            param_schema = {
                { name = "rate", min = 0.0, max = 1.0, default = 0.5 },
                { name = "threshold", min = 0.0, max = 1.0, default = 0.5 },
            },
            sim_fn = function(params, seed)
                return { ok = true }
            end,
            extract = { "ok" },
            runs = 3,
        })
        expect(ctx.result.params.rate).to.equal(1.0)
        expect(ctx.result.params.threshold).to.equal(0.0)
    end)

    it("runs sensitivity sweep when schema provided", function()
        mock_alc()
        package.loaded["hybrid_abm"] = nil
        local m = require("hybrid_abm")
        local ctx = m.run({
            task = "Test",
            params = { rate = 0.5, noise = 0.1 },
            param_schema = {
                { name = "rate", min = 0.0, max = 1.0, default = 0.5 },
                { name = "noise", min = 0.0, max = 1.0, default = 0.1 },
            },
            sim_fn = function(params, seed)
                return { survived = params.rate > 0.3 }
            end,
            extract = { "survived" },
            runs = 10,
            sweep_runs = 5,
        })
        expect(ctx.result.sensitivity).to_not.equal(nil)
        expect(type(ctx.result.sensitivity)).to.equal("table")
    end)
end)

-- ================================================================
-- Integration: full ABM pipeline (Agent → Model → MC)
-- ================================================================
describe("abm integration", function()
    lust.after(reset)

    it("runs a complete predator-prey simulation", function()
        mock_alc()
        local abm = require("abm")

        -- Prey and predator specs need to be accessible from step closures.
        -- Use a shared table to hold specs since Lua locals aren't visible
        -- inside define() closures before assignment completes.
        local specs = {}

        specs.prey = abm.Agent.define {
            state = { tag = "prey", alive = true },
            step = function(self, model)
                if not self.state.alive then return end
                -- Reproduce with 20% chance
                if model.rng() < 0.2 then
                    local new_prey = abm.Agent.new(specs.prey, { tag = "prey", alive = true })
                    model.agents[#model.agents + 1] = new_prey
                end
            end,
        }

        specs.predator = abm.Agent.define {
            state = { tag = "predator", energy = 5 },
            step = function(self, model)
                self.state.energy = self.state.energy - 1
                -- Hunt: find a live prey
                for _, a in ipairs(model.agents) do
                    if a.state.tag == "prey" and a.state.alive then
                        a.state.alive = false
                        self.state.energy = self.state.energy + 3
                        break
                    end
                end
                if self.state.energy <= 0 then
                    self.state.tag = "dead"
                end
            end,
        }

        local result = abm.mc.run_model({
            model_fn = function(seed)
                local m = abm.Model.new({ scheduler = abm.Scheduler.shuffle })
                abm.Model.add_agents(m, abm.Agent.populate(specs.prey, 10))
                abm.Model.add_agents(m, abm.Agent.populate(specs.predator, 3))
                return m
            end,
            steps = 5,
            runs = 10,
            extract_fn = function(model)
                local live_prey = abm.Model.count(model, function(a)
                    return a.state.tag == "prey" and a.state.alive
                end)
                return { prey_count = live_prey }
            end,
            extract = { "prey_count" },
        })

        expect(result.runs).to.equal(10)
        expect(result.prey_count_median).to_not.equal(nil)
        expect(type(result.prey_count_median)).to.equal("number")
    end)
end)
