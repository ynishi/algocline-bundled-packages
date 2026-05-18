--- Tests for optimize package (4-component architecture)
--- Tests search strategies, evaluators, stopping criteria, and orchestrator
--- without requiring evalframe (mocked).

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        json_decode = function(s)
            -- Minimal JSON parser for test purposes
            if type(s) ~= "string" then return nil end
            local t = {}
            for k, v in s:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
                local num = tonumber(v)
                if num then
                    t[k] = num
                else
                    t[k] = v:match('^"(.*)"$') or v
                end
            end
            return t
        end,
        json_encode = function(t)
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                if type(v) == "string" then
                    parts[#parts + 1] = string.format('"%s":"%s"', k, v)
                else
                    parts[#parts + 1] = string.format('"%s":%s', k, tostring(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
        tuning = function(defaults, overrides)
            if type(defaults) ~= "table" then return defaults end
            local result = {}
            for k, v in pairs(defaults) do result[k] = v end
            if type(overrides) == "table" then
                for k, v in pairs(overrides) do result[k] = v end
            end
            return result
        end,
        state = {
            _store = {},
            get = function(key) return _G.alc.state._store[key] end,
            set = function(key, val) _G.alc.state._store[key] = val end,
            delete = function(key) _G.alc.state._store[key] = nil end,
            keys = function()
                local ks = {}
                for k in pairs(_G.alc.state._store) do ks[#ks + 1] = k end
                return ks
            end,
        },
        card = {
            _cards = {},
            _samples = {},
            _id_counter = 0,
            create = function(payload)
                _G.alc.card._id_counter = _G.alc.card._id_counter + 1
                local pkg_name = payload.pkg and payload.pkg.name or "unknown"
                local card_id = pkg_name .. "_card_" .. _G.alc.card._id_counter
                payload.card_id = card_id
                _G.alc.card._cards[card_id] = payload
                return { card_id = card_id, path = "/mock/" .. card_id .. ".toml" }
            end,
            write_samples = function(card_id, samples)
                _G.alc.card._samples[card_id] = samples
                return "/mock/" .. card_id .. ".samples.jsonl"
            end,
            get = function(card_id)
                return _G.alc.card._cards[card_id]
            end,
        },
    }
    return call_log
end

local function reset()
    _G.alc = nil
    for k in pairs(package.loaded) do
        if k:match("^optimize") or k:match("^evalframe") then
            package.loaded[k] = nil
        end
    end
end

--- Install a mock evalframe that returns controlled scores
local function install_mock_evalframe(score_fn)
    local eval_call_count = 0
    local mock_suite = {}
    setmetatable(mock_suite, {
        __call = function(_, _name)
            return function(_spec)
                return {
                    run = function()
                        eval_call_count = eval_call_count + 1
                        local score = score_fn(eval_call_count)
                        return {
                            aggregated = { mean = score, std = 0.1, n = 1 },
                            failures = {},
                        }
                    end,
                }
            end
        end,
    })
    local mock_algocline_provider = setmetatable({}, {
        __call = function(_, _opts)
            return function(_input) return { text = "mock", model = "mock" } end
        end,
    })
    package.loaded["evalframe"] = {
        suite = mock_suite,
        providers = { algocline = mock_algocline_provider },
    }
    return function() return eval_call_count end
end

-- ================================================================
-- optimize.search tests
-- ================================================================

describe("optimize.search: parameter utilities", function()
    lust.after(reset)

    it("random_params respects space types", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        local space = {
            x = { type = "int", min = 1, max = 5 },
            y = { type = "float", min = 0.0, max = 1.0 },
            z = { type = "choice", values = { "a", "b", "c" } },
        }
        for _ = 1, 20 do
            local p = search.random_params(space)
            expect(p.x >= 1 and p.x <= 5).to.equal(true)
            expect(p.y >= 0.0 and p.y <= 1.0).to.equal(true)
            local valid_z = p.z == "a" or p.z == "b" or p.z == "c"
            expect(valid_z).to.equal(true)
        end
    end)

    it("grid_params produces cartesian product", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        local space = {
            a = { type = "int", min = 1, max = 3, step = 1 },
            b = { type = "choice", values = { "x", "y" } },
        }
        local grid = search.grid_params(space)
        expect(#grid).to.equal(6) -- 3 * 2
    end)

    it("params_eq checks equality", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        expect(search.params_eq({ a = 1, b = 2 }, { a = 1, b = 2 })).to.equal(true)
        expect(search.params_eq({ a = 1 }, { a = 2 })).to.equal(false)
        expect(search.params_eq({ a = 1 }, { a = 1, b = 2 })).to.equal(false)
    end)
end)

describe("optimize.search: UCB strategy", function()
    lust.after(reset)

    it("init seeds arms from grid for small space", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ucb = search.resolve("ucb")

        local space = { x = { type = "int", min = 1, max = 3 } }
        local state = ucb.init(space, nil)
        expect(#state.arms >= 3).to.equal(true)
    end)

    it("propose returns unpulled arms first (UCB1 = inf)", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ucb = search.resolve("ucb")

        local space = { x = { type = "int", min = 1, max = 3 } }
        local state = ucb.init(space, nil)
        local p = ucb.propose(state)
        expect(p.x).to_not.equal(nil)
    end)

    it("update records score correctly", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ucb = search.resolve("ucb")

        local space = { x = { type = "int", min = 1, max = 3 } }
        local state = ucb.init(space, nil)
        local p = ucb.propose(state)
        state = ucb.update(state, p, 0.8)
        expect(state.total_pulls).to.equal(1)
    end)
end)

describe("optimize.search: OPRO strategy", function()
    lust.after(reset)

    it("falls back to random on first proposal (no history)", function()
        mock_alc(function() return '{"x": 2}' end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local opro = search.resolve("opro")

        local space = { x = { type = "int", min = 1, max = 5 } }
        local state = opro.init(space, nil)
        local p = opro.propose(state)
        expect(p.x >= 1 and p.x <= 5).to.equal(true)
    end)

    it("uses LLM for proposal after history accumulates", function()
        local llm_called = false
        mock_alc(function(prompt)
            if prompt:find("Parameter space") then
                llm_called = true
                return '{"x": 3}'
            end
            return "mock"
        end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local opro = search.resolve("opro")

        local space = { x = { type = "int", min = 1, max = 5 } }
        local history = { results = {
            { params = { x = 1 }, score = 0.3 },
            { params = { x = 2 }, score = 0.5 },
        }}
        local state = opro.init(space, history)
        local p = opro.propose(state)
        expect(llm_called).to.equal(true)
        expect(p.x >= 1 and p.x <= 5).to.equal(true)
    end)
end)

describe("optimize.search: EA strategy", function()
    lust.after(reset)

    it("init seeds population", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ea_s = search.resolve("ea")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = ea_s.init(space, nil)
        expect(#state.population).to.equal(10)
    end)

    it("propose returns valid params", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ea_s = search.resolve("ea")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = ea_s.init(space, nil)
        -- Give population some scores for tournament selection
        for _, ind in ipairs(state.population) do
            ind.score = math.random()
        end
        local p = ea_s.propose(state)
        expect(p.x).to_not.equal(nil)
    end)

    it("update keeps population bounded", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local ea_s = search.resolve("ea")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = ea_s.init(space, nil)
        for i = 1, 25 do
            state = ea_s.update(state, { x = i % 10 + 1 }, math.random())
        end
        expect(#state.population <= 20).to.equal(true)
    end)
end)

describe("optimize.search: greedy strategy", function()
    lust.after(reset)

    it("proposes near current best", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local greedy_s = search.resolve("greedy")

        local space = { x = { type = "int", min = 1, max = 100 } }
        local history = { results = { { params = { x = 50 }, score = 0.9 } } }
        local state = greedy_s.init(space, history)
        -- Collect proposals, most should be near 50
        local near_count = 0
        for _ = 1, 50 do
            local p = greedy_s.propose(state)
            if math.abs(p.x - 50) <= 10 then near_count = near_count + 1 end
        end
        -- At least 60% should be near (80% exploit * ~75% within 10)
        expect(near_count > 20).to.equal(true)
    end)
end)

describe("optimize.search: resolve", function()
    lust.after(reset)

    it("resolves known strategy names", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        for _, name in ipairs({ "ucb", "random", "opro", "ea", "greedy" }) do
            local s = search.resolve(name)
            expect(type(s.init)).to.equal("function")
            expect(type(s.propose)).to.equal("function")
            expect(type(s.update)).to.equal("function")
        end
    end)

    it("errors on unknown strategy", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        local ok, err = pcall(search.resolve, "nonexistent")
        expect(ok).to.equal(false)
        expect(err:match("unknown strategy")).to_not.equal(nil)
    end)

    it("accepts custom strategy table", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")

        local custom = {
            init = function() return {} end,
            propose = function() return { x = 1 } end,
            update = function(s) return s end,
        }
        local s = search.resolve(custom)
        expect(s).to.equal(custom)
    end)
end)

-- ================================================================
-- optimize.stop tests
-- ================================================================

describe("optimize.stop: variance criterion", function()
    lust.after(reset)

    it("does not stop with insufficient data", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local v = stop.resolve("variance")

        local h = { results = { { score = 0.5 }, { score = 0.5 } } }
        local stopped = v.should_stop(h, { window = 5 })
        expect(stopped).to.equal(false)
    end)

    it("stops when scores are constant", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local v = stop.resolve("variance")

        local results = {}
        for _ = 1, 10 do results[#results + 1] = { score = 0.75 } end
        local stopped, reason = v.should_stop({ results = results }, { window = 5 })
        expect(stopped).to.equal(true)
        expect(reason:match("variance converged")).to_not.equal(nil)
    end)
end)

describe("optimize.stop: patience criterion", function()
    lust.after(reset)

    it("stops when no improvement for N rounds", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local p = stop.resolve("patience")

        local results = {
            { score = 0.9 },  -- best
            { score = 0.5 },
            { score = 0.4 },
            { score = 0.3 },
            { score = 0.2 },
            { score = 0.1 },
        }
        local stopped, reason = p.should_stop({ results = results }, { patience = 3 })
        expect(stopped).to.equal(true)
        expect(reason:match("no improvement")).to_not.equal(nil)
    end)

    it("does not stop when improvement occurs", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local p = stop.resolve("patience")

        local results = {
            { score = 0.5 },
            { score = 0.6 },
            { score = 0.5 },
            { score = 0.7 },  -- improved
        }
        local stopped = p.should_stop({ results = results }, { patience = 2 })
        expect(stopped).to.equal(false)
    end)
end)

describe("optimize.stop: threshold criterion", function()
    lust.after(reset)

    it("stops when threshold exceeded", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local t = stop.resolve("threshold")

        local results = { { score = 0.3 }, { score = 0.95 } }
        local stopped, reason = t.should_stop({ results = results }, { target = 0.9 })
        expect(stopped).to.equal(true)
        expect(reason:match("threshold reached")).to_not.equal(nil)
    end)
end)

describe("optimize.stop: composite criterion", function()
    lust.after(reset)

    it("triggers on first matching criterion", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")

        local results = { { score = 0.95 } }
        local c = stop.resolve({
            { "patience", { patience = 10 } },
            { "threshold", { target = 0.9 } },
        })
        local stopped, reason = c.should_stop({ results = results })
        expect(stopped).to.equal(true)
        expect(reason:match("threshold")).to_not.equal(nil)
    end)
end)

describe("optimize.stop: improvement criterion", function()
    lust.after(reset)

    it("does not stop with insufficient data", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local imp = stop.resolve("improvement")

        local results = {}
        for i = 1, 5 do results[#results + 1] = { score = 0.5 + i * 0.01 } end
        local stopped = imp.should_stop({ results = results }, { window = 5 })
        expect(stopped).to.equal(false)
    end)

    it("stops when improvement rate drops below min_rate", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local imp = stop.resolve("improvement")

        local results = {}
        -- First window: scores around 0.5
        for _ = 1, 5 do results[#results + 1] = { score = 0.50 } end
        -- Second window: scores barely changed
        for _ = 1, 5 do results[#results + 1] = { score = 0.501 } end
        local stopped, reason = imp.should_stop({ results = results }, { window = 5, min_rate = 0.01 })
        expect(stopped).to.equal(true)
        expect(reason:match("improvement rate")).to_not.equal(nil)
    end)

    it("does not stop when improvement is sufficient", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.stop"] = nil
        local stop = require("optimize.stop")
        local imp = stop.resolve("improvement")

        local results = {}
        -- First window: low scores
        for _ = 1, 5 do results[#results + 1] = { score = 0.3 } end
        -- Second window: significant improvement
        for _ = 1, 5 do results[#results + 1] = { score = 0.5 } end
        local stopped = imp.should_stop({ results = results }, { window = 5, min_rate = 0.01 })
        expect(stopped).to.equal(false)
    end)
end)

-- ================================================================
-- optimize.eval tests
-- ================================================================

describe("optimize.eval: custom evaluator", function()
    lust.after(reset)

    it("calls user-provided eval_fn", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.eval"] = nil
        local eval = require("optimize.eval")
        local custom = eval.resolve("custom")

        local called_with = nil
        local result = custom.evaluate("my_strategy", { x = 5 }, "scenario", {
            eval_fn = function(target, params, scenario)
                called_with = { target = target, params = params }
                return 0.85
            end,
        })
        expect(called_with.target).to.equal("my_strategy")
        expect(called_with.params.x).to.equal(5)
        expect(result.mean).to.equal(0.85)
    end)

    it("accepts table result from eval_fn", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.eval"] = nil
        local eval = require("optimize.eval")
        local custom = eval.resolve("custom")

        local result = custom.evaluate("s", {}, "sc", {
            eval_fn = function() return { mean = 0.7, std = 0.05, n = 10 } end,
        })
        expect(result.mean).to.equal(0.7)
        expect(result.std).to.equal(0.05)
        expect(result.n).to.equal(10)
    end)
end)

describe("optimize.eval: llm_judge evaluator", function()
    lust.after(reset)

    it("returns LLM-scored result", function()
        mock_alc(function() return "0.72" end)
        package.loaded["optimize.eval"] = nil
        local eval = require("optimize.eval")
        local judge = eval.resolve("llm_judge")

        local result = judge.evaluate("strategy", { x = 3 }, "task desc", {})
        expect(result.mean >= 0 and result.mean <= 1).to.equal(true)
    end)
end)

-- ================================================================
-- Orchestrator integration tests
-- ================================================================

describe("optimize: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.5 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")
        expect(m.meta.name).to.equal("optimize")
        expect(m.meta.version).to.equal("0.3.0")
        expect(m.meta.category).to.equal("optimization")
    end)

    it("exposes submodules", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.5 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")
        expect(m.search).to_not.equal(nil)
        expect(m.eval).to_not.equal(nil)
        expect(m.stop).to_not.equal(nil)
    end)

    it("errors without required fields", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.5 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ok1, e1 = pcall(m.run, { space = {}, scenario = {} })
        expect(ok1).to.equal(false)
        expect(e1:match("ctx.target")).to_not.equal(nil)

        local ok2, e2 = pcall(m.run, { target = "t", scenario = {} })
        expect(ok2).to.equal(false)
        expect(e2:match("ctx.space")).to_not.equal(nil)

        local ok3, e3 = pcall(m.run, { target = "t", space = {} })
        expect(ok3).to.equal(false)
        expect(e3:match("ctx.scenario")).to_not.equal(nil)
    end)
end)

describe("optimize: basic run with UCB", function()
    lust.after(reset)

    it("runs optimization loop and returns best params", function()
        mock_alc(function() return "mock" end)
        local get_count = install_mock_evalframe(function(n)
            return 0.5 + math.random() * 0.3
        end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "mock_strategy",
            space = {
                threshold = { type = "float", min = 1.0, max = 5.0, step = 1.0 },
            },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "test", expected = "result" } },
            },
            rounds = 5,
            search = "ucb",
        })

        expect(ctx.result.status).to_not.equal(nil)
        expect(ctx.result.best_params).to_not.equal(nil)
        expect(ctx.result.best_score > 0).to.equal(true)
        expect(ctx.result.rounds_used <= 5).to.equal(true)
        expect(get_count() > 0).to.equal(true)
    end)
end)

describe("optimize: run with random search", function()
    lust.after(reset)

    it("completes with random strategy", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.6 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "mock_strategy",
            space = { x = { type = "int", min = 1, max = 10 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 3,
            search = "random",
        })

        expect(ctx.result.rounds_used).to.equal(3)
        expect(ctx.result.best_score > 0).to.equal(true)
    end)
end)

describe("optimize: run with custom evaluator", function()
    lust.after(reset)

    it("uses ctx.eval_fn when evaluator is custom", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local eval_calls = 0
        local ctx = m.run({
            target = "mock_strategy",
            space = { x = { type = "int", min = 1, max = 5 } },
            scenario = "mock_scenario",
            rounds = 3,
            search = "random",
            evaluator = "custom",
            eval_fn = function(_target, params, _scenario)
                eval_calls = eval_calls + 1
                return params.x / 5
            end,
        })

        expect(eval_calls).to.equal(3)
        expect(ctx.result.best_score > 0).to.equal(true)
    end)
end)

describe("optimize: convergence with variance stop", function()
    lust.after(reset)

    it("converges when scores are stable", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.75 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "converge_test",
            space = { x = { type = "int", min = 1, max = 2 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 20,
            stop = "variance",
        })

        expect(ctx.result.status).to.equal("converged")
        expect(ctx.result.rounds_used < 20).to.equal(true)
    end)
end)

describe("optimize: patience stop", function()
    lust.after(reset)

    it("stops after N rounds without improvement", function()
        mock_alc(function() return "mock" end)
        local call_n = 0
        install_mock_evalframe(function()
            call_n = call_n + 1
            -- High score first, then low scores
            if call_n == 1 then return 0.9 end
            return 0.3
        end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "patience_test",
            space = { x = { type = "int", min = 1, max = 10 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 20,
            search = "random",
            stop = "patience",
            stop_config = { patience = 3 },
        })

        expect(ctx.result.status).to.equal("converged")
        expect(ctx.result.stop_reason:match("no improvement")).to_not.equal(nil)
    end)
end)

describe("optimize: threshold stop", function()
    lust.after(reset)

    it("stops when target score reached", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.95 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "threshold_test",
            space = { x = { type = "int", min = 1, max = 5 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 10,
            search = "random",
            stop = "threshold",
            stop_config = { target = 0.9 },
        })

        expect(ctx.result.status).to.equal("converged")
        expect(ctx.result.rounds_used).to.equal(1) -- first score already exceeds
    end)
end)

describe("optimize: state persistence", function()
    lust.after(reset)

    it("persists and resumes from alc.state", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.7 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        -- First run
        m.run({
            target = "resume_test",
            space = { x = { type = "int", min = 1, max = 3 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 2,
            search = "random",
        })

        local after_first = alc.state.get("optimize_resume_test")
        local first_count = #after_first.results

        -- Second run (resumes)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        install_mock_evalframe(function() return 0.9 end)
        local m2 = require("optimize")
        m2.run({
            target = "resume_test",
            space = { x = { type = "int", min = 1, max = 3 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 2,
            search = "random",
        })

        local after_second = alc.state.get("optimize_resume_test")
        expect(#after_second.results > first_count).to.equal(true)
    end)
end)

describe("optimize: top_5 ranking", function()
    lust.after(reset)

    it("returns top 5 arms sorted by score", function()
        mock_alc(function() return "mock" end)
        local call_n = 0
        install_mock_evalframe(function()
            call_n = call_n + 1
            return call_n * 0.1
        end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "ranking_test",
            space = { x = { type = "int", min = 1, max = 10 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 8,
            search = "random",
        })

        expect(#ctx.result.top_5 > 0).to.equal(true)
        expect(#ctx.result.top_5 <= 5).to.equal(true)
        if #ctx.result.top_5 >= 2 then
            expect(ctx.result.top_5[1].avg_score >= ctx.result.top_5[2].avg_score).to.equal(true)
        end
    end)
end)

describe("optimize: alc.tuning integration", function()
    lust.after(reset)

    it("merges defaults with arm params", function()
        local tuning_calls = {}
        mock_alc(function() return "mock" end)
        local original_tuning = alc.tuning
        alc.tuning = function(defaults, overrides)
            tuning_calls[#tuning_calls + 1] = {
                defaults = defaults,
                overrides = overrides,
            }
            return original_tuning(defaults, overrides)
        end

        install_mock_evalframe(function() return 0.7 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        m.run({
            target = "tuning_test",
            space = { threshold = { type = "float", min = 1.0, max = 5.0, step = 2.0 } },
            defaults = { threshold = 3.0, other_param = "keep" },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 2,
        })

        expect(#tuning_calls > 0).to.equal(true)
        expect(tuning_calls[1].defaults.other_param).to.equal("keep")
    end)
end)

-- ================================================================
-- auto_card integration tests
-- ================================================================

describe("optimize: auto_card emits Card with two-tier data", function()
    lust.after(reset)

    it("creates Card (Tier 1) and samples (Tier 2) when auto_card=true", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function(n) return 0.5 + n * 0.05 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "card_test_target",
            space = { x = { type = "float", min = 0.0, max = 1.0, step = 0.5 } },
            scenario = {
                name = "test_scenario",
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 3,
            auto_card = true,
        })

        -- card_id should be set in result
        expect(ctx.result.card_id).to_not.equal(nil)

        -- Tier 1: Card body should exist with optimize section
        local card = alc.card.get(ctx.result.card_id)
        expect(card).to_not.equal(nil)
        expect(card.optimize).to_not.equal(nil)
        expect(card.optimize.target).to.equal("card_test_target")
        expect(card.optimize.search).to.equal("ucb")
        expect(card.optimize.evaluator).to.equal("evalframe")
        expect(card.optimize.rounds_used).to.equal(3)
        expect(card.optimize.top_k).to_not.equal(nil)
        expect(card.stats.best_score).to_not.equal(nil)
        expect(card.params).to_not.equal(nil)
        expect(card.pkg.name).to.equal("optimize_card_test_target")

        -- Tier 2: samples sidecar should contain per-round history
        local samples = alc.card._samples[ctx.result.card_id]
        expect(samples).to_not.equal(nil)
        expect(#samples).to.equal(3)
        expect(samples[1].round).to.equal(1)
        expect(samples[1].score).to_not.equal(nil)
        expect(samples[1].params).to_not.equal(nil)
    end)

    it("does not emit Card when auto_card is false/absent", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.7 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "no_card_test",
            space = { x = { type = "float", min = 0.0, max = 1.0, step = 0.5 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 2,
        })

        expect(ctx.result.card_id).to.equal(nil)
    end)

    it("respects card_pkg override", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.8 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "pkg_override_test",
            space = { x = { type = "float", min = 0.0, max = 1.0, step = 0.5 } },
            scenario = {
                name = "test_scn",
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            rounds = 2,
            auto_card = true,
            card_pkg = "my_custom_pkg",
        })

        local card = alc.card.get(ctx.result.card_id)
        expect(card.pkg.name).to.equal("my_custom_pkg")
    end)

    it("scenario name extracted from string scenario", function()
        mock_alc(function() return "mock" end)
        install_mock_evalframe(function() return 0.6 end)
        package.loaded["optimize"] = nil
        package.loaded["optimize.search"] = nil
        package.loaded["optimize.eval"] = nil
        package.loaded["optimize.stop"] = nil
        local m = require("optimize")

        local ctx = m.run({
            target = "scn_name_test",
            space = { x = { type = "float", min = 0.0, max = 1.0, step = 0.5 } },
            scenario = {
                { _is_binding = true },
                cases = { { _is_case = true, input = "t", expected = "r" } },
            },
            scenario_name = "gsm8k_100",
            rounds = 2,
            auto_card = true,
        })

        local card = alc.card.get(ctx.result.card_id)
        expect(card.scenario.name).to.equal("gsm8k_100")
    end)
end)
