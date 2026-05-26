--- civic.slot_table — indexed slot container with mechanical 5-op surface
---
--- Pure in-memory indexed container where each slot holds an arbitrary payload
--- table. Slots are initialized via a caller-provided `init_fn(idx)` callback,
--- giving full control over initial payloads without post-hoc replacement.
---
--- This module is a component of the `civic` package. It carries no `M.meta`
--- or `M.shape` field; those live in `civic/init.lua`. Require this module
--- directly only when you need slot storage in isolation:
--- `require("civic.slot_table")`. Most callers should use `require("civic")`.
---
--- ## Usage
---
--- ```lua
--- local st = require("civic.slot_table")
--- local slots = st.new(4, function(i)
---     return { state = "alive", energy = i * 10 }
--- end)
--- assert(slots:size() == 4)
--- local p = slots:get(2)
--- p.energy = 99
--- slots:set(2, p)
--- for idx, payload in slots:iter() do
---     -- process each slot
--- end
--- ```
---
--- ## Algorithm
---
--- 1. **Construct** — `new(n, init_fn)` allocates `n` slots, calling `init_fn(i)`
---    for each index `1..n` to obtain the initial payload table.
--- 2. **Read** — `get(idx)` returns the payload at slot `idx`.
--- 3. **Write** — `set(idx, payload)` replaces the payload at slot `idx`.
--- 4. **Iterate** — `iter()` returns a stateless iterator yielding `(idx, payload)`.
--- 5. **Size** — `size()` returns the fixed slot count.
---
--- ## Entry contract
---
--- - `new(n, init_fn)` — factory; returns a slot table of `n` slots.
--- - `SlotTable:get(idx)` — return payload at idx.
--- - `SlotTable:set(idx, payload)` — replace payload at idx.
--- - `SlotTable:iter()` — stateless iterator over (idx, payload).
--- - `SlotTable:size()` — fixed slot count (immutable after construction).
---
--- ## Caveats
---
--- **Fixed size**: the slot count is determined at construction and never changes.
--- There is no add/remove API; slot reuse (e.g. agent death/rebirth) is modeled
--- by overwriting the payload via `:set`.
---
--- **Payload is a table**: `init_fn` must return a table for each slot, and
--- `:set` requires a table. The slot table does not enforce payload field schema;
--- callers coordinate field conventions within their domain.
---
--- **Reference semantics**: `:get` returns the stored table reference directly
--- (not a copy). Mutations to the returned table are visible through subsequent
--- `:get` calls. Callers that need snapshot semantics must copy explicitly.
---
--- **No LLM dependency**: civic.slot_table is a pure in-memory data-structure
--- module. `alc.llm` is never called.

local M = {}

local SlotTable = {}
SlotTable.__index = SlotTable

local function require_pos_int(v, name, fn)
    if type(v) ~= "number" or v < 1 or math.floor(v) ~= v then
        error("civic.slot_table." .. fn .. ": " .. name .. " must be positive integer (got " .. tostring(v) .. ")")
    end
end

--- Build a slot table of `n` slots, each initialized by `init_fn(idx)`.
---
---@param n number       Positive integer — number of slots
---@param init_fn function init_fn(idx: number) -> table
---@return table slot table instance
function M.new(n, init_fn)
    require_pos_int(n, "n", "new")
    if type(init_fn) ~= "function" then
        error("civic.slot_table.new: init_fn must be function (got " .. type(init_fn) .. ")")
    end
    local slots = {}
    for i = 1, n do
        local p = init_fn(i)
        if type(p) ~= "table" then
            error("civic.slot_table.new: init_fn(" .. i .. ") must return table (got " .. type(p) .. ")")
        end
        slots[i] = p
    end
    return setmetatable({ _slots = slots, _n = n }, SlotTable)
end

--- Fixed slot count (immutable after construction).
---
---@return integer
function SlotTable:size() return self._n end

--- Return the payload at slot `idx`.
---
---@param idx number Positive integer in [1, size]
---@return table
function SlotTable:get(idx)
    require_pos_int(idx, "idx", "get")
    if idx > self._n then
        error("civic.slot_table.get: idx out of range (got " .. tostring(idx) .. ", size=" .. self._n .. ")")
    end
    return self._slots[idx]
end

--- Replace the payload at slot `idx` (state-write semantic).
---
---@param idx number     Positive integer in [1, size]
---@param payload table  New payload for the slot
---@return nil
function SlotTable:set(idx, payload)
    require_pos_int(idx, "idx", "set")
    if idx > self._n then
        error("civic.slot_table.set: idx out of range (got " .. tostring(idx) .. ", size=" .. self._n .. ")")
    end
    if type(payload) ~= "table" then
        error("civic.slot_table.set: payload must be table (got " .. type(payload) .. ")")
    end
    self._slots[idx] = payload
end

--- Stateless iterator over (idx, payload).
---
---@return function
function SlotTable:iter()
    local i = 0
    local n = self._n
    return function()
        i = i + 1
        if i > n then return nil end
        return i, self._slots[i]
    end
end

M.SlotTable = SlotTable
return M
