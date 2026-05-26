--- civic.ledger — zero-sum transfer state with credit inflow and transaction log
---
--- Pure in-memory double-entry bookkeeping primitive. Transfers between slots
--- are strictly zero-sum; the only way to increase `total()` is through
--- `:credit` (external inflow). An append-only transaction log records every
--- credit and transfer for auditability.
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need the ledger in isolation:
--- `require("civic.ledger")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local lg = require("civic.ledger")
--- local book = lg.new()
--- book:credit(1, 100)
--- book:credit(2, 50)
--- assert(book:total() == 150)
--- local ok = book:transfer(1, 2, 30)
--- assert(ok == true)
--- assert(book:balance(1) == 70)
--- assert(book:balance(2) == 80)
--- assert(book:total() == book:credit_total())  -- invariant
--- ```
---
--- ## Algorithm
---
--- 1. **Credit** — `credit(slot, amount)` adds external inflow to a slot's
---    balance and increments the running credit total.
--- 2. **Transfer** — `transfer(from, to, amount)` moves funds between slots.
---    When `allow_negative` is false (default), insufficient funds returns
---    `false` without modifying any balance.
--- 3. **Query** — `balance(slot)` returns a single slot's balance; `total()`
---    sums all balances; `credit_total()` returns cumulative external inflows.
--- 4. **Inspect** — `transactions()` returns a defensive copy of the full log;
---    `size()` returns the transaction count.
---
--- ## Entry contract
---
--- - `new(opts?)` — factory; returns an empty ledger. `opts.allow_negative` (default false).
--- - `Ledger:credit(slot, amount)` — external inflow. No return value.
--- - `Ledger:transfer(from, to, amount)` — zero-sum transfer; returns boolean.
--- - `Ledger:balance(slot)` — current balance (0 for unknown slots).
--- - `Ledger:total()` — sum of all balances.
--- - `Ledger:credit_total()` — cumulative external inflows.
--- - `Ledger:transactions()` — defensive copy of the transaction log.
--- - `Ledger:size()` — transaction count.
---
--- ## Caveats
---
--- **Zero-sum invariant**: `total() == credit_total()` must hold after any
--- sequence of credit and transfer operations. Transfers move funds between
--- slots without creating or destroying value.
---
--- **Insufficient funds**: when `allow_negative` is false (default), a transfer
--- that would push the sender's balance below zero is rejected (returns false).
--- Set `allow_negative = true` for margin/debt semantics where balances may
--- go negative.
---
--- **Self-transfer prohibited**: `transfer(slot, slot, amount)` raises an error.
--- A self-transfer is a no-op that would clutter the transaction log.
---
--- **No LLM dependency**: civic.ledger is a pure in-memory data-structure
--- module. `alc.llm` is never called.

local M = {}

local Ledger = {}
Ledger.__index = Ledger

local function require_pos_int(v, name, fn)
    if type(v) ~= "number" or v < 1 or math.floor(v) ~= v then
        error("civic.ledger." .. fn .. ": " .. name .. " must be positive integer (got " .. tostring(v) .. ")")
    end
end

--- Build an empty ledger.
---
---@param opts table|nil  Optional config: { allow_negative = boolean (default false) }
---@return table ledger instance
function M.new(opts)
    opts = opts or {}
    local allow_negative = opts.allow_negative
    if allow_negative == nil then allow_negative = false end
    if type(allow_negative) ~= "boolean" then
        error("civic.ledger.new: opts.allow_negative must be boolean (got " .. type(allow_negative) .. ")")
    end
    return setmetatable({
        _balance = {},
        _credit_total = 0,
        _allow_negative = allow_negative,
        _txs = {},
    }, Ledger)
end

--- External inflow into slot (not zero-sum; increases total).
---
---@param slot number    Positive integer
---@param amount number  Non-negative amount
---@return nil
function Ledger:credit(slot, amount)
    require_pos_int(slot, "slot", "credit")
    if type(amount) ~= "number" or amount < 0 then
        error("civic.ledger.credit: amount must be non-negative number (got " .. tostring(amount) .. ")")
    end
    self._balance[slot] = (self._balance[slot] or 0) + amount
    self._credit_total = self._credit_total + amount
    table.insert(self._txs, { kind = "credit", to = slot, amount = amount })
end

--- Zero-sum transfer between slots. Returns true on success, false on
--- insufficient funds (when allow_negative is false).
---
---@param from number    Source slot (positive integer)
---@param to number      Destination slot (positive integer)
---@param amount number  Positive amount to transfer
---@return boolean
function Ledger:transfer(from, to, amount)
    require_pos_int(from, "from", "transfer")
    require_pos_int(to, "to", "transfer")
    if from == to then
        error("civic.ledger.transfer: from == to is meaningless (got " .. tostring(from) .. ")")
    end
    if type(amount) ~= "number" or amount <= 0 then
        error("civic.ledger.transfer: amount must be positive number (got " .. tostring(amount) .. ")")
    end
    local from_bal = self._balance[from] or 0
    if not self._allow_negative and from_bal < amount then
        return false
    end
    self._balance[from] = from_bal - amount
    self._balance[to] = (self._balance[to] or 0) + amount
    table.insert(self._txs, { kind = "transfer", from = from, to = to, amount = amount })
    return true
end

--- Current balance of slot (0 for unknown slots).
---
---@param slot number
---@return number
function Ledger:balance(slot)
    return self._balance[slot] or 0
end

--- Sum of all balances.
---
---@return number
function Ledger:total()
    local s = 0
    for _, b in pairs(self._balance) do s = s + b end
    return s
end

--- Cumulative external inflows.
---
---@return number
function Ledger:credit_total()
    return self._credit_total
end

--- Defensive copy of the transaction log.
---
---@return table[]
function Ledger:transactions()
    local copy = {}
    for i, t in ipairs(self._txs) do
        copy[i] = { kind = t.kind, from = t.from, to = t.to, amount = t.amount }
    end
    return copy
end

--- Transaction count.
---
---@return integer
function Ledger:size() return #self._txs end

M.Ledger = Ledger
return M
