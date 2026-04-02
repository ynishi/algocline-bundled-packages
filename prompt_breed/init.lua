--- prompt_breed — Self-Referential Prompt Evolution
---
--- Evolves a population of task prompts (instructions) using genetic operators,
--- with a unique twist: the mutation operators themselves (mutation prompts)
--- also evolve. This double loop — task-prompt evolution + meta-mutation
--- evolution — enables the system to discover increasingly effective ways
--- to explore prompt space.
---
--- Unlike optimize/ea (parameter-level evolution) or optimize/opro (history-
--- based proposal), prompt_breed operates on natural-language instructions
--- with self-referential meta-evolution: the way prompts are mutated improves
--- alongside the prompts themselves.
---
--- Based on:
---   [1] Fernando et al. "PromptBreeder: Self-Referential Self-Improvement
---       via Prompt Evolution" (2023, arXiv:2309.16797)
---       GSM8K zero-shot: 83.9% (vs OPRO 80.2%)
---   [2] Guo et al. "Connecting LLMs with Evolutionary Algorithms Yields
---       Powerful Prompt Optimizers" — EvoPrompt
---       (ICLR 2024, arXiv:2309.08532)
---       BBH: +25% over human-designed prompts
---   [3] Xu et al. "PromptWizard: Task-Aware Agent-driven Prompt Optimization"
---       (ACL Findings 2025)
---
--- Pipeline (population × generations × 2 LLM calls + hyper-mutations):
---   Init       — generate initial task prompts + mutation prompts
---   Loop (per generation):
---     Evaluate   — score each task prompt via evaluator
---     Select     — tournament selection of parents
---     Mutate     — apply mutation prompt to parent → child
---     Replace    — elitist replacement (child beats parent)
---     Hyper-mut  — occasionally evolve the mutation prompts themselves
---   Final: return best prompt
---
--- Usage:
---   local prompt_breed = require("prompt_breed")
---   return prompt_breed.run(ctx)
---
--- ctx.task (required): Task description for prompt evaluation
--- ctx.evaluator (required): Evaluation prompt/criteria for scoring
--- ctx.population_size: Number of task prompts (default: 6)
--- ctx.generations: Evolution generations (default: 8)
--- ctx.mutation_pool: Number of mutation prompts (default: 3)
--- ctx.hyper_mutation_rate: Probability of meta-mutation (default: 0.15)
--- ctx.crossover_rate: Probability of crossover vs mutation (default: 0.3)

local M = {}

---@type AlcMeta
M.meta = {
    name = "prompt_breed",
    version = "0.1.0",
    description = "Self-Referential Prompt Evolution — evolves task prompts "
        .. "via genetic operators with meta-mutation (the mutation operators "
        .. "themselves evolve). Double evolutionary loop.",
    category = "exploration",
}

-- ─── Initialization ───

--- Generate initial task prompts.
local function init_task_prompts(task, count)
    local prompts = {}
    for i = 1, count do
        local existing = ""
        if #prompts > 0 then
            local items = {}
            for j, p in ipairs(prompts) do
                items[#items + 1] = string.format("  %d. %s", j, p:sub(1, 80))
            end
            existing = "\n\nExisting prompts (be DIFFERENT):\n"
                .. table.concat(items, "\n")
        end

        local prompt = alc.llm(
            string.format(
                "Task domain: %s\n%s\n\n"
                    .. "Generate a task INSTRUCTION (prompt) that would help an LLM "
                    .. "solve tasks in this domain effectively. The instruction should:\n"
                    .. "- Be 1-3 sentences\n"
                    .. "- Be specific and actionable\n"
                    .. "- Take a unique angle or approach\n\n"
                    .. "Output ONLY the instruction text, nothing else.",
                task, existing
            ),
            {
                system = "You are a prompt engineer. Generate a clear, effective instruction.",
                max_tokens = 150,
            }
        )
        prompts[#prompts + 1] = prompt
    end
    return prompts
end

--- Generate initial mutation prompts (meta-prompts that guide mutation).
local function init_mutation_prompts(count)
    local defaults = {
        "Rephrase the instruction to be more precise and actionable, "
            .. "while preserving its core intent.",
        "Make the instruction more creative and unconventional. "
            .. "Challenge assumptions in the original.",
        "Simplify the instruction. Remove unnecessary complexity. "
            .. "Focus on what matters most.",
        "Add specific constraints or structure to the instruction "
            .. "that would improve reasoning quality.",
        "Combine the strengths of the instruction with an entirely "
            .. "different problem-solving paradigm.",
    }
    local prompts = {}
    for i = 1, math.min(count, #defaults) do
        prompts[#prompts + 1] = defaults[i]
    end
    -- Generate additional if needed
    for i = #prompts + 1, count do
        local prompt = alc.llm(
            "Generate a meta-instruction that describes HOW to improve a task prompt. "
                .. "The meta-instruction should be a general strategy for mutation "
                .. "(1-2 sentences). Output ONLY the meta-instruction.",
            {
                system = "You are a meta-prompt designer.",
                max_tokens = 100,
            }
        )
        prompts[#prompts + 1] = prompt
    end
    return prompts
end

-- ─── Genetic operators ───

--- Evaluate a task prompt using the provided evaluator.
local function evaluate_prompt(task, prompt, evaluator)
    local score_str = alc.llm(
        string.format(
            "Task domain: %s\n\n"
                .. "Evaluation criteria: %s\n\n"
                .. "Instruction to evaluate:\n\"%s\"\n\n"
                .. "Rate this instruction 1-10 for:\n"
                .. "- Clarity and specificity\n"
                .. "- Likely effectiveness for the task\n"
                .. "- Actionability\n\n"
                .. "Reply with ONLY the number.",
            task, evaluator, prompt
        ),
        {
            system = "You are a prompt quality evaluator. Just the number.",
            max_tokens = 10,
        }
    )
    return alc.parse_score(score_str)
end

--- Apply a mutation prompt to a task prompt.
local function apply_mutation(task, parent_prompt, mutation_prompt)
    return alc.llm(
        string.format(
            "Task domain: %s\n\n"
                .. "Original instruction:\n\"%s\"\n\n"
                .. "Mutation strategy:\n\"%s\"\n\n"
                .. "Apply the mutation strategy to the original instruction. "
                .. "Produce an improved version. Output ONLY the new instruction (1-3 sentences).",
            task, parent_prompt, mutation_prompt
        ),
        {
            system = "You are an instruction mutator. Apply the strategy precisely.",
            max_tokens = 150,
        }
    )
end

--- Crossover: combine two task prompts.
local function crossover(task, parent_a, parent_b)
    return alc.llm(
        string.format(
            "Task domain: %s\n\n"
                .. "Instruction A:\n\"%s\"\n\n"
                .. "Instruction B:\n\"%s\"\n\n"
                .. "Combine the best elements of both instructions into a single, "
                .. "coherent new instruction. Output ONLY the combined instruction (1-3 sentences).",
            task, parent_a, parent_b
        ),
        {
            system = "You are a prompt crossover operator. Merge intelligently.",
            max_tokens = 150,
        }
    )
end

--- Hyper-mutation: evolve a mutation prompt itself.
local function hyper_mutate(mutation_prompt, task)
    return alc.llm(
        string.format(
            "Task domain: %s\n\n"
                .. "Current meta-instruction for mutating prompts:\n\"%s\"\n\n"
                .. "Improve this meta-instruction. Make it a MORE EFFECTIVE strategy "
                .. "for generating better prompt mutations. Output ONLY the improved "
                .. "meta-instruction (1-2 sentences).",
            task, mutation_prompt
        ),
        {
            system = "You are a meta-prompt evolver. Improve the mutation strategy itself.",
            max_tokens = 100,
        }
    )
end

--- Tournament selection: pick a parent from population.
local function tournament_select(population, scores, tournament_size)
    local best_idx = nil
    local best_score = -1
    tournament_size = math.min(tournament_size, #population)

    for _ = 1, tournament_size do
        local idx = math.random(1, #population)
        if scores[idx] > best_score then
            best_score = scores[idx]
            best_idx = idx
        end
    end
    return best_idx
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local evaluator = ctx.evaluator or error("ctx.evaluator is required — evaluation criteria")
    local pop_size = ctx.population_size or 6
    local generations = ctx.generations or 8
    local mut_pool_size = ctx.mutation_pool or 3
    local hyper_rate = ctx.hyper_mutation_rate or 0.15
    local crossover_rate = ctx.crossover_rate or 0.3

    -- Phase 1: Initialize populations
    local population = init_task_prompts(task, pop_size)
    local mutation_prompts = init_mutation_prompts(mut_pool_size)

    -- Track scores
    local scores = {}
    local best_prompt = nil
    local best_score = -1
    local history = {}

    alc.log("info", string.format(
        "prompt_breed: initialized %d prompts, %d mutation operators",
        #population, #mutation_prompts
    ))

    -- Phase 2: Evolution loop
    for gen = 1, generations do
        -- Evaluate all prompts
        for i = 1, #population do
            scores[i] = evaluate_prompt(task, population[i], evaluator)

            if scores[i] > best_score then
                best_score = scores[i]
                best_prompt = population[i]
            end
        end

        -- Record generation stats
        local sum = 0
        for _, s in ipairs(scores) do sum = sum + s end
        local avg = sum / #scores

        history[#history + 1] = {
            generation = gen,
            best_score = best_score,
            avg_score = avg,
        }

        alc.log("info", string.format(
            "prompt_breed: gen %d/%d — best=%.1f, avg=%.1f",
            gen, generations, best_score, avg
        ))

        -- Produce offspring
        local offspring = {}
        local offspring_count = math.max(1, math.floor(pop_size / 2))

        for _ = 1, offspring_count do
            local child

            if math.random() < crossover_rate then
                -- Crossover
                local idx_a = tournament_select(population, scores, 3)
                local idx_b = tournament_select(population, scores, 3)
                -- Ensure different parents
                local attempts = 0
                while idx_b == idx_a and attempts < 5 do
                    idx_b = tournament_select(population, scores, 3)
                    attempts = attempts + 1
                end
                child = crossover(task, population[idx_a], population[idx_b])
            else
                -- Mutation
                local parent_idx = tournament_select(population, scores, 3)
                local mut_idx = math.random(1, #mutation_prompts)
                child = apply_mutation(task, population[parent_idx], mutation_prompts[mut_idx])
            end

            offspring[#offspring + 1] = child
        end

        -- Evaluate offspring and replace worst in population (elitist)
        for _, child in ipairs(offspring) do
            local child_score = evaluate_prompt(task, child, evaluator)

            if child_score > best_score then
                best_score = child_score
                best_prompt = child
            end

            -- Find worst in current population and replace if child is better
            local worst_idx = 1
            local worst_score = scores[1]
            for i = 2, #population do
                if scores[i] < worst_score then
                    worst_score = scores[i]
                    worst_idx = i
                end
            end

            if child_score > worst_score then
                population[worst_idx] = child
                scores[worst_idx] = child_score
            end
        end

        -- Hyper-mutation: evolve mutation prompts themselves
        for i = 1, #mutation_prompts do
            if math.random() < hyper_rate then
                mutation_prompts[i] = hyper_mutate(mutation_prompts[i], task)
                alc.log("info", string.format(
                    "prompt_breed: hyper-mutated mutation operator %d", i
                ))
            end
        end
    end

    -- Phase 3: Final ranking
    local ranked = {}
    for i, p in ipairs(population) do
        ranked[#ranked + 1] = {
            rank = 0,
            prompt = p,
            score = scores[i],
        }
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    for i, r in ipairs(ranked) do r.rank = i end

    ctx.result = {
        best_prompt = best_prompt,
        best_score = best_score,
        population = ranked,
        mutation_prompts = mutation_prompts,
        evolution_history = history,
        stats = {
            generations = generations,
            population_size = pop_size,
            mutation_pool = mut_pool_size,
            hyper_mutation_rate = hyper_rate,
            crossover_rate = crossover_rate,
        },
    }
    return ctx
end

return M
