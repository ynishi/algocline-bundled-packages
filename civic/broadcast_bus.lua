--- civic.broadcast_bus — 1-to-N publish + selector/aggregation bus for swarm primitives
---
--- Pure in-memory, cross-pkg-require-free substrate that decouples message
--- producers from consumers. Producers call `:publish(src, msg)` each round;
--- consumers call `:aggregate_for(target, selector_fn, agg_fn)` to collect
--- the msgs that pass a domain-specific selector and reduce them via agg_fn.
--- Opaque payload — the bus imposes no field constraints on msg.
---
--- This module is a **Component** of the `civic` LogicPkg. It carries no
--- `M.meta` or `M.shape` field; those live in `civic/init.lua`. Require this
--- module directly only when you need the bus Component in isolation:
--- `require("civic.broadcast_bus")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local bus_mod = require("civic.broadcast_bus")
---
--- local bus = bus_mod.new()
---
--- -- Producers publish (e.g. all cells in a swarm step)
--- bus:publish(1, { value = 3 })
--- bus:publish(2, { value = 7 })
--- bus:publish(3, { value = 2 })
---
--- -- Consumer aggregates: sum values from slots 1 and 2
--- local total = bus:aggregate_for(
---     99,
---     function(src) return src == 1 or src == 2 end,
---     function(msgs)
---         local s = 0
---         for _, m in ipairs(msgs) do s = s + m.value end
---         return s
---     end
--- )
--- -- total == 10
---
--- bus:reset()  -- clear for next round
--- ```
---
--- ## Algorithm
---
--- Each round proceeds in three phases:
---
--- 1. **Publish** — every source slot pushes a `{ src, msg }` entry onto an
---    ordered list. Source must be a positive integer; msg may be any value.
--- 2. **Aggregate** — a consumer calls `aggregate_for(target, selector_fn, agg_fn)`.
---    The bus filters the published list to entries where `selector_fn(src)` is
---    truthy, then passes the collected msg list to `agg_fn` and returns its
---    result. The caller is responsible for all domain logic (neighborhood,
---    weighting, consensus, etc.) via the two injection points.
--- 3. **Reset** — `:reset()` clears the list at a round boundary; published msgs
---    do not persist across rounds.
---
--- ## Entry contract
---
--- - `new` — factory; returns an empty bus instance (table).
--- - `Bus:publish(src, msg)` — push msg from src slot. No return value.
--- - `Bus:aggregate_for(target, selector_fn, agg_fn)` — return agg_fn result.
--- - `Bus:reset()` — clear all msgs (round boundary).
---
--- ## Caveats
---
--- **Selector/aggregator injection**: `selector_fn` and `agg_fn` are the two
--- caller-owned extension points that carry all domain-specific logic. The bus
--- itself is policy-free. Callers must ensure `selector_fn` is side-effect-free
--- (called once per published entry per `aggregate_for` invocation) and that
--- `agg_fn` handles an empty list gracefully (the bus never guarantees at least
--- one match).
---
--- **Opaque payload**: the bus places no constraints on `msg` type or fields.
--- Callers must coordinate payload shape conventions between producers and
--- consumers within their own domain. The shape descriptor `civic.shape.broadcast_entry`
--- (in `civic/init.lua`) documents the canonical `{ src, msg }` envelope shape
--- for tooling, but the bus does not enforce it at runtime.
---
--- **Round boundary semantics**: `:reset()` is a caller responsibility. The bus
--- does not auto-reset; msgs accumulate across multiple publish calls within a
--- round. Calling `aggregate_for` on an empty bus (before any publish or after
--- reset) yields `agg_fn({})`.
---
--- **O(P) per aggregate call** where P is the number of published entries: the
--- bus scans all entries linearly. For large swarms (P in the thousands),
--- callers may want to shard or pre-filter at the domain layer.
---
--- **No LLM dependency**: civic.broadcast_bus is a pure in-memory data-structure
--- Component. `alc.llm` is never called. It may be used freely in synchronous,
--- non-LLM orchestration code.

local M = {}

local Bus = {}
Bus.__index = Bus

--- Build an empty bus instance.
---
---@return table bus instance
function M.new()
    return setmetatable({ _msgs = {} }, Bus)
end

--- Clear all published msgs (round boundary).
--- Call this at the end of each swarm step before the next round of publishes.
---
---@return nil
function Bus:reset()
    self._msgs = {}
end

--- Publish `msg` from `src` slot. `msg` may be any value (opaque payload).
---
---@param src number Source slot index (must be a positive integer)
---@param msg any   Opaque payload; no field constraints imposed by the bus
---@return nil
function Bus:publish(src, msg)
    if type(src) ~= "number" or src < 1 or math.floor(src) ~= src then
        error("civic_broadcast_bus.publish: src must be positive integer (got " .. tostring(src) .. ")")
    end
    table.insert(self._msgs, { src = src, msg = msg })
end

--- Aggregate published msgs from the perspective of `target` slot.
---
--- Scans all published entries. For each entry whose source passes
--- `selector_fn(src)`, the entry's `msg` is added to a list.
--- `agg_fn` receives the filtered msg list and its return value is
--- returned to the caller. If no entries pass, `agg_fn({})` is called.
---
---@param target      number   Target slot index (positive integer; informational only — the bus does not self-filter by target)
---@param selector_fn function selector_fn(src: number) -> boolean — return true to include msg
---@param agg_fn      function agg_fn(msg_list: table) -> any — reduce the selected msgs
---@return any
function Bus:aggregate_for(target, selector_fn, agg_fn)
    if type(target) ~= "number" or target < 1 or math.floor(target) ~= target then
        error("civic_broadcast_bus.aggregate_for: target must be positive integer (got " .. tostring(target) .. ")")
    end
    if type(selector_fn) ~= "function" then
        error("civic_broadcast_bus.aggregate_for: selector_fn must be function (got " .. type(selector_fn) .. ")")
    end
    if type(agg_fn) ~= "function" then
        error("civic_broadcast_bus.aggregate_for: agg_fn must be function (got " .. type(agg_fn) .. ")")
    end
    local picked = {}
    for _, entry in ipairs(self._msgs) do
        if selector_fn(entry.src) then
            table.insert(picked, entry.msg)
        end
    end
    return agg_fn(picked)
end

-- Expose the Bus metatable for callers that want to extend or type-check.
M.Bus = Bus

return M
