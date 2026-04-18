--- evogame_abm — Evolutionary Game Theory ABM
---
--- N agents with strategies play iterated games (Prisoner's Dilemma by default).
--- Each generation: random pairing → payoff calculation → selection → mutation.
--- Emergent phenomena: cooperation/defection equilibria, cyclic dominance,
--- strategy invasion dynamics.
---
--- Based on:
---   Axelrod, "The Evolution of Cooperation", Basic Books, 1984
---   Nowak & May, "Evolutionary Games and Spatial Chaos", Nature 359, 1992
---   Mao et al., "ALYMPICS: LLM Agents Meet Game Theory", COLING 2025
---
--- Usage:
---   local evogame = require("evogame_abm")
---   return evogame.run(ctx)
---
--- ctx.task (required): Description
--- ctx.n_agents?: number (default 50)
--- ctx.generations?: number (default 30)
--- ctx.rounds_per_gen?: number Games per generation (default 10)
--- ctx.mutation_rate?: number (default 0.05)
--- ctx.payoff_matrix?: table Custom payoff { CC, CD, DC, DD }
--- ctx.strategies?: string[] Initial strategy distribution
--- ctx.runs?: number MC runs (default 100)

local abm = require("abm")
local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "evogame_abm",
    version = "0.1.0",
    description = "Evolutionary Game Theory ABM — iterated games with "
        .. "selection and mutation. Prisoner's Dilemma, Hawk-Dove, "
        .. "or custom payoff matrices. Based on Axelrod (1984).",
    category = "simulation",
}

---@type AlcSpec
-- Phase 6-a: ABM MC-sweep pattern. payoff_matrix and strategies are
-- accepted as opaque tables; result sub-tables stay opaque.
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:is_optional(),
                n_agents       = T.number:is_optional(),
                generations    = T.number:is_optional(),
                rounds_per_gen = T.number:is_optional(),
                mutation_rate  = T.number:is_optional(),
                payoff_matrix  = T.table:is_optional(),
                strategies     = T.array_of(T.string):is_optional(),
                runs           = T.number:is_optional(),
            }),
            result = T.shape({
                params      = T.table,
                simulation  = T.table,
                sensitivity = T.table,
            }),
        },
    },
}

---------------------------------------------------------------------------
-- Payoff matrices
---------------------------------------------------------------------------

-- Prisoner's Dilemma: T > R > P > S, 2R > T + S
local PD_PAYOFF = {
    CC = { 3, 3 },  -- mutual cooperation (Reward)
    CD = { 0, 5 },  -- sucker / temptation
    DC = { 5, 0 },  -- temptation / sucker
    DD = { 1, 1 },  -- mutual defection (Punishment)
}

-- Hawk-Dove (Chicken): T > R > S > P (reversed P and S from PD)
local HD_PAYOFF = {
    CC = { 3, 3 },  -- Dove-Dove: share
    CD = { 1, 5 },  -- Dove-Hawk: yield
    DC = { 5, 1 },  -- Hawk-Dove: take
    DD = { 0, 0 },  -- Hawk-Hawk: fight (both lose)
}

---------------------------------------------------------------------------
-- Strategies (deterministic, stateless)
---------------------------------------------------------------------------

-- Always cooperate
local function always_cooperate(_history, _opp_history) return "C" end

-- Always defect
local function always_defect(_history, _opp_history) return "D" end

-- Tit-for-Tat: cooperate first, then copy opponent's last move
local function tit_for_tat(_history, opp_history)
    if #opp_history == 0 then return "C" end
    return opp_history[#opp_history]
end

-- Pavlov (Win-Stay Lose-Shift): repeat if won, switch if lost
local function pavlov(history, opp_history)
    if #history == 0 then return "C" end
    local my_last = history[#history]
    local opp_last = opp_history[#opp_history]
    if (my_last == "C" and opp_last == "C") or (my_last == "D" and opp_last == "D") then
        return my_last
    end
    return my_last == "C" and "D" or "C"
end

-- Random: 50/50
local function random_strategy(_history, _opp_history, rng)
    return rng() < 0.5 and "C" or "D"
end

-- Grudger: cooperate until opponent defects, then always defect
local function grudger(_history, opp_history)
    for _, m in ipairs(opp_history) do
        if m == "D" then return "D" end
    end
    return "C"
end

local STRATEGY_MAP = {
    always_cooperate = always_cooperate,
    always_defect = always_defect,
    tit_for_tat = tit_for_tat,
    pavlov = pavlov,
    random = random_strategy,
    grudger = grudger,
}

local STRATEGY_NAMES = {
    "always_cooperate", "always_defect", "tit_for_tat",
    "pavlov", "random", "grudger",
}

---------------------------------------------------------------------------
-- Game mechanics
---------------------------------------------------------------------------

--- Play a series of rounds between two agents.
--- @return number, number Scores for agent a and b
local function play_match(strat_a, strat_b, rounds, payoff, rng)
    local hist_a, hist_b = {}, {}
    local score_a, score_b = 0, 0

    for _ = 1, rounds do
        local move_a = strat_a(hist_a, hist_b, rng)
        local move_b = strat_b(hist_b, hist_a, rng)

        local key = move_a .. move_b
        local p = payoff[key]
        score_a = score_a + p[1]
        score_b = score_b + p[2]

        hist_a[#hist_a + 1] = move_a
        hist_b[#hist_b + 1] = move_b
    end

    return score_a, score_b
end

--- Tournament: all-vs-all or random pairing.
--- Returns total scores per agent index.
local function round_robin(agents, rounds, payoff, rng)
    local n = #agents
    local scores = {}
    for i = 1, n do scores[i] = 0 end

    for i = 1, n do
        for j = i + 1, n do
            local sa, sb = play_match(
                STRATEGY_MAP[agents[i]], STRATEGY_MAP[agents[j]],
                rounds, payoff, rng
            )
            scores[i] = scores[i] + sa
            scores[j] = scores[j] + sb
        end
    end

    return scores
end

--- Selection: fitness-proportionate (roulette wheel).
--- @return string[] New generation of strategy names
local function select_generation(agents, scores, n, rng)
    local total = 0
    for _, s in ipairs(scores) do
        total = total + math.max(s, 0.001)  -- avoid zero
    end

    local new_gen = {}
    for _ = 1, n do
        local pick = rng() * total
        local acc = 0
        for i, s in ipairs(scores) do
            acc = acc + math.max(s, 0.001)
            if acc >= pick then
                new_gen[#new_gen + 1] = agents[i]
                break
            end
        end
        if #new_gen < _ then
            new_gen[#new_gen + 1] = agents[1]  -- fallback
        end
    end
    return new_gen
end

--- Mutation: with probability p, replace strategy with random one.
local function mutate(agents, rate, rng)
    for i = 1, #agents do
        if rng() < rate then
            agents[i] = STRATEGY_NAMES[math.floor(rng() * #STRATEGY_NAMES) + 1]
        end
    end
    return agents
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

--- Run a single evolutionary simulation.
local function run_single(params, seed)
    local r = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(r) end

    local n = params.n_agents or 50
    local generations = params.generations or 30
    local rounds = params.rounds_per_gen or 10
    local mutation_rate = params.mutation_rate or 0.05
    local payoff = params.payoff_matrix or PD_PAYOFF

    -- Initialize agents with strategies
    local agents
    if params.strategies then
        agents = {}
        for i = 1, n do
            agents[i] = params.strategies[((i - 1) % #params.strategies) + 1]
        end
    else
        agents = {}
        for i = 1, n do
            agents[i] = STRATEGY_NAMES[((i - 1) % #STRATEGY_NAMES) + 1]
        end
    end

    -- Run generations
    local history = {}
    for gen = 1, generations do
        local scores = round_robin(agents, rounds, payoff, rng)
        agents = select_generation(agents, scores, n, rng)
        agents = mutate(agents, mutation_rate, rng)

        -- Record strategy distribution
        local dist = {}
        for _, s in ipairs(agents) do
            dist[s] = (dist[s] or 0) + 1
        end
        history[gen] = dist
    end

    -- Final analysis
    local final_dist = history[#history] or {}
    local dominant = nil
    local dominant_count = 0
    for s, c in pairs(final_dist) do
        if c > dominant_count then
            dominant = s
            dominant_count = c
        end
    end

    local cooperation_count = 0
    for _, s in ipairs(agents) do
        if s == "always_cooperate" or s == "tit_for_tat"
            or s == "pavlov" or s == "grudger" then
            cooperation_count = cooperation_count + 1
        end
    end

    local n_surviving = 0
    for _ in pairs(final_dist) do n_surviving = n_surviving + 1 end

    return {
        dominant_strategy = dominant,
        dominant_fraction = dominant_count / n,
        cooperation_rate = cooperation_count / n,
        n_strategies_surviving = n_surviving,
        tft_survived = (final_dist["tit_for_tat"] or 0) > 0,
    }
end

---------------------------------------------------------------------------
-- M.run(ctx)
---------------------------------------------------------------------------

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    -- ctx.task is available for LLM prompt integration (e.g. via hybrid_abm)

    local params = {
        n_agents = ctx.n_agents or 50,
        generations = ctx.generations or 30,
        rounds_per_gen = ctx.rounds_per_gen or 10,
        mutation_rate = ctx.mutation_rate or 0.05,
        payoff_matrix = ctx.payoff_matrix or PD_PAYOFF,
        strategies = ctx.strategies,
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = {
            "cooperation_rate", "dominant_fraction",
            "n_strategies_surviving", "tft_survived",
        },
    })

    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = { "mutation_rate", "rounds_per_gen" },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "cooperation_rate" },
            })
            return quick.cooperation_rate_median or 0
        end,
    })

    ctx.result = {
        params = params,
        simulation = mc_result,
        sensitivity = sensitivity,
    }
    return ctx
end

M.run_single = run_single
M.PD_PAYOFF = PD_PAYOFF
M.HD_PAYOFF = HD_PAYOFF
M.STRATEGY_NAMES = STRATEGY_NAMES

-- Malli-style self-decoration. run_single stays uninstrumented.
M.run = S.instrument(M, "run")

return M
