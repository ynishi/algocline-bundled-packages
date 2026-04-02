--- optimize.search — Search strategies for parameter optimization
---
--- Provides pluggable search strategies with a unified interface:
---   strategy.init(space, history)           → state
---   strategy.propose(state)                 → params
---   strategy.update(state, params, score)   → state
---
--- Each strategy implements the Propose-Evaluate-Update loop from the
--- APO (Automatic Prompt Optimization) taxonomy [6]. The interface
--- separates candidate generation from evaluation, allowing strategies
--- to be composed with any evaluator (see optimize.eval).
---
--- Built-in strategies:
---
---   "ucb" — UCB1 multi-armed bandit
---     Based on: Auer et al. "Finite-time Analysis of the Multiarmed Bandit
---     Problem" (Machine Learning 2002). UCB1 achieves O(√(KT log T)) regret
---     bound, balancing exploration (untried arms) and exploitation (high-
---     scoring arms) via the upper confidence bound: avg + √(2 ln(T) / n_i).
---     Best for: discrete/small parameter spaces where each configuration
---     can be evaluated multiple times.
---
---   "random" — Uniform random sampling
---     Baseline strategy. No learning; each proposal is independently
---     sampled from the parameter space. Useful as a control or when
---     the search space is poorly understood.
---
---   "opro" — OPRO-style meta-prompt accumulation
---     Based on: Yang et al. "Large Language Models as Optimizers"
---     (2023, arXiv:2309.03409). Accumulates top-k scored results into
---     a meta-prompt and asks the LLM to propose the next candidate.
---     The LLM acts as the optimizer, leveraging its understanding of
---     parameter relationships. GSM8K: +8% over human-designed prompts.
---     Best for: when parameter semantics are meaningful to an LLM.
---
---   "ea" — Evolutionary algorithm (GA-style)
---     Inspired by: Guo et al. "EvoPrompt" (ICLR 2024, arXiv:2309.08532).
---     Maintains a population of candidates. New candidates are generated
---     via tournament selection, uniform crossover, and point mutation.
---     Population is bounded and pruned by fitness (elitist selection).
---     BBH: +25% over existing methods. Best for: large parameter spaces
---     where gradient-free global search is needed.
---
---   "greedy" — Epsilon-greedy neighborhood search
---     Classic local search with exploration. With probability (1-ε),
---     perturbs the current best by ±1 step; with probability ε, samples
---     randomly (exploration). Converges fast but may get stuck in local
---     optima. Best for: fine-tuning around a known-good configuration.
---
---   "breed" — PromptBreeder-style self-referential evolution
---     Based on: Fernando et al. "PromptBreeder: Self-Referential
---     Self-Improvement via Prompt Evolution" (2023, arXiv:2309.16797).
---     GSM8K zero-shot: 83.9% (vs OPRO 80.2%). Extends EA with meta-
---     mutation: mutation operators (mutation prompts) themselves evolve
---     alongside the candidate population. Hyper-mutation rate controls
---     how often mutation strategies are improved via LLM self-reflection.
---     Best for: prompt/text parameter spaces where LLM-guided mutation
---     can discover non-obvious improvements.
---
--- Custom strategies:
---   Pass a table with { init, propose, update } functions to M.resolve().

local M = {}

-- ============================================================
-- Parameter space utilities
-- ============================================================

--- Sample a single value from a parameter spec.
local function sample_param(spec)
    if spec.type == "choice" then
        local values = spec.values or error("choice param requires 'values'")
        return values[math.random(#values)]
    end
    local lo = spec.min or 0
    local hi = spec.max or 10
    local step = spec.step
    if spec.type == "int" then
        if step and step > 1 then
            local n = math.floor((hi - lo) / step)
            return lo + math.random(0, n) * step
        end
        return math.random(lo, hi)
    end
    -- float
    if step then
        local n = math.floor((hi - lo) / step + 0.5)
        return lo + math.random(0, n) * step
    end
    return lo + math.random() * (hi - lo)
end

--- Sample a random parameter combination from the full space.
function M.random_params(space)
    local params = {}
    for name, spec in pairs(space) do
        params[name] = sample_param(spec)
    end
    return params
end

--- Enumerate all grid points for a search space (cartesian product).
function M.grid_params(space)
    local dims, dim_names = {}, {}
    for name, spec in pairs(space) do
        dim_names[#dim_names + 1] = name
        local values = {}
        if spec.type == "choice" then
            values = spec.values or {}
        else
            local lo = spec.min or 0
            local hi = spec.max or 10
            local step = spec.step or (spec.type == "int" and 1 or (hi - lo) / 5)
            local v = lo
            while v <= hi + step * 0.01 do
                values[#values + 1] = spec.type == "int" and math.floor(v + 0.5) or v
                v = v + step
            end
        end
        dims[#dims + 1] = values
    end
    local arms = {}
    local function recurse(depth, current)
        if depth > #dims then
            local p = {}
            for i, name in ipairs(dim_names) do p[name] = current[i] end
            arms[#arms + 1] = p
            return
        end
        for _, v in ipairs(dims[depth]) do
            current[depth] = v
            recurse(depth + 1, current)
        end
    end
    recurse(1, {})
    return arms
end

--- Check if two parameter tables are identical.
function M.params_eq(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

--- Perturb params by small delta (neighborhood for greedy).
local function perturb(space, base)
    local p = {}
    for name, spec in pairs(space) do
        local v = base[name]
        if spec.type == "choice" then
            -- 30% chance to switch to random choice
            if math.random() < 0.3 then
                p[name] = sample_param(spec)
            else
                p[name] = v
            end
        elseif spec.type == "int" then
            local step = spec.step or 1
            local delta = step * (math.random(0, 2) - 1) -- -1, 0, +1 step
            local lo = spec.min or 0
            local hi = spec.max or 10
            p[name] = math.max(lo, math.min(hi, v + delta))
        else -- float
            local range = (spec.max or 10) - (spec.min or 0)
            local delta = (math.random() - 0.5) * range * 0.2
            local lo = spec.min or 0
            local hi = spec.max or 10
            p[name] = math.max(lo, math.min(hi, v + delta))
        end
    end
    return p
end

--- Format parameter space for LLM consumption.
local function format_space(space)
    local parts = {}
    for name, spec in pairs(space) do
        if spec.type == "choice" then
            parts[#parts + 1] = string.format(
                "  %s: choice from {%s}", name, table.concat(spec.values, ", "))
        else
            parts[#parts + 1] = string.format(
                "  %s: %s [%s, %s]%s", name, spec.type,
                tostring(spec.min or 0), tostring(spec.max or 10),
                spec.step and (" step=" .. tostring(spec.step)) or "")
        end
    end
    return table.concat(parts, "\n")
end

--- Format top-k results for meta-prompt.
local function format_top_k(results, k)
    -- Sort by score descending
    local sorted = {}
    for _, r in ipairs(results) do sorted[#sorted + 1] = r end
    table.sort(sorted, function(a, b) return a.score > b.score end)
    local lines = {}
    for i = 1, math.min(k, #sorted) do
        local r = sorted[i]
        lines[#lines + 1] = string.format(
            "  %s → score=%.4f", alc.json_encode(r.params), r.score)
    end
    return table.concat(lines, "\n")
end

-- ============================================================
-- UCB1 Strategy
-- Auer et al. 2002: score = avg(reward) + √(2·ln(T) / n_i)
-- Unpulled arms get score=∞, ensuring all arms are tried first.
-- ============================================================

local ucb = {}

function ucb.init(space, history)
    local arms = {}
    -- Rebuild arm stats from history
    if history and #history.results > 0 then
        for _, r in ipairs(history.results) do
            local found = false
            for _, arm in ipairs(arms) do
                if M.params_eq(arm.params, r.params) then
                    arm.total = arm.total + r.score
                    arm.n = arm.n + 1
                    found = true
                    break
                end
            end
            if not found then
                arms[#arms + 1] = { params = r.params, total = r.score, n = 1 }
            end
        end
    end
    -- Seed from grid or random if no arms yet
    if #arms == 0 then
        local grid = M.grid_params(space)
        if #grid <= 100 then
            for _, p in ipairs(grid) do
                arms[#arms + 1] = { params = p, total = 0, n = 0 }
            end
        else
            for _ = 1, 50 do
                arms[#arms + 1] = { params = M.random_params(space), total = 0, n = 0 }
            end
        end
    end
    local total_pulls = 0
    for _, arm in ipairs(arms) do total_pulls = total_pulls + arm.n end
    return { arms = arms, total_pulls = total_pulls, space = space }
end

function ucb.propose(state)
    local best_arm, best_score = state.arms[1], -math.huge
    for _, arm in ipairs(state.arms) do
        local s
        if arm.n == 0 then
            s = math.huge
        else
            s = arm.total / arm.n
                + math.sqrt(2 * math.log(state.total_pulls + 1) / arm.n)
        end
        if s > best_score then
            best_score = s
            best_arm = arm
        end
    end
    return best_arm.params
end

function ucb.update(state, params, score)
    for _, arm in ipairs(state.arms) do
        if M.params_eq(arm.params, params) then
            arm.total = arm.total + score
            arm.n = arm.n + 1
            state.total_pulls = state.total_pulls + 1
            return state
        end
    end
    -- New arm observed
    state.arms[#state.arms + 1] = { params = params, total = score, n = 1 }
    state.total_pulls = state.total_pulls + 1
    return state
end

-- ============================================================
-- Random Strategy
-- ============================================================

local random = {}

function random.init(space, _history)
    return { space = space }
end

function random.propose(state)
    return M.random_params(state.space)
end

function random.update(state, _params, _score)
    return state
end

-- ============================================================
-- OPRO Strategy (meta-prompt accumulation)
-- Yang et al. 2023 (arXiv:2309.03409): In each step, the LLM
-- receives a meta-prompt containing the top-k historical results
-- (params → score pairs) and proposes a new candidate. The LLM
-- implicitly learns parameter-score relationships from the
-- accumulated history. Falls back to random sampling when LLM
-- output fails to parse as valid JSON.
-- ============================================================

local opro = {}

function opro.init(space, history)
    local results = (history and history.results) or {}
    return { space = space, results = results, top_k = 10 }
end

function opro.propose(state)
    if #state.results == 0 then
        return M.random_params(state.space)
    end
    local history_text = format_top_k(state.results, state.top_k)
    local space_text = format_space(state.space)
    local suggestion = alc.llm(
        string.format(
            "You are optimizing parameters to maximize a score.\n\n"
            .. "Parameter space:\n%s\n\n"
            .. "Past results (best first):\n%s\n\n"
            .. "Propose a NEW parameter combination that would score higher than all previous attempts.\n"
            .. "Respond with ONLY a JSON object of parameter values, no explanation.",
            space_text, history_text
        ),
        { system = "You are a hyperparameter optimization expert. Return only valid JSON.",
          max_tokens = 200 }
    )
    local ok, parsed = pcall(alc.json_decode, suggestion)
    if not ok or type(parsed) ~= "table" then
        alc.log("warn", "opro: failed to parse LLM suggestion, falling back to random")
        return M.random_params(state.space)
    end
    -- Clamp parsed values to space bounds
    local params = {}
    for name, spec in pairs(state.space) do
        local v = parsed[name]
        if v == nil then
            params[name] = sample_param(spec)
        elseif spec.type == "choice" then
            -- Validate choice
            local valid = false
            for _, cv in ipairs(spec.values or {}) do
                if cv == v then valid = true; break end
            end
            params[name] = valid and v or sample_param(spec)
        elseif spec.type == "int" then
            v = math.floor(tonumber(v) or 0)
            local lo = spec.min or 0
            local hi = spec.max or 10
            params[name] = math.max(lo, math.min(hi, v))
        else -- float
            v = tonumber(v) or 0
            local lo = spec.min or 0
            local hi = spec.max or 10
            params[name] = math.max(lo, math.min(hi, v))
        end
    end
    return params
end

function opro.update(state, params, score)
    state.results[#state.results + 1] = { params = params, score = score }
    return state
end

-- ============================================================
-- EA Strategy (Evolutionary Algorithm)
-- Guo et al. 2024, EvoPrompt (ICLR 2024, arXiv:2309.08532):
-- GA-style with tournament selection (k=2), uniform crossover
-- (50% per gene), and point mutation (30% per gene).
-- Population bounded to 20 via elitist truncation selection.
-- Unlike EvoPrompt which uses LLM as the evolution operator
-- for discrete text, this implementation operates on numeric/
-- choice parameter spaces with classical GA operators.
-- ============================================================

local ea = {}

function ea.init(space, history)
    local pop = {}
    if history and #history.results > 0 then
        -- Seed population from best historical results
        local sorted = {}
        for _, r in ipairs(history.results) do sorted[#sorted + 1] = r end
        table.sort(sorted, function(a, b) return a.score > b.score end)
        for i = 1, math.min(10, #sorted) do
            pop[#pop + 1] = { params = sorted[i].params, score = sorted[i].score }
        end
    end
    if #pop == 0 then
        for _ = 1, 10 do
            pop[#pop + 1] = { params = M.random_params(space), score = 0 }
        end
    end
    return { space = space, population = pop, generation = 0 }
end

function ea.propose(state)
    local pop = state.population
    if #pop < 2 then return M.random_params(state.space) end
    -- Tournament selection: pick 2 parents
    local function tournament()
        local a = pop[math.random(#pop)]
        local b = pop[math.random(#pop)]
        return a.score >= b.score and a or b
    end
    local p1 = tournament()
    local p2 = tournament()
    -- Crossover: uniform
    local child = {}
    for name, _spec in pairs(state.space) do
        child[name] = math.random() < 0.5 and p1.params[name] or p2.params[name]
    end
    -- Mutation: 30% chance per parameter
    for name, spec in pairs(state.space) do
        if math.random() < 0.3 then
            child[name] = sample_param(spec)
        end
    end
    return child
end

function ea.update(state, params, score)
    local pop = state.population
    pop[#pop + 1] = { params = params, score = score }
    -- Keep population bounded (top 20 by score)
    if #pop > 20 then
        table.sort(pop, function(a, b) return a.score > b.score end)
        while #pop > 20 do pop[#pop] = nil end
    end
    state.generation = state.generation + 1
    return state
end

-- ============================================================
-- Greedy Strategy (epsilon-greedy neighborhood)
-- Classical ε-greedy from reinforcement learning (Sutton & Barto
-- 2018, Ch.2). ε=0.2 balances local refinement (80%) with random
-- exploration (20%). Perturbation is ±1 step for discrete params
-- and ±10% of range for continuous params.
-- ============================================================

local greedy = {}

function greedy.init(space, history)
    local best_params = M.random_params(space)
    local best_score = -math.huge
    if history and #history.results > 0 then
        for _, r in ipairs(history.results) do
            if r.score > best_score then
                best_score = r.score
                best_params = r.params
            end
        end
    end
    return { space = space, best_params = best_params, best_score = best_score, epsilon = 0.2 }
end

function greedy.propose(state)
    if math.random() < state.epsilon then
        return M.random_params(state.space)
    end
    return perturb(state.space, state.best_params)
end

function greedy.update(state, params, score)
    if score > state.best_score then
        state.best_score = score
        state.best_params = params
    end
    return state
end

-- ============================================================
-- Breed Strategy (PromptBreeder-style meta-evolution)
-- Fernando et al. 2023 (arXiv:2309.16797): Evolves both the
-- candidate population AND the mutation operators (mutation
-- prompts) that generate new candidates. Hyper-mutation allows
-- the mutation strategy itself to improve over time.
-- ============================================================

local breed = {}

local BREED_DEFAULT_MUTATIONS = {
    "Rephrase the parameters to be more precise, keeping the core approach.",
    "Try a radically different parameter combination. Challenge assumptions.",
    "Simplify: reduce to the minimal effective configuration.",
}

function breed.init(space, history)
    local pop = {}
    if history and #history.results > 0 then
        local sorted = {}
        for _, r in ipairs(history.results) do sorted[#sorted + 1] = r end
        table.sort(sorted, function(a, b) return a.score > b.score end)
        for i = 1, math.min(10, #sorted) do
            pop[#pop + 1] = { params = sorted[i].params, score = sorted[i].score }
        end
    end
    if #pop == 0 then
        for _ = 1, 10 do
            pop[#pop + 1] = { params = M.random_params(space), score = 0 }
        end
    end

    -- Initialize mutation prompts with scores
    local mut_prompts = {}
    for _, m in ipairs(BREED_DEFAULT_MUTATIONS) do
        mut_prompts[#mut_prompts + 1] = { text = m, total_score = 0, uses = 0 }
    end

    return {
        space = space,
        population = pop,
        mutation_prompts = mut_prompts,
        generation = 0,
        hyper_mutation_rate = 0.15,
    }
end

function breed.propose(state)
    local pop = state.population
    if #pop < 2 then return M.random_params(state.space) end

    -- Tournament selection for parent
    local function tournament()
        local a = pop[math.random(#pop)]
        local b = pop[math.random(#pop)]
        return a.score >= b.score and a or b
    end
    local parent = tournament()

    -- Select mutation prompt (UCB1-like over mutation prompts)
    local muts = state.mutation_prompts
    local best_mut = muts[1]
    local best_mut_score = -math.huge
    local total_uses = 0
    for _, m in ipairs(muts) do total_uses = total_uses + m.uses end

    for _, m in ipairs(muts) do
        local s
        if m.uses == 0 then
            s = math.huge
        else
            s = m.total_score / m.uses
                + math.sqrt(2 * math.log(total_uses + 1) / m.uses)
        end
        if s > best_mut_score then
            best_mut_score = s
            best_mut = m
        end
    end

    -- Use LLM to apply mutation prompt to parent's params
    local space_text = format_space(state.space)
    local parent_text = alc.json_encode(parent.params)

    local suggestion = alc.llm(
        string.format(
            "You are optimizing parameters to maximize a score.\n\n"
                .. "Parameter space:\n%s\n\n"
                .. "Parent parameters (score=%.4f):\n%s\n\n"
                .. "Mutation strategy: %s\n\n"
                .. "Apply the mutation strategy to the parent parameters and "
                .. "propose improved values. Respond with ONLY a JSON object.",
            space_text, parent.score, parent_text, best_mut.text
        ),
        {
            system = "You are a parameter mutation operator. Return only valid JSON.",
            max_tokens = 200,
        }
    )

    -- Track which mutation was used (for update)
    state._last_mutation_idx = nil
    for i, m in ipairs(muts) do
        if m == best_mut then state._last_mutation_idx = i; break end
    end

    local ok, parsed = pcall(alc.json_decode, suggestion)
    if not ok or type(parsed) ~= "table" then
        alc.log("warn", "breed: failed to parse LLM suggestion, falling back to EA-style")
        -- Fallback: EA-style mutation
        local child = {}
        for name, spec in pairs(state.space) do
            if math.random() < 0.3 then
                child[name] = sample_param(spec)
            else
                child[name] = parent.params[name]
            end
        end
        return child
    end

    -- Clamp to space bounds
    local params = {}
    for name, spec in pairs(state.space) do
        local v = parsed[name]
        if v == nil then
            params[name] = parent.params[name] or sample_param(spec)
        elseif spec.type == "choice" then
            local valid = false
            for _, cv in ipairs(spec.values or {}) do
                if cv == v then valid = true; break end
            end
            params[name] = valid and v or sample_param(spec)
        elseif spec.type == "int" then
            v = math.floor(tonumber(v) or 0)
            params[name] = math.max(spec.min or 0, math.min(spec.max or 10, v))
        else
            v = tonumber(v) or 0
            params[name] = math.max(spec.min or 0, math.min(spec.max or 10, v))
        end
    end
    return params
end

function breed.update(state, params, score)
    local pop = state.population
    pop[#pop + 1] = { params = params, score = score }

    -- Update mutation prompt score
    if state._last_mutation_idx then
        local m = state.mutation_prompts[state._last_mutation_idx]
        m.total_score = m.total_score + score
        m.uses = m.uses + 1
    end
    state._last_mutation_idx = nil

    -- Elitist truncation (keep top 20)
    if #pop > 20 then
        table.sort(pop, function(a, b) return a.score > b.score end)
        while #pop > 20 do pop[#pop] = nil end
    end

    -- Hyper-mutation: evolve mutation prompts themselves
    if math.random() < state.hyper_mutation_rate then
        local muts = state.mutation_prompts
        -- Pick the worst-performing mutation prompt
        local worst_idx = 1
        local worst_avg = math.huge
        for i, m in ipairs(muts) do
            local avg = m.uses > 0 and (m.total_score / m.uses) or math.huge
            if m.uses > 0 and avg < worst_avg then
                worst_avg = avg
                worst_idx = i
            end
        end

        if muts[worst_idx].uses > 0 then
            local new_text = alc.llm(
                string.format(
                    "Current mutation strategy (avg score=%.2f):\n\"%s\"\n\n"
                        .. "This strategy has been underperforming. Improve it to be "
                        .. "a more effective way to mutate parameter combinations. "
                        .. "Output ONLY the improved mutation strategy (1-2 sentences).",
                    worst_avg, muts[worst_idx].text
                ),
                {
                    system = "You are a meta-optimizer. Improve the mutation strategy itself.",
                    max_tokens = 100,
                }
            )
            muts[worst_idx] = { text = new_text, total_score = 0, uses = 0 }
            alc.log("info", "optimize.breed: hyper-mutated mutation prompt #" .. worst_idx)
        end
    end

    state.generation = state.generation + 1
    return state
end

-- ============================================================
-- Registry
-- ============================================================

M.strategies = {
    ucb     = ucb,
    random  = random,
    opro    = opro,
    ea      = ea,
    greedy  = greedy,
    breed   = breed,
}

--- Resolve a strategy by name or table.
--- Returns { init, propose, update }.
function M.resolve(spec)
    if type(spec) == "string" then
        local s = M.strategies[spec]
        if not s then error("optimize.search: unknown strategy '" .. spec .. "'") end
        return s
    elseif type(spec) == "table" then
        if not spec.init then error("optimize.search: custom strategy requires init()") end
        if not spec.propose then error("optimize.search: custom strategy requires propose()") end
        if not spec.update then error("optimize.search: custom strategy requires update()") end
        return spec
    end
    error("optimize.search: spec must be a string name or strategy table")
end

return M
