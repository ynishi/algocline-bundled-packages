--- civic.transition_rules — slot state-machine policy (first-match-wins rule table)
---
--- Pure in-memory rule table that maps `{ state = from } + predicate(payload, ctx)`
--- to a new state. Rules are evaluated in registration order; the first matching
--- rule wins and the returned payload carries the rewritten state field. All other
--- payload fields are shallow-copied unchanged.
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need transition rules in isolation:
--- `require("civic.transition_rules")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local tr = require("civic.transition_rules")
--- local rules = tr.new()
--- rules:add("alive", "dead", function(p, ctx)
---     return ctx.neighbors < 2 or ctx.neighbors > 3
--- end)
--- rules:add("dead", "alive", function(p, ctx)
---     return ctx.neighbors == 3
--- end)
--- local out = rules:apply({ state = "alive", energy = 5 }, { neighbors = 1 })
--- -- out == { state = "dead", energy = 5 }
--- ```
---
--- ## Algorithm
---
--- 1. **Register** — `add(from, to, predicate)` appends a rule to the ordered list.
--- 2. **Apply** — `apply(payload, ctx)` iterates rules in registration order. For
---    each rule where `payload.state == from` and `predicate(payload, ctx)` is
---    truthy, the payload is shallow-copied with `state = to` and returned
---    immediately (first-match-wins). If no rule matches, a shallow copy with the
---    original state is returned.
---
--- ## Entry contract
---
--- - `new` — factory; returns an empty rule set (table).
--- - `Rules:add(from, to, predicate)` — append a rule. No return value.
--- - `Rules:apply(payload, ctx)` — return shallow-copied payload with state possibly rewritten.
--- - `Rules:size()` — number of registered rules.
---
--- ## Caveats
---
--- **First-match-wins semantics**: rule evaluation order matters. If two rules
--- share the same `from` state, the one registered first takes priority. Callers
--- must register rules in the intended priority order.
---
--- **Shallow copy on apply**: `:apply` always returns a new table. The original
--- payload table is never mutated. Nested tables within payload fields are shared
--- references (not deep-copied).
---
--- **Predicate contract**: `predicate(payload, ctx)` receives the original (pre-copy)
--- payload and the caller-provided context. Predicates must be side-effect-free.
--- Exceptions raised by predicates propagate directly to the caller.
---
--- **No LLM dependency**: civic.transition_rules is a pure in-memory data-structure
--- module. `alc.llm` is never called.

local M = {}

local Rules = {}
Rules.__index = Rules

--- Build an empty rule set.
---
---@return table rules instance
function M.new()
    return setmetatable({ _rules = {} }, Rules)
end

--- Append a transition rule evaluated in registration order (first-match-wins).
---
---@param from string      Source state (payload.state must equal this to match)
---@param to string        Destination state (payload.state will be set to this)
---@param predicate function predicate(payload, ctx) -> boolean
---@return nil
function Rules:add(from, to, predicate)
    if type(from) ~= "string" or from == "" then
        error("civic.transition_rules.add: from must be non-empty string (got " .. type(from) .. ")")
    end
    if type(to) ~= "string" or to == "" then
        error("civic.transition_rules.add: to must be non-empty string (got " .. type(to) .. ")")
    end
    if type(predicate) ~= "function" then
        error("civic.transition_rules.add: predicate must be function (got " .. type(predicate) .. ")")
    end
    table.insert(self._rules, { from = from, to = to, predicate = predicate })
end

--- Apply rules to payload; returns a new (shallow-copied) table with state
--- possibly rewritten. If no rule matches, returns a shallow copy unchanged.
---
---@param payload table  Must contain a `state` string field
---@param ctx any        Optional context forwarded to predicates
---@return table
function Rules:apply(payload, ctx)
    if type(payload) ~= "table" then
        error("civic.transition_rules.apply: payload must be table (got " .. type(payload) .. ")")
    end
    if type(payload.state) ~= "string" then
        error("civic.transition_rules.apply: payload.state must be string (got " .. type(payload.state) .. ")")
    end
    local out = {}
    for k, v in pairs(payload) do out[k] = v end
    for _, rule in ipairs(self._rules) do
        if rule.from == payload.state and rule.predicate(payload, ctx) then
            out.state = rule.to
            return out
        end
    end
    return out
end

--- Number of registered rules.
---
---@return integer
function Rules:size() return #self._rules end

M.Rules = Rules
return M
