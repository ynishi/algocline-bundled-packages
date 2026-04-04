--- abm.frame.agent — Agent definition protocol
---
--- Smart Constructor (DSL Layer 1.5): validates at construction time.
--- Agents are tables with a mandatory step(self, model) function.
---
--- Usage:
---   local Agent = require("abm.frame.agent")
---   local buyer = Agent.define {
---       state = { budget = 100 },
---       step = function(self, model)
---           -- decision logic here
---       end,
---   }
---
---   -- Bulk creation with per-instance state
---   local buyers = Agent.populate(buyer_spec, 50, function(i)
---       return { budget = 80 + i * 2 }
---   end)

local M = {}

local AGENT_TAG = "abm.agent"

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- Deep-copy a flat state table (1 level).
local function copy_state(src)
    if not src then return {} end
    local dst = {}
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

--- Define an agent specification.
--- Returns a frozen spec table (template). Use populate() or new() to
--- create mutable instances from it.
---
--- @param spec table
---   step: function(self, model)          — mandatory
---   before_step?: function(self, model)  — called before step
---   after_step?: function(self, model)   — called after step
---   state?: table                        — per-instance mutable data
--- @return table Agent spec (template)
function M.define(spec)
    if type(spec) ~= "table" then
        error("Agent.define: spec must be a table", 2)
    end
    if type(spec.step) ~= "function" then
        error("Agent.define: spec.step must be a function(self, model)", 2)
    end
    return {
        _tag = AGENT_TAG,
        _spec = true,
        step = spec.step,
        before_step = spec.before_step,
        after_step = spec.after_step,
        state_template = spec.state or {},
    }
end

--- Create a single mutable agent instance from a spec.
--- @param spec table Agent spec (from define())
--- @param state_override? table Merged into state
--- @return table Agent instance
function M.new(spec, state_override)
    if not spec._spec then
        error("Agent.new: expected a spec from Agent.define()", 2)
    end
    local state = copy_state(spec.state_template)
    if state_override then
        for k, v in pairs(state_override) do state[k] = v end
    end

    local noop = function() end
    return {
        _tag = AGENT_TAG,
        step = spec.step,
        before_step = spec.before_step or noop,
        after_step = spec.after_step or noop,
        state = state,
    }
end

--- Bulk-create agent instances from a spec.
--- @param spec table Agent spec (from define())
--- @param n number Count
--- @param init_fn? function(i) → state override table
--- @return table[] Array of agent instances
function M.populate(spec, n, init_fn)
    if type(n) ~= "number" or n < 1 then
        error("Agent.populate: n must be a positive number", 2)
    end
    local agents = {}
    for i = 1, n do
        local override = init_fn and init_fn(i) or nil
        agents[i] = M.new(spec, override)
    end
    return agents
end

--- Check if a value is an agent instance.
function M.is_agent(v)
    return type(v) == "table" and v._tag == AGENT_TAG and not v._spec
end

return M
