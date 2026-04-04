--- epidemic_abm — SIR Agent-Based Epidemic Model
---
--- N agents transition between Susceptible → Infected → Recovered states.
--- Each step, infected agents probabilistically transmit to susceptible
--- contacts, and recover with probability γ.
---
--- Emergent phenomena: epidemic threshold (R0 = β/γ > 1),
--- herd immunity, wave dynamics, stochastic extinction.
---
--- Based on:
---   Kermack & McKendrick, "A Contribution to the Mathematical Theory
---   of Epidemics", Proc. Royal Society A, 1927 (SIR ODE)
---
---   Epstein, "Generative Social Science: Studies in Agent-Based
---   Computational Modeling", Princeton, 2006 (ABM formulation)
---
--- Usage:
---   local epidemic = require("epidemic_abm")
---   return epidemic.run(ctx)
---
--- ctx.task (required): Description
--- ctx.n_agents?: number (default 200)
--- ctx.initial_infected?: number (default 5)
--- ctx.beta?: number Transmission probability per contact (default 0.3)
--- ctx.gamma?: number Recovery probability per step (default 0.1)
--- ctx.contacts_per_step?: number Mean contacts per agent (default 5)
--- ctx.steps?: number (default 100)
--- ctx.runs?: number MC runs (default 100)

local abm = require("abm")

local M = {}

---@type AlcMeta
M.meta = {
    name = "epidemic_abm",
    version = "0.1.0",
    description = "SIR Agent-Based epidemic model — stochastic individual-level "
        .. "disease transmission with tunable R0. Emergent epidemic curves, "
        .. "herd immunity thresholds, and stochastic extinction.",
    category = "simulation",
}

---------------------------------------------------------------------------
-- SIR states
---------------------------------------------------------------------------

local S, I, R = 1, 2, 3

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

--- Run a single SIR simulation.
local function run_single(params, seed)
    local rng_state = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(rng_state) end

    local n = params.n_agents or 200
    local initial_infected = params.initial_infected or 5
    local beta = params.beta or 0.3
    local gamma = params.gamma or 0.1
    local contacts = params.contacts_per_step or 5
    local steps = params.steps or 100

    -- Initialize population
    local state = {}
    for i = 1, n do state[i] = S end
    -- Infect initial agents
    for i = 1, math.min(initial_infected, n) do
        state[i] = I
    end

    -- Tracking
    local peak_infected = initial_infected
    local total_ever_infected = initial_infected
    local epidemic_duration = 0
    local snapshots = {}

    for step = 1, steps do
        local new_state = {}
        for i = 1, n do new_state[i] = state[i] end

        -- Count current infected
        local current_infected = 0
        for i = 1, n do
            if state[i] == I then current_infected = current_infected + 1 end
        end

        if current_infected == 0 then
            -- Epidemic over
            snapshots[#snapshots + 1] = {
                step = step, s = n - total_ever_infected,
                i = 0, r = total_ever_infected,
            }
            epidemic_duration = step
            break
        end

        -- Transmission: each infected agent contacts `contacts` random agents
        for i = 1, n do
            if state[i] == I then
                for _ = 1, contacts do
                    local j = math.floor(rng() * n) + 1
                    -- Check both old and new state to avoid double-counting
                    if state[j] == S and new_state[j] == S and rng() < beta then
                        new_state[j] = I
                        total_ever_infected = total_ever_infected + 1
                    end
                end
            end
        end

        -- Recovery
        for i = 1, n do
            if state[i] == I and rng() < gamma then
                new_state[i] = R
            end
        end

        state = new_state

        -- Count states
        local s_count, i_count, r_count = 0, 0, 0
        for i = 1, n do
            if state[i] == S then s_count = s_count + 1
            elseif state[i] == I then i_count = i_count + 1
            else r_count = r_count + 1
            end
        end

        if i_count > peak_infected then peak_infected = i_count end
        epidemic_duration = step

        snapshots[#snapshots + 1] = {
            step = step, s = s_count, i = i_count, r = r_count,
        }
    end

    local attack_rate = total_ever_infected / n
    local r0_empirical = (beta * contacts) / gamma

    return {
        attack_rate = attack_rate,
        peak_infected = peak_infected,
        peak_fraction = peak_infected / n,
        epidemic_duration = epidemic_duration,
        r0_empirical = r0_empirical,
        herd_immunity_reached = attack_rate > (1 - 1 / math.max(r0_empirical, 1.001)),
        epidemic_occurred = total_ever_infected > initial_infected * 2,
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
        n_agents = ctx.n_agents or 200,
        initial_infected = ctx.initial_infected or 5,
        beta = ctx.beta or 0.3,
        gamma = ctx.gamma or 0.1,
        contacts_per_step = ctx.contacts_per_step or 5,
        steps = ctx.steps or 100,
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = {
            "attack_rate", "peak_fraction", "epidemic_duration",
            "epidemic_occurred", "herd_immunity_reached",
        },
    })

    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = { "beta", "gamma", "contacts_per_step" },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "attack_rate" },
            })
            return quick.attack_rate_median or 0
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

return M
