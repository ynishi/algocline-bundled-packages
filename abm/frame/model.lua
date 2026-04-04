--- abm.frame.model — Simulation model (agent container + stepper)
---
--- Fluent API (DSL Layer 2): new() → add_agents() → run()
--- Model holds agents, global state, scheduler, and RNG.
---
--- Usage:
---   local Model = require("abm.frame.model")
---   local Agent = require("abm.frame.agent")
---   local S     = require("abm.frame.scheduler")
---
---   local m = Model.new({
---       globals = { price = 100 },
---       scheduler = S.shuffle,
---   })
---   Model.add_agents(m, buyers)
---   Model.add_agents(m, sellers)
---   Model.run(m, 24)  -- 24 steps

local M = {}

local MODEL_TAG = "abm.model"

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- Create a new model.
--- @param opts? table
---   globals?: table        — shared mutable state visible to all agents
---   scheduler?: function   — (agents, rng) → ordered_agents
---   seed?: number          — RNG seed (set by MC runner normally)
---   on_step?: function(model, step_num) — hook called after each step
--- @return table Model instance
function M.new(opts)
    opts = opts or {}
    local default_scheduler = require("abm.frame.scheduler").shuffle
    local model = {
        _tag = MODEL_TAG,
        agents = {},
        globals = opts.globals or {},
        scheduler = opts.scheduler or default_scheduler,
        rng = nil,
        seed = opts.seed or 1,
        step_count = 0,
        on_step = opts.on_step,
    }
    return model
end

--- Set seed and initialize RNG. Called by MC runner before each run.
--- @param model table
--- @param seed number
function M.set_seed(model, seed)
    model.seed = seed
    local r = alc.math.rng_create(seed)
    model.rng = function()
        return alc.math.rng_float(r)
    end
end

---------------------------------------------------------------------------
-- Agent management
---------------------------------------------------------------------------

--- Add agents to model (single or array).
--- @param model table
--- @param agents table|table[] Single agent or array of agents
function M.add_agents(model, agents)
    if agents._tag then
        -- Single agent
        model.agents[#model.agents + 1] = agents
    else
        for _, a in ipairs(agents) do
            model.agents[#model.agents + 1] = a
        end
    end
end

--- Get agents matching a predicate.
--- @param model table
--- @param pred function(agent) → boolean
--- @return table[]
function M.get_agents(model, pred)
    local result = {}
    for _, a in ipairs(model.agents) do
        if pred(a) then result[#result + 1] = a end
    end
    return result
end

--- Get agents by state.tag.
--- @param model table
--- @param tag string
--- @return table[]
function M.get_by_tag(model, tag)
    return M.get_agents(model, function(a)
        return a.state and a.state.tag == tag
    end)
end

--- Count agents matching a predicate.
--- @param model table
--- @param pred? function(agent) → boolean (all if nil)
--- @return number
function M.count(model, pred)
    if not pred then return #model.agents end
    local n = 0
    for _, a in ipairs(model.agents) do
        if pred(a) then n = n + 1 end
    end
    return n
end

--- Remove agents matching a predicate.
--- @param model table
--- @param pred function(agent) → boolean
--- @return number removed count
function M.remove_agents(model, pred)
    local kept = {}
    local removed = 0
    for _, a in ipairs(model.agents) do
        if pred(a) then
            removed = removed + 1
        else
            kept[#kept + 1] = a
        end
    end
    model.agents = kept
    return removed
end

---------------------------------------------------------------------------
-- Stepping
---------------------------------------------------------------------------

--- Execute a single step.
--- @param model table
function M.step(model)
    local order = model.scheduler(model.agents, model.rng)
    for _, a in ipairs(order) do
        a.before_step(a, model)
        a.step(a, model)
        a.after_step(a, model)
    end
    model.step_count = model.step_count + 1
    if model.on_step then
        model.on_step(model, model.step_count)
    end
end

--- Run N steps.
--- @param model table
--- @param steps number
--- @return table model (for chaining)
function M.run(model, steps)
    for _ = 1, steps do
        M.step(model)
    end
    return model
end

return M
