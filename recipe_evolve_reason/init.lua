--- recipe_evolve_reason — multi-generation evolutionary LLM reasoning
---
--- Maintains a population of N reasoning slots across G generations.
--- Each generation: LLM generates reasoning, peer-evaluation scores
--- fitness, transition rules select elites, lineage begets children
--- via LLM-driven mutation, and knowledge channel inherits insights.
--- Converges to a high-fitness answer through evolutionary pressure.
---
--- ## Usage
---
--- ```lua
--- local recipe = require("recipe_evolve_reason")
--- return recipe.run({
---     task = "Prove that sqrt(2) is irrational.",
---     pop_size = 6,
---     max_gen = 3,
---     elite_ratio = 0.5,
---     gen_tokens = 600,
--- })
--- ```
---
--- ## Algorithm
---
--- 1. Gen 0: LLM generates N independent reasoning paths (1 call each).
--- 2. Peer evaluation: each pair (i, j) where i < j, LLM scores both
---    on a 1-10 scale (1 call per pair). Scores accumulate in
---    civic.scalar_pool with source="peer".
--- 3. Transition: top `elite_ratio` fraction → "elite", rest →
---    "eliminated" via civic.transition_rules.
--- 4. Reproduction: each eliminated slot is replaced by a child of a
---    random elite parent. civic.lineage.beget with mutation_op that
---    calls LLM to improve the parent reasoning (1 call per child).
---    civic.knowledge_channel transfers the parent's key insight to
---    the child (1 call per child).
--- 5. Repeat 2-4 for max_gen generations.
--- 6. Return the highest-scoring reasoning from the final generation.
---
--- ## Caveats
---
--- Peer evaluation cost is O(N^2) per generation. Keep pop_size <= 8
--- for practical LLM budgets. For N=6, max_gen=3: worst case ~69 LLM
--- calls (6 init + 15 eval × 3 gen + 3 mutate × 2 gen + 3 inherit
--- × 2 gen).
---
--- No canonical paper for evolutionary LLM reasoning as a recipe
--- pattern. Design draws on tournament selection (Goldberg 1991 §4),
--- self-play evaluation (Silver et al. 2017 Nature), and LLM-as-judge
--- (Zheng et al. 2023 arXiv:2306.05685). Implementation choice: civic
--- primitives provide the population / scoring / selection / lineage
--- infrastructure, LLM provides reasoning + evaluation + mutation.

local M = {}

---@type AlcMeta
M.meta = {
    name        = "recipe_evolve_reason",
    version     = "0.1.0",
    description = "Multi-generation evolutionary LLM reasoning. "
        .. "Maintains a population of reasoning paths that compete, "
        .. "mutate, and evolve across generations via civic primitives. "
        .. "Targets hard problems where single-generation voting "
        .. "(recipe_quick_vote / recipe_safe_panel) cannot converge.",
    category    = "recipe",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            result = "evolved_reason",
        },
    },
}

M.ingredients = {
    "civic",
}

M.caveats = {
    "Peer evaluation cost is O(N choose 2) per generation. For pop_size=6 "
        .. "that is 15 LLM calls per generation just for scoring. Keep "
        .. "pop_size <= 8 for practical budgets.",
    "Mutation op asks LLM to 'improve' the parent reasoning. This is a "
        .. "single-prompt mutation — no crossover between two parents. "
        .. "Crossover (merging insights from two elites) is v0.2+.",
    "Knowledge channel transform extracts key insight via LLM. This adds "
        .. "1 call per child per generation. Set inherit=false in ctx to "
        .. "skip and reduce cost.",
    "Elite selection is deterministic: top-K by total fitness. Stochastic "
        .. "tournament selection (fitness-proportional) is v0.2+.",
    "No early stopping. Runs all max_gen generations even if the "
        .. "population converges early. Convergence detection is v0.2+.",
}

-- ─── Internal helpers ───

local function make_gen_prompt(task, hint)
    return string.format(
        "Question: %s\n\n%s\n\nThink carefully and show your full "
        .. "reasoning step by step. Then state your final answer clearly.",
        task, hint or "Think step by step."
    )
end

local function make_eval_prompt(task, reasoning_a, reasoning_b)
    return string.format(
        "Question: %s\n\n"
        .. "=== Reasoning A ===\n%s\n\n"
        .. "=== Reasoning B ===\n%s\n\n"
        .. "Score each reasoning on correctness and thoroughness (1-10). "
        .. "Reply EXACTLY in this format:\n"
        .. "Score_A: <number>\nScore_B: <number>",
        task, reasoning_a, reasoning_b
    )
end

local function make_mutate_prompt(task, parent_reasoning)
    return string.format(
        "Question: %s\n\n"
        .. "A previous attempt at reasoning:\n%s\n\n"
        .. "Improve this reasoning. Fix any errors, strengthen weak "
        .. "arguments, and add missing steps. Show your improved full "
        .. "reasoning step by step, then state your final answer.",
        task, parent_reasoning
    )
end

local function make_inherit_prompt(parent_reasoning)
    return string.format(
        "Extract the single most important insight or key step from "
        .. "this reasoning. Reply in 1-2 sentences only.\n\n%s",
        parent_reasoning
    )
end

local function parse_scores(response)
    local sa = response:match("Score_A:%s*(%d+)")
    local sb = response:match("Score_B:%s*(%d+)")
    local a = tonumber(sa) or 5
    local b = tonumber(sb) or 5
    a = math.max(1, math.min(10, a))
    b = math.max(1, math.min(10, b))
    return a, b
end

local DIVERSITY_HINTS = {
    "Think step by step carefully.",
    "Approach this from first principles.",
    "Consider an alternative perspective.",
    "Work backwards from the expected outcome.",
    "Break this into smaller sub-problems.",
    "Try a proof by contradiction.",
    "Consider edge cases first.",
    "Use a concrete example to build intuition.",
}

-- ─── Main entry ───

function M.run(ctx)
    local task = ctx.task
        or error("recipe_evolve_reason: ctx.task is required", 2)

    local pop_size    = ctx.pop_size    or 6
    local max_gen     = ctx.max_gen     or 3
    local elite_ratio = ctx.elite_ratio or 0.5
    local gen_tokens  = ctx.gen_tokens  or 600
    local inherit     = ctx.inherit ~= false

    if pop_size < 2 then
        error("recipe_evolve_reason: pop_size must be >= 2", 2)
    end
    if max_gen < 1 then
        error("recipe_evolve_reason: max_gen must be >= 1", 2)
    end
    if elite_ratio <= 0 or elite_ratio >= 1 then
        error("recipe_evolve_reason: elite_ratio must be in (0, 1)", 2)
    end

    local civic = require("civic")
    local total_llm_calls = 0

    local n_elite = math.max(1, math.floor(pop_size * elite_ratio))

    -- civic infrastructure
    local slots = civic.slot_table.new(pop_size, function(idx)
        return { state = "active", reasoning = "", answer = "", insight = "" }
    end)
    local pool = civic.scalar_pool.new()
    local lin  = civic.lineage.new()
    local kchan = civic.knowledge_channel.new()

    local rules = civic.transition_rules.new()
    -- rules are re-applied each gen with fresh threshold

    -- Gen 0: generate initial reasoning
    for idx = 1, pop_size do
        local hint = DIVERSITY_HINTS[((idx - 1) % #DIVERSITY_HINTS) + 1]
        local reasoning = alc.llm(make_gen_prompt(task, hint), {
            system = "You are a careful, thorough reasoner.",
            max_tokens = gen_tokens,
        })
        total_llm_calls = total_llm_calls + 1
        local payload = slots:get(idx)
        payload.reasoning = reasoning
        payload.answer = reasoning
    end

    local gen_history = {}

    for gen = 1, max_gen do
        -- Peer evaluation: all pairs
        for i = 1, pop_size do
            for j = i + 1, pop_size do
                local pi = slots:get(i)
                local pj = slots:get(j)
                if pi.state == "active" and pj.state == "active" then
                    local resp = alc.llm(
                        make_eval_prompt(task, pi.reasoning, pj.reasoning),
                        {
                            system = "You are a fair, precise evaluator. "
                                .. "Score each reasoning independently.",
                            max_tokens = 100,
                        }
                    )
                    total_llm_calls = total_llm_calls + 1
                    local sa, sb = parse_scores(resp)
                    pool:credit(i, "peer_gen" .. gen, sa)
                    pool:credit(j, "peer_gen" .. gen, sb)
                end
            end
        end

        -- Rank by total fitness, determine elite threshold
        local ranked = {}
        for idx = 1, pop_size do
            ranked[idx] = { idx = idx, score = pool:total(idx) }
        end
        table.sort(ranked, function(a, b) return a.score > b.score end)

        local threshold = ranked[n_elite].score

        -- Build transition rules for this generation
        local gen_rules = civic.transition_rules.new()
        gen_rules:add("active", "elite", function(payload, gctx)
            return pool:total(gctx.idx) >= threshold
        end)
        gen_rules:add("active", "eliminated", function(payload, gctx)
            return pool:total(gctx.idx) < threshold
        end)

        -- Apply transitions
        local elites = {}
        local eliminated = {}
        for idx = 1, pop_size do
            local payload = slots:get(idx)
            local new_payload = gen_rules:apply(payload, { idx = idx })
            slots:set(idx, new_payload)
            if new_payload.state == "elite" then
                elites[#elites + 1] = idx
            else
                eliminated[#eliminated + 1] = idx
            end
        end

        gen_history[gen] = {
            ranked = ranked,
            elites = elites,
            eliminated = eliminated,
            threshold = threshold,
        }

        -- Last generation: no reproduction needed
        if gen == max_gen then break end

        -- Reproduction: mutate elites to fill eliminated slots
        lin:set_mutation_op(function(parent_payload)
            local improved = alc.llm(
                make_mutate_prompt(task, parent_payload.reasoning),
                {
                    system = "You are improving a previous reasoning attempt. "
                        .. "Fix errors and strengthen the argument.",
                    max_tokens = gen_tokens,
                }
            )
            total_llm_calls = total_llm_calls + 1
            return {
                state = "active",
                reasoning = improved,
                answer = improved,
                insight = parent_payload.insight or "",
            }
        end)

        if inherit then
            kchan:set_transform(function(payload, tctx)
                local insight_text = alc.llm(
                    make_inherit_prompt(payload.reasoning),
                    {
                        system = "Extract the key insight concisely.",
                        max_tokens = 150,
                    }
                )
                total_llm_calls = total_llm_calls + 1
                return {
                    reasoning = payload.reasoning,
                    insight = insight_text,
                }
            end)
        end

        for _, elim_idx in ipairs(eliminated) do
            local parent_idx = elites[((elim_idx - 1) % #elites) + 1]
            local parent_payload = slots:get(parent_idx)

            local child_payload = lin:beget(
                parent_idx, elim_idx, gen, parent_payload
            )

            if inherit then
                local inherited = kchan:transfer(
                    parent_idx, elim_idx, parent_payload
                )
                child_payload.insight = inherited.insight or ""
            end

            slots:set(elim_idx, child_payload)
        end

        -- Reset states for next generation
        for idx = 1, pop_size do
            local payload = slots:get(idx)
            payload.state = "active"
        end
    end

    -- Find best reasoning from final population
    local best_idx = 1
    local best_score = pool:total(1)
    for idx = 2, pop_size do
        local s = pool:total(idx)
        if s > best_score then
            best_score = s
            best_idx = idx
        end
    end

    local best = slots:get(best_idx)

    ctx.result = {
        answer          = best.reasoning,
        best_idx        = best_idx,
        best_score      = best_score,
        insight         = best.insight,
        pop_size        = pop_size,
        generations     = max_gen,
        total_llm_calls = total_llm_calls,
        gen_history     = gen_history,
        lineage_edges   = lin:edges(),
    }

    return ctx
end

return M
