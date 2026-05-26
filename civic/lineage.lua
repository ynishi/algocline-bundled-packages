--- civic.lineage — parent-child edge graph with generation tag and mutation_op hook
---
--- Pure in-memory directed graph where each edge records a parent slot producing
--- a child slot at a given generation. The Q1 mutation_op subordinate lives here
--- as the payload-transform hook of edge creation — lineage and mutation always
--- co-occur, so wrapping mutation_op into lineage avoids primitive proliferation.
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need lineage in isolation:
--- `require("civic.lineage")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local lin = require("civic.lineage")
--- local g = lin.new()
--- g:set_mutation_op(function(parent_payload)
---     return { strategy = parent_payload.strategy, fitness = parent_payload.fitness * 0.9 }
--- end)
--- local child = g:beget(1, 2, 1, { strategy = "coop", fitness = 10 })
--- -- child == { strategy = "coop", fitness = 9 }
--- assert(g:parent(2) == 1)
--- assert(g:generation(2) == 1)
--- ```
---
--- ## Algorithm
---
--- 1. **Register** — `set_mutation_op(fn)` stores the mutation function.
--- 2. **Beget** — `beget(parent_slot, child_slot, gen, parent_payload)` invokes
---    `fn(parent_payload)` to produce a child payload, records the edge
---    `{ parent, child, gen }` in the append-only log, updates indexed accessors,
---    and returns the child payload.
--- 3. **Query** — `parent(child_slot)`, `children(parent_slot)`, `generation(slot)`
---    reflect the latest beget on each slot (overwrite on reuse).
--- 4. **Inspect** — `edges()` returns a defensive copy of the full edge history;
---    `size()` returns the edge count.
---
--- ## Entry contract
---
--- - `new` — factory; returns an empty lineage graph (table).
--- - `Lineage:set_mutation_op(fn)` — register mutation function. No return value.
--- - `Lineage:beget(parent_slot, child_slot, gen, parent_payload)` — return child payload.
--- - `Lineage:parent(child_slot)` — latest parent of child_slot (or nil).
--- - `Lineage:children(parent_slot)` — list of child slots (defensive copy).
--- - `Lineage:generation(slot)` — generation number (0 if unknown).
--- - `Lineage:edges()` — defensive copy of the full edge log.
--- - `Lineage:size()` — edge count.
---
--- ## Caveats
---
--- **Mutation_op required**: `:beget` raises if `set_mutation_op` has not been
--- called. The mutation function must return a table.
---
--- **Slot reuse semantics**: `edges()` is append-only history (every beget
--- appends). But `parent(slot)`, `children(slot)`, and `generation(slot)` reflect
--- only the latest beget on that slot (overwrite on reuse). Callers needing the
--- original parent of a slot at generation N must walk `edges()` themselves.
---
--- **Generation is caller-managed**: the `gen` parameter is stored as-is. The
--- lineage graph does not auto-increment or validate generation ordering.
---
--- **No LLM dependency**: civic.lineage is a pure in-memory data-structure
--- module. `alc.llm` is never called.

local M = {}

local Lineage = {}
Lineage.__index = Lineage

local function require_pos_int(v, name, fn)
    if type(v) ~= "number" or v < 1 or math.floor(v) ~= v then
        error("civic.lineage." .. fn .. ": " .. name .. " must be positive integer (got " .. tostring(v) .. ")")
    end
end

--- Build an empty lineage graph.
---
---@return table lineage instance
function M.new()
    return setmetatable({
        _mutation_op = nil,
        _edges = {},
        _parent_of = {},
        _children_of = {},
        _gen_of = {},
    }, Lineage)
end

--- Register the mutation_op (Q1 subordinate).
---
---@param fn function fn(parent_payload: table) -> table
---@return nil
function Lineage:set_mutation_op(fn)
    if type(fn) ~= "function" then
        error("civic.lineage.set_mutation_op: fn must be function (got " .. type(fn) .. ")")
    end
    self._mutation_op = fn
end

--- Create a child payload from parent via mutation_op, record the edge,
--- return child payload.
---
---@param parent_slot number   Positive integer
---@param child_slot number    Positive integer
---@param gen number           Non-negative integer (generation number)
---@param parent_payload table Parent payload passed to mutation_op
---@return table
function Lineage:beget(parent_slot, child_slot, gen, parent_payload)
    if type(self._mutation_op) ~= "function" then
        error("civic.lineage.beget: mutation_op not set (call set_mutation_op first)")
    end
    require_pos_int(parent_slot, "parent_slot", "beget")
    require_pos_int(child_slot, "child_slot", "beget")
    if type(gen) ~= "number" or gen < 0 or math.floor(gen) ~= gen then
        error("civic.lineage.beget: gen must be non-negative integer (got " .. tostring(gen) .. ")")
    end
    if type(parent_payload) ~= "table" then
        error("civic.lineage.beget: parent_payload must be table (got " .. type(parent_payload) .. ")")
    end
    local child_payload = self._mutation_op(parent_payload)
    if type(child_payload) ~= "table" then
        error("civic.lineage.beget: mutation_op must return table (got " .. type(child_payload) .. ")")
    end
    table.insert(self._edges, { parent = parent_slot, child = child_slot, gen = gen })
    self._parent_of[child_slot] = parent_slot
    if not self._children_of[parent_slot] then
        self._children_of[parent_slot] = {}
    end
    table.insert(self._children_of[parent_slot], child_slot)
    self._gen_of[child_slot] = gen
    return child_payload
end

--- Latest parent of child_slot (or nil if no beget recorded for that slot).
---
---@param child_slot number
---@return number|nil
function Lineage:parent(child_slot)
    return self._parent_of[child_slot]
end

--- List of child slots begotten by parent_slot (defensive copy).
---
---@param parent_slot number
---@return number[]
function Lineage:children(parent_slot)
    local list = self._children_of[parent_slot]
    if not list then return {} end
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    return copy
end

--- Generation number of slot (0 if no beget recorded).
---
---@param slot number
---@return integer
function Lineage:generation(slot)
    return self._gen_of[slot] or 0
end

--- Defensive copy of the full edge history.
---
---@return table[]
function Lineage:edges()
    local copy = {}
    for i, e in ipairs(self._edges) do
        copy[i] = { parent = e.parent, child = e.child, gen = e.gen }
    end
    return copy
end

--- Edge count.
---
---@return integer
function Lineage:size() return #self._edges end

M.Lineage = Lineage
return M
