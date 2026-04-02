--- Tests for exploration packages: qdaif, falsify, prompt_breed, coevolve
--- Also tests mcts reflection extension and optimize breed strategy
--- Structural tests + mock LLM (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for _, item in ipairs(list) do
                results[#results + 1] = fn(item)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("%d+")) or 5
        end,
        json_decode = function(s)
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
    }
    _G.alc = a
    return call_log
end

local PACKAGES = {
    "qdaif", "falsify", "prompt_breed", "coevolve",
    "mcts", "optimize", "optimize.search",
}

local function reset()
    _G.alc = nil
    for _, name in ipairs(PACKAGES) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- qdaif
-- ================================================================
describe("qdaif", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("qdaif")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("qdaif")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, {
            features = { { name = "style", bins = { "a", "b" } } },
        })
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.features", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, { task = "solve" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.features is required")).to_not.equal(nil)
    end)

    it("errors with single-bin feature", function()
        mock_alc(function() return "mock" end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ok, err = pcall(m.run, {
            task = "solve",
            features = { { name = "x", bins = { "only_one" } } },
        })
        expect(ok).to.equal(false)
        expect(err:match("bins")).to_not.equal(nil)
    end)

    it("seeds archive and runs mutation loop", function()
        local call_n = 0
        local log = mock_alc(function(prompt, opts, n)
            call_n = call_n + 1
            -- Seed generation
            if prompt:match("Generate a high%-quality solution") then
                return "solution candidate " .. call_n
            end
            -- Evaluation: return score + bins
            if prompt:match("SCORE:") or prompt:match("Evaluate this candidate") then
                return "SCORE: 7\nBINS: 1"
            end
            -- Mutation
            if prompt:match("Create a VARIANT") then
                return "mutated variant " .. call_n
            end
            return "mock " .. call_n
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "Write a greeting",
            features = { { name = "tone", bins = { "formal", "casual" } } },
            seed_count = 2,
            iterations = 3,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.best).to_not.equal(nil)
        expect(ctx.result.best_score > 0).to.equal(true)
        expect(ctx.result.stats.total_cells).to.equal(2)
        expect(ctx.result.stats.seed_count).to.equal(2)
        expect(ctx.result.stats.iterations).to.equal(3)
        expect(ctx.result.coverage > 0).to.equal(true)
        -- seed_count * 2 (generate + eval) + iterations * 2 (mutate + eval)
        expect(#log).to.equal(2 * 2 + 3 * 2)
    end)

    it("multi-axis features create correct grid", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "SCORE: 6\nBINS: 1, 2" end
            return "candidate"
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "test",
            features = {
                { name = "style", bins = { "formal", "casual", "technical" } },
                { name = "length", bins = { "short", "long" } },
            },
            seed_count = 1,
            iterations = 1,
        })
        expect(ctx.result.stats.total_cells).to.equal(6) -- 3 * 2
    end)

    it("archive replaces only when score improves", function()
        local eval_scores = { 8, 8, 3 } -- seed=8, seed_eval=8, mutation_eval=3
        local eval_idx = 0
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then
                eval_idx = eval_idx + 1
                local s = eval_scores[eval_idx] or 5
                return string.format("SCORE: %d\nBINS: 1", s)
            end
            return "candidate"
        end)
        package.loaded["qdaif"] = nil
        local m = require("qdaif")
        local ctx = m.run({
            task = "test",
            features = { { name = "x", bins = { "a", "b" } } },
            seed_count = 1,
            iterations = 1,
        })
        -- Best should be from seed (score 8), not mutation (score 3)
        expect(ctx.result.best_score).to.equal(8)
    end)
end)

-- ================================================================
-- falsify
-- ================================================================
describe("falsify", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("falsify")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("falsify")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates initial hypotheses", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose hypothesis") then
                return "Hypothesis text " .. n
            end
            if prompt:match("DISPROVE") then
                return "Cannot find counterexample"
            end
            if prompt:match("Judge the falsification") then
                return "SURVIVED"
            end
            if prompt:match("Synthesize") then
                return "Final synthesis"
            end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Why is the sky blue?",
            initial_hypotheses = 2,
            max_rounds = 1,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.stats.initial_count).to.equal(2)
        expect(ctx.result.stats.total_survived).to.equal(2)
        expect(#ctx.result.survivors).to.equal(2)
        expect(ctx.result.answer).to.equal("Final synthesis")
    end)

    it("refutes hypotheses and derives successors", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose hypothesis") then
                return "Hypothesis " .. n
            end
            if prompt:match("DISPROVE") then
                return "Found clear counterexample: X contradicts the hypothesis"
            end
            if prompt:match("Judge the falsification") then
                return "REFUTED"
            end
            if prompt:match("IMPROVED hypothesis") then
                return "Derived successor hypothesis"
            end
            if prompt:match("Synthesize") or prompt:match("All hypotheses were refuted") then
                return "Synthesis from survivors"
            end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Analyze X",
            initial_hypotheses = 2,
            max_rounds = 1,
            derive_on_refute = true,
        })
        expect(ctx.result.stats.total_refuted > 0).to.equal(true)
        expect(ctx.result.stats.total_derived > 0).to.equal(true)
        -- Total generated = initial + derived
        expect(ctx.result.stats.total_generated > 2).to.equal(true)
    end)

    it("respects derive_on_refute=false", function()
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then return "Counterexample found" end
            if prompt:match("Judge") then return "REFUTED" end
            if prompt:match("refuted") then return "Answer from nothing" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 2,
            max_rounds = 1,
            derive_on_refute = false,
        })
        expect(ctx.result.stats.total_derived).to.equal(0)
        expect(ctx.result.stats.total_generated).to.equal(2)
    end)

    it("weakened verdict lowers confidence but keeps active", function()
        local round = 0
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then
                round = round + 1
                return "Partial flaw found"
            end
            if prompt:match("Judge") then return "WEAKENED" end
            if prompt:match("Synthesize") then return "Answer" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 1,
            max_rounds = 2,
        })
        -- Weakened twice: 0.5 - 0.2 - 0.2 = 0.1
        local h = ctx.result.all_hypotheses[1]
        expect(h.status).to.equal("survived")
        expect(h.confidence < 0.5).to.equal(true)
    end)

    it("max_hypotheses limits derived count", function()
        mock_alc(function(prompt)
            if prompt:match("Propose hypothesis") then return "H" end
            if prompt:match("DISPROVE") then return "counter" end
            if prompt:match("Judge") then return "REFUTED" end
            if prompt:match("IMPROVED") then return "derived" end
            if prompt:match("Synthesize") or prompt:match("refuted") then return "A" end
            return "mock"
        end)
        package.loaded["falsify"] = nil
        local m = require("falsify")

        -- max_hypotheses=3: 5 initial hypotheses, all refuted in round 1.
        -- After each refute, active_count = remaining_active + new_hypotheses.
        -- 1st refute: 4 active + 0 new = 4 ≥ 3 → NO derive
        -- 2nd refute: 3 active + 0 new = 3 ≥ 3 → NO derive
        -- 3rd refute: 2 active + 0 new = 2 < 3 → derive → 1 new
        -- 4th refute: 1 active + 1 new = 2 < 3 → derive → 2 new
        -- 5th refute: 0 active + 2 new = 2 < 3 → derive → 3 new
        -- Total derived in round 1 = 3 (not 5)
        local ctx = m.run({
            task = "Test",
            initial_hypotheses = 5,
            max_rounds = 1,
            max_hypotheses = 3,
        })
        -- Should derive fewer than refuted due to cap
        expect(ctx.result.stats.total_refuted).to.equal(5)
        expect(ctx.result.stats.total_derived).to.equal(3)
    end)
end)

-- ================================================================
-- prompt_breed
-- ================================================================
describe("prompt_breed", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("prompt_breed")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("prompt_breed")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["prompt_breed"] = nil
        local m = require("prompt_breed")
        local ok, err = pcall(m.run, { evaluator = "test criteria" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.evaluator", function()
        mock_alc(function() return "mock" end)
        package.loaded["prompt_breed"] = nil
        local m = require("prompt_breed")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.evaluator is required")).to_not.equal(nil)
    end)

    it("evolves population across generations", function()
        local gen_count = 0
        local log = mock_alc(function(prompt, opts, n)
            -- Init prompts
            if prompt:match("Generate a task INSTRUCTION") then
                return "Instruction variant " .. n
            end
            -- Evaluation
            if prompt:match("Rate this instruction") then
                gen_count = gen_count + 1
                return tostring(math.min(10, 5 + math.floor(gen_count / 3)))
            end
            -- Mutation
            if prompt:match("Apply the mutation strategy") then
                return "Mutated instruction " .. n
            end
            -- Crossover
            if prompt:match("Combine the best elements") then
                return "Crossover instruction " .. n
            end
            -- Hyper-mutation
            if prompt:match("Improve this meta%-instruction") then
                return "Improved mutation strategy"
            end
            return "mock " .. n
        end)
        package.loaded["prompt_breed"] = nil
        local m = require("prompt_breed")
        local ctx = m.run({
            task = "Math problem solving",
            evaluator = "How well does this instruction help solve math?",
            population_size = 4,
            generations = 3,
            mutation_pool = 2,
            hyper_mutation_rate = 0.0, -- disable for deterministic test
            crossover_rate = 0.0,      -- mutation only for deterministic test
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.best_prompt).to_not.equal(nil)
        expect(ctx.result.best_score > 0).to.equal(true)
        expect(#ctx.result.population).to.equal(4)
        expect(#ctx.result.evolution_history).to.equal(3)
        expect(ctx.result.stats.generations).to.equal(3)
        expect(ctx.result.stats.population_size).to.equal(4)
    end)

    it("mutation prompts are present in result", function()
        mock_alc(function(prompt)
            if prompt:match("Rate this instruction") then return "7" end
            return "mock output"
        end)
        package.loaded["prompt_breed"] = nil
        local m = require("prompt_breed")
        local ctx = m.run({
            task = "Test",
            evaluator = "Quality criteria",
            population_size = 2,
            generations = 1,
            mutation_pool = 3,
            hyper_mutation_rate = 0.0,
        })
        expect(#ctx.result.mutation_prompts).to.equal(3)
    end)

    it("population is ranked by score descending", function()
        local score_map = {}
        mock_alc(function(prompt)
            if prompt:match("Generate a task INSTRUCTION") then
                return "instruction"
            end
            if prompt:match("Rate this instruction") then
                return tostring(math.random(3, 9))
            end
            return "mock"
        end)
        package.loaded["prompt_breed"] = nil
        local m = require("prompt_breed")
        local ctx = m.run({
            task = "Test",
            evaluator = "Criteria",
            population_size = 4,
            generations = 2,
            hyper_mutation_rate = 0.0,
        })
        local pop = ctx.result.population
        for i = 1, #pop - 1 do
            expect(pop[i].score >= pop[i + 1].score).to.equal(true)
        end
    end)
end)

-- ================================================================
-- coevolve
-- ================================================================
describe("coevolve", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("coevolve")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("coevolve")
        expect(m.meta.category).to.equal("exploration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates seed problems when none provided", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Problem: what is 2+2?" end
            if prompt:match("Solve this problem") then return "The answer is 4" end
            if prompt:match("Judge the answer") then return "CORRECT\nWell done" end
            if prompt:match("CHALLENGER") then return "Problem: what is 3*7?" end
            if prompt:match("everything you learned") then return "Final comprehensive answer" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Arithmetic reasoning",
            rounds = 2,
            problems_per_round = 2,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.answer).to.equal("Final comprehensive answer")
        expect(#ctx.result.round_stats).to.equal(2)
        expect(ctx.result.total_problems > 0).to.equal(true)
    end)

    it("accepts seed_problems", function()
        mock_alc(function(prompt)
            if prompt:match("Solve") then return "answer" end
            if prompt:match("Judge") then return "CORRECT\nGood" end
            if prompt:match("CHALLENGER") then return "New problem" end
            if prompt:match("battle%-tested") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Math",
            seed_problems = { "What is 1+1?", "What is 2*3?" },
            rounds = 1,
        })
        expect(ctx.result.total_problems).to.equal(2)
    end)

    it("tracks correct/partial/wrong counts", function()
        local judge_n = 0
        mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Problem" end
            if prompt:match("Solve this problem") then return "answer" end
            if prompt:match("Judge the answer") then
                judge_n = judge_n + 1
                if judge_n == 1 then return "CORRECT\nRight" end
                if judge_n == 2 then return "WRONG\nIncorrect" end
                return "PARTIAL\nAlmost"
            end
            if prompt:match("everything you learned") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Test",
            rounds = 1,
            problems_per_round = 3,
        })
        expect(ctx.result.total_correct).to.equal(1)
        expect(ctx.result.total_wrong).to.equal(1)
        expect(ctx.result.total_partial).to.equal(1)
    end)

    it("difficulty adjusts based on success rate", function()
        mock_alc(function(prompt)
            if prompt:match("Generate problem") then return "Easy problem" end
            if prompt:match("Solve") then return "correct answer" end
            if prompt:match("Judge") then return "CORRECT\nPerfect" end
            if prompt:match("CHALLENGER") then return "Should be harder" end
            if prompt:match("battle%-tested") then return "Final" end
            return "mock"
        end)
        package.loaded["coevolve"] = nil
        local m = require("coevolve")
        local ctx = m.run({
            task = "Test",
            rounds = 2,
            problems_per_round = 2,
            difficulty_target = 0.5,
        })
        -- All correct → success_rate=1.0 > target+0.2 → "harder"
        expect(ctx.result.round_stats[1].success_rate).to.equal(1.0)
        expect(ctx.result.round_stats[1].difficulty_hint:match("harder")).to_not.equal(nil)
    end)
end)

-- ================================================================
-- mcts reflection extension
-- ================================================================
describe("mcts: reflection", function()
    lust.after(reset)

    it("works without reflection (backward compatible)", function()
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought " .. n
            end
            if prompt:match("Continue this reasoning") then
                return "Continued reasoning"
            end
            if prompt:match("Rate this reasoning") then
                return "7"
            end
            if prompt:match("Synthesize") then
                return "Final answer"
            end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        local ctx = m.run({
            task = "Solve X",
            iterations = 2,
            max_depth = 2,
            -- reflection not set → default false
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.conclusion).to.equal("Final answer")
        -- No reflection calls should appear
        local reflection_calls = 0
        for _, c in ipairs(log) do
            if c.prompt:match("why this reasoning path scored poorly") then
                reflection_calls = reflection_calls + 1
            end
        end
        expect(reflection_calls).to.equal(0)
    end)

    it("generates reflections on low-score paths", function()
        local score_n = 0
        local log = mock_alc(function(prompt, opts, n)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought"
            end
            if prompt:match("Continue") then return "Continued" end
            if prompt:match("Rate this reasoning") then
                score_n = score_n + 1
                -- First iteration: low score triggers reflection
                -- Second: high score, no reflection
                if score_n == 1 then return "2" end
                return "8"
            end
            if prompt:match("why this reasoning path scored poorly") then
                return "The approach was too vague"
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        local ctx = m.run({
            task = "Solve X",
            iterations = 2,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 4,
        })
        -- Should have at least one reflection call
        local reflection_calls = 0
        for _, c in ipairs(log) do
            if c.prompt:match("why this reasoning path scored poorly") then
                reflection_calls = reflection_calls + 1
            end
        end
        expect(reflection_calls).to.equal(1)
    end)

    it("injects reflections into expansion prompts", function()
        local score_n = 0
        local saw_lessons = false
        mock_alc(function(prompt, opts, n)
            if prompt:match("Lessons from failed paths") then
                saw_lessons = true
            end
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step thought"
            end
            if prompt:match("Continue") then return "Continued" end
            if prompt:match("Rate this reasoning") then
                score_n = score_n + 1
                if score_n <= 2 then return "2" end -- low scores
                return "8"
            end
            if prompt:match("why this reasoning path scored poorly") then
                return "Wrong approach used"
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        m.run({
            task = "Solve X",
            iterations = 4,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 4,
        })
        -- After first low-score iteration, subsequent expansions should see lessons
        expect(saw_lessons).to.equal(true)
    end)

    it("respects max_reflections buffer size", function()
        local reflection_count = 0
        mock_alc(function(prompt)
            if prompt:match("Propose") or prompt:match("next reasoning") then
                return "Step"
            end
            if prompt:match("Continue") then return "Cont" end
            if prompt:match("Rate this reasoning") then return "1" end -- always low
            if prompt:match("why this reasoning path scored poorly") then
                reflection_count = reflection_count + 1
                return "Reflection #" .. reflection_count
            end
            if prompt:match("Synthesize") then return "Final" end
            return "mock"
        end)
        package.loaded["mcts"] = nil
        local m = require("mcts")
        m.run({
            task = "Solve",
            iterations = 6,
            max_depth = 2,
            reflection = true,
            reflection_threshold = 5,
            max_reflections = 3,
        })
        -- Should generate reflections but buffer capped at 3
        -- (older ones evicted via FIFO)
        expect(reflection_count).to.equal(6) -- one per iteration
    end)
end)

-- ================================================================
-- optimize.search: breed strategy
-- ================================================================
describe("optimize.search: breed strategy", function()
    lust.after(reset)

    it("is registered in strategies", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local s = search.resolve("breed")
        expect(type(s.init)).to.equal("function")
        expect(type(s.propose)).to.equal("function")
        expect(type(s.update)).to.equal("function")
    end)

    it("init creates population and mutation prompts", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = breed.init(space, nil)
        expect(#state.population).to.equal(10)
        expect(#state.mutation_prompts >= 3).to.equal(true)
        expect(state.hyper_mutation_rate).to.equal(0.15)
    end)

    it("init seeds from history when available", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local history = {
            results = {
                { params = { x = 3 }, score = 0.8 },
                { params = { x = 7 }, score = 0.9 },
            },
        }
        local state = breed.init(space, history)
        expect(#state.population).to.equal(2)
        expect(state.population[1].score).to.equal(0.9) -- sorted desc
    end)

    it("propose uses LLM for mutation", function()
        local llm_called = false
        mock_alc(function(prompt)
            if prompt:match("Mutation strategy") then
                llm_called = true
                return '{"x": 5}'
            end
            return "mock"
        end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = breed.init(space, nil)
        -- Give population scores for tournament
        for _, ind in ipairs(state.population) do
            ind.score = math.random()
        end
        local p = breed.propose(state)
        expect(llm_called).to.equal(true)
        expect(p.x >= 1 and p.x <= 10).to.equal(true)
    end)

    it("propose falls back to EA-style on parse failure", function()
        mock_alc(function() return "not valid json at all" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = breed.init(space, nil)
        for _, ind in ipairs(state.population) do
            ind.score = math.random()
        end
        -- Should not error even with bad LLM output
        local p = breed.propose(state)
        expect(p.x >= 1 and p.x <= 10).to.equal(true)
    end)

    it("update tracks mutation prompt scores", function()
        mock_alc(function() return '{"x": 5}' end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = breed.init(space, nil)
        for _, ind in ipairs(state.population) do
            ind.score = 0.5
        end
        -- Propose to set _last_mutation_idx
        breed.propose(state)
        -- Update with a score
        state = breed.update(state, { x = 5 }, 0.9)

        -- At least one mutation prompt should have uses > 0
        local any_used = false
        for _, m in ipairs(state.mutation_prompts) do
            if m.uses > 0 then any_used = true; break end
        end
        expect(any_used).to.equal(true)
    end)

    it("update keeps population bounded", function()
        mock_alc(function() return '{"x": 5}' end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        local breed = search.resolve("breed")

        local space = { x = { type = "int", min = 1, max = 10 } }
        local state = breed.init(space, nil)
        -- Add many individuals
        for i = 1, 25 do
            state = breed.update(state, { x = i % 10 + 1 }, math.random())
        end
        expect(#state.population <= 20).to.equal(true)
    end)

    it("resolve includes breed in known strategies", function()
        mock_alc(function() return "mock" end)
        package.loaded["optimize.search"] = nil
        local search = require("optimize.search")
        -- Should resolve without error
        for _, name in ipairs({ "ucb", "random", "opro", "ea", "greedy", "breed" }) do
            local s = search.resolve(name)
            expect(type(s.init)).to.equal("function")
        end
    end)
end)
