--- civic.scalar_pool — multi-source per-slot scalar accumulator with decay
---
--- Pure in-memory accumulator where each slot has multiple named source buckets.
--- Credits and debits add to or subtract from a `(slot, source)` bucket; decay
--- multiplies all buckets by a rate in [0, 1]. No conservation invariant across
--- slots — this is accumulate semantic, not transfer semantic (see ledger for
--- zero-sum transfers).
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need the pool in isolation:
--- `require("civic.scalar_pool")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local sp = require("civic.scalar_pool")
--- local pool = sp.new()
--- pool:credit(1, "tournament", 5.0)
--- pool:credit(1, "peer", 2.0)
--- assert(pool:total(1) == 7.0)
--- assert(pool:by_source(1, "tournament") == 5.0)
--- pool:apply_decay(0.5)
--- assert(pool:by_source(1, "tournament") == 2.5)
--- pool:reset(1)
--- assert(pool:total(1) == 0)
--- ```
---
--- ## Algorithm
---
--- 1. **Credit** — `credit(slot, source, amount)` adds `amount` (positive or
---    negative) to the `(slot, source)` bucket.
--- 2. **Debit** — `debit(slot, source, amount)` subtracts `amount` (convenience
---    wrapper over credit with negated amount).
--- 3. **Query** — `by_source(slot, source)` returns a single bucket value;
---    `total(slot)` sums across all sources for a slot.
--- 4. **Decay** — `apply_decay(rate)` multiplies every `(slot, source)` bucket
---    by `rate` in [0, 1].
--- 5. **Reset** — `reset(slot)` drops a slot entirely from the pool.
--- 6. **Enumerate** — `slots()` returns a sorted list of slot indices currently
---    in the pool.
---
--- ## Entry contract
---
--- - `new` — factory; returns an empty pool (table).
--- - `Pool:credit(slot, source, amount)` — add to bucket. No return value.
--- - `Pool:debit(slot, source, amount)` — subtract from bucket. No return value.
--- - `Pool:by_source(slot, source)` — current bucket value (0 if absent).
--- - `Pool:total(slot)` — sum across all sources for slot (0 if absent).
--- - `Pool:reset(slot)` — drop slot from pool.
--- - `Pool:apply_decay(rate)` — multiply all buckets by rate in [0, 1].
--- - `Pool:slots()` — sorted list of active slot indices.
---
--- ## Caveats
---
--- **Accumulate, not transfer**: there is no conservation invariant. Credits
--- and debits are independent per slot. For zero-sum bookkeeping, use the
--- ledger component.
---
--- **Decay is global**: `apply_decay(rate)` affects every `(slot, source)`
--- bucket in the pool. Callers needing per-source decay rates must apply
--- decay manually via credit/debit.
---
--- **Source is a string label**: source buckets are keyed by non-empty strings.
--- The pool does not enumerate or validate source names; callers coordinate
--- source naming conventions within their domain.
---
--- **No LLM dependency**: civic.scalar_pool is a pure in-memory data-structure
--- module. `alc.llm` is never called.

local M = {}

local Pool = {}
Pool.__index = Pool

local function require_pos_int(v, name, fn)
    if type(v) ~= "number" or v < 1 or math.floor(v) ~= v then
        error("civic.scalar_pool." .. fn .. ": " .. name .. " must be positive integer (got " .. tostring(v) .. ")")
    end
end

local function require_source(s, fn)
    if type(s) ~= "string" or s == "" then
        error("civic.scalar_pool." .. fn .. ": source must be non-empty string (got " .. type(s) .. ")")
    end
end

local function require_number(v, name, fn)
    if type(v) ~= "number" then
        error("civic.scalar_pool." .. fn .. ": " .. name .. " must be number (got " .. type(v) .. ")")
    end
end

--- Build an empty pool.
---
---@return table pool instance
function M.new()
    return setmetatable({ _balances = {} }, Pool)
end

--- Add amount (positive or negative) to the (slot, source) bucket.
---
---@param slot number    Positive integer
---@param source string  Non-empty source label
---@param amount number  Amount to add
---@return nil
function Pool:credit(slot, source, amount)
    require_pos_int(slot, "slot", "credit")
    require_source(source, "credit")
    require_number(amount, "amount", "credit")
    self._balances[slot] = self._balances[slot] or {}
    self._balances[slot][source] = (self._balances[slot][source] or 0) + amount
end

--- Subtract amount from the (slot, source) bucket (convenience for credit of -amount).
---
---@param slot number    Positive integer
---@param source string  Non-empty source label
---@param amount number  Amount to subtract
---@return nil
function Pool:debit(slot, source, amount)
    require_pos_int(slot, "slot", "debit")
    require_source(source, "debit")
    require_number(amount, "amount", "debit")
    self._balances[slot] = self._balances[slot] or {}
    self._balances[slot][source] = (self._balances[slot][source] or 0) - amount
end

--- Current value in the (slot, source) bucket (0 if absent).
---
---@param slot number
---@param source string
---@return number
function Pool:by_source(slot, source)
    local s = self._balances[slot]
    if not s then return 0 end
    return s[source] or 0
end

--- Sum across all sources for slot (0 if absent).
---
---@param slot number
---@return number
function Pool:total(slot)
    local s = self._balances[slot]
    if not s then return 0 end
    local sum = 0
    for _, amt in pairs(s) do sum = sum + amt end
    return sum
end

--- Drop slot from pool (slot death / reuse).
---
---@param slot number Positive integer
---@return nil
function Pool:reset(slot)
    require_pos_int(slot, "slot", "reset")
    self._balances[slot] = nil
end

--- Multiply every (slot, source) bucket by rate in [0, 1].
---
---@param rate number  Decay rate in [0, 1]
---@return nil
function Pool:apply_decay(rate)
    if type(rate) ~= "number" or rate < 0 or rate > 1 then
        error("civic.scalar_pool.apply_decay: rate must be number in [0, 1] (got " .. tostring(rate) .. ")")
    end
    for slot, sources in pairs(self._balances) do
        for source, amt in pairs(sources) do
            self._balances[slot][source] = amt * rate
        end
    end
end

--- Sorted list of slot indices currently in the pool.
---
---@return integer[]
function Pool:slots()
    local out = {}
    for slot, _ in pairs(self._balances) do out[#out + 1] = slot end
    table.sort(out)
    return out
end

M.Pool = Pool
return M
