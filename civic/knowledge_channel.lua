--- civic.knowledge_channel — predecessor to successor rich payload transform
---
--- Pure in-memory transfer channel that applies a caller-registered transform
--- function to a payload as it flows from a predecessor slot to a successor slot.
--- Each transfer is logged in an append-only history for auditability.
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need the channel in isolation:
--- `require("civic.knowledge_channel")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local kc = require("civic.knowledge_channel")
--- local ch = kc.new()
--- ch:set_transform(function(payload, ctx)
---     return { strategy = payload.strategy, wins = payload.wins + 1 }
--- end)
--- local out = ch:transfer(1, 2, { strategy = "tit-for-tat", wins = 3 })
--- -- out == { strategy = "tit-for-tat", wins = 4 }
--- assert(ch:size() == 1)
--- ```
---
--- ## Algorithm
---
--- 1. **Register** — `set_transform(fn)` stores the transform function.
--- 2. **Transfer** — `transfer(predecessor, successor, payload, ctx?)` invokes
---    `fn(payload, ctx)`, validates the return is a table, appends
---    `{ predecessor, successor }` to the history log, and returns the
---    transformed payload.
--- 3. **Inspect** — `history()` returns a defensive copy of the transfer log;
---    `size()` returns the number of recorded transfers.
---
--- ## Entry contract
---
--- - `new` — factory; returns an empty channel (table).
--- - `Channel:set_transform(fn)` — register transform_fn. No return value.
--- - `Channel:transfer(predecessor, successor, payload, ctx?)` — return transformed payload.
--- - `Channel:history()` — defensive copy of the transfer log.
--- - `Channel:size()` — number of recorded transfers.
---
--- ## Caveats
---
--- **Transform function required**: `:transfer` raises if `set_transform` has not
--- been called. The channel is policy-free — all domain-specific reshaping,
--- synthesis, or projection logic lives in the transform function.
---
--- **Transform return type**: the transform function must return a table.
--- Returning nil or a non-table value raises an error.
---
--- **History is append-only**: the transfer log records `{ predecessor, successor }`
--- pairs and never shrinks. Callers needing bounded history must manage that
--- externally.
---
--- **Distinct from lineage mutation_op**: lineage's Q1 mutation_op is for
--- stateless numeric/vector single-op variation that always co-occurs with
--- parent-child edges. Knowledge channel handles structural payload transforms
--- (schema reshape, hash projection, etc.) independent of the lineage graph.
---
--- **No LLM dependency**: civic.knowledge_channel is a pure in-memory
--- data-structure module. `alc.llm` is never called.

local M = {}

local Channel = {}
Channel.__index = Channel

local function require_pos_int(v, name, fn)
    if type(v) ~= "number" or v < 1 or math.floor(v) ~= v then
        error("civic.knowledge_channel." .. fn .. ": " .. name .. " must be positive integer (got " .. tostring(v) .. ")")
    end
end

--- Build an empty channel.
---
---@return table channel instance
function M.new()
    return setmetatable({ _transform = nil, _history = {} }, Channel)
end

--- Register the transform function.
---
---@param fn function fn(payload: table, ctx?: table) -> table
---@return nil
function Channel:set_transform(fn)
    if type(fn) ~= "function" then
        error("civic.knowledge_channel.set_transform: fn must be function (got " .. type(fn) .. ")")
    end
    self._transform = fn
end

--- Apply transform to payload, record the transfer, return transformed payload.
---
---@param predecessor number  Predecessor slot index (positive integer)
---@param successor number    Successor slot index (positive integer)
---@param payload table       Payload to transform
---@param ctx table|nil       Optional context forwarded to transform function
---@return table
function Channel:transfer(predecessor, successor, payload, ctx)
    if type(self._transform) ~= "function" then
        error("civic.knowledge_channel.transfer: transform not set (call set_transform first)")
    end
    require_pos_int(predecessor, "predecessor", "transfer")
    require_pos_int(successor, "successor", "transfer")
    if type(payload) ~= "table" then
        error("civic.knowledge_channel.transfer: payload must be table (got " .. type(payload) .. ")")
    end
    if ctx ~= nil and type(ctx) ~= "table" then
        error("civic.knowledge_channel.transfer: ctx must be table or nil (got " .. type(ctx) .. ")")
    end
    local transformed = self._transform(payload, ctx)
    if type(transformed) ~= "table" then
        error("civic.knowledge_channel.transfer: transform must return table (got " .. type(transformed) .. ")")
    end
    table.insert(self._history, { predecessor = predecessor, successor = successor })
    return transformed
end

--- Defensive copy of the transfer log.
---
---@return table[]
function Channel:history()
    local copy = {}
    for i, h in ipairs(self._history) do
        copy[i] = { predecessor = h.predecessor, successor = h.successor }
    end
    return copy
end

--- Number of recorded transfers.
---
---@return integer
function Channel:size() return #self._history end

M.Channel = Channel
return M
