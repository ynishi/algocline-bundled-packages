--- abm.frame.scheduler — Agent activation order control
---
--- Combinator pattern (DSL Layer 3): all schedulers share the unified
--- signature (agents, rng) → ordered_agents, composable via concat/filter.
---
--- Usage:
---   local S = require("abm.frame.scheduler")
---   -- Basic
---   local sched = S.shuffle
---   -- Composed: sellers first (shuffled), then buyers (shuffled)
---   local sched = S.concat(
---       S.filter_tag("seller", S.shuffle),
---       S.filter_tag("buyer", S.shuffle)
---   )

local M = {}

---------------------------------------------------------------------------
-- Base schedulers
---------------------------------------------------------------------------

--- Random shuffle (Fisher-Yates). Default for most ABMs.
--- @param agents table[]
--- @param rng function() → [0,1)
--- @return table[] Shuffled copy
function M.shuffle(agents, rng)
    local copy = {}
    for i, a in ipairs(agents) do copy[i] = a end
    for i = #copy, 2, -1 do
        local j = math.floor(rng() * i) + 1
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

--- Sequential (insertion order). Deterministic.
--- @param agents table[]
--- @param _rng function
--- @return table[]
function M.sequential(agents, _rng)
    return agents
end

--- Reverse order.
--- @param agents table[]
--- @param _rng function
--- @return table[]
function M.reverse(agents, _rng)
    local copy = {}
    for i = #agents, 1, -1 do
        copy[#copy + 1] = agents[i]
    end
    return copy
end

---------------------------------------------------------------------------
-- Combinators — compose schedulers while preserving the signature
---------------------------------------------------------------------------

--- Filter agents by state.tag, then delegate to inner scheduler.
--- @param tag string Target tag value
--- @param inner function Scheduler
--- @return function Scheduler (same signature)
function M.filter_tag(tag, inner)
    return function(agents, rng)
        local filtered = {}
        for _, a in ipairs(agents) do
            if a.state and a.state.tag == tag then
                filtered[#filtered + 1] = a
            end
        end
        return inner(filtered, rng)
    end
end

--- Filter agents by a predicate function, then delegate.
--- @param pred function(agent) → boolean
--- @param inner function Scheduler
--- @return function Scheduler (same signature)
function M.filter(pred, inner)
    return function(agents, rng)
        local filtered = {}
        for _, a in ipairs(agents) do
            if pred(a) then filtered[#filtered + 1] = a end
        end
        return inner(filtered, rng)
    end
end

--- Concatenate two schedulers (group A executes, then group B).
--- @param sched_a function
--- @param sched_b function
--- @return function Scheduler (same signature)
function M.concat(sched_a, sched_b)
    return function(agents, rng)
        local a = sched_a(agents, rng)
        local b = sched_b(agents, rng)
        local result = {}
        for _, x in ipairs(a) do result[#result + 1] = x end
        for _, x in ipairs(b) do result[#result + 1] = x end
        return result
    end
end

--- Pipe: apply schedulers sequentially (output of A feeds into B).
--- Useful for sort-then-filter patterns.
--- @param ... function Schedulers
--- @return function Scheduler (same signature)
function M.pipe(...)
    local scheds = { ... }
    return function(agents, rng)
        local current = agents
        for _, sched in ipairs(scheds) do
            current = sched(current, rng)
        end
        return current
    end
end

return M
