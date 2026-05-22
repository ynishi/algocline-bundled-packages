--- Tests extracted from tests/test_exploration.lua (Phase C decomposition).

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

local function reset()
    _G.alc = nil
    for _, name in ipairs({ "prompt_breed" }) do
        package.loaded[name] = nil
    end
end

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
