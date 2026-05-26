--- civic — civic-frame primitives for swarm simulations
---
--- Aggregation hub for the civic-frame component library. Each component is a
--- flat Lua module that exposes a domain-specific primitive for swarm simulations.
--- This file is the single entry point callers use to access all components.
---
--- ## Usage
---
--- ```lua
--- local civic = require("civic")
---
--- -- Create a broadcast bus for a swarm round
--- local bus = civic.broadcast_bus.new()
---
--- -- Producers publish (e.g. every cell in one step)
--- bus:publish(1, { signal = 0.9 })
--- bus:publish(2, { signal = 0.4 })
---
--- -- Consumer aggregates selected signals
--- local max_signal = bus:aggregate_for(
---     99,
---     function(src) return src == 1 or src == 2 end,
---     function(msgs)
---         local best = 0
---         for _, m in ipairs(msgs) do
---             if m.signal > best then best = m.signal end
---         end
---         return best
---     end
--- )
---
--- bus:reset()  -- clear before next round
--- ```
---
--- ## Caveats
---
--- **Module structure**: `civic/init.lua` (this file) owns `M.meta` and the
--- aggregate `M.shape` table. Each `civic/<name>.lua` is a component module
--- with no `M.meta` and no `M.shape`. components expose only their own API.
---
--- **Shape descriptors**: `M.shape.broadcast_entry` documents the entry shape
--- used internally by `broadcast_bus`. Callers may reference it for documentation
--- or tooling; the bus itself does not enforce it at runtime (payload is opaque).
---
--- **No LLM dependency**: all civic-frame components are pure in-memory
--- data-structure primitives. `alc.llm` is never called. civic may be used
--- freely in synchronous, non-LLM orchestration and simulation code.
---
--- **Component independence**: each component can also be required directly
--- (`require("civic.broadcast_bus")`, `require("civic.ledger")`, etc.) for
--- callers that want to import only a subset. The canonical path for most
--- callers is `require("civic")`.

local M = {}

---@type AlcMeta
M.meta = {
    name        = "civic",
    version     = "0.1.0",
    description = "civic-frame primitives — bus / state / channel / policy components for swarm simulations.",
    category    = "substrate",
    alc_shapes_compat = "^0.25",
}

-- components
M.broadcast_bus    = require("civic.broadcast_bus")
M.transition_rules = require("civic.transition_rules")
M.slot_table       = require("civic.slot_table")
M.knowledge_channel = require("civic.knowledge_channel")
M.lineage          = require("civic.lineage")
M.ledger           = require("civic.ledger")
M.scalar_pool      = require("civic.scalar_pool")

-- M.shape: aggregate shape descriptors for civic-frame data entries.
local S = require("alc_shapes")
local T = S.T
M.shape = {
    broadcast_entry = T.shape({
        src = T.number:describe("Source slot index (positive integer)"),
        msg = T.any:describe("Opaque payload published by the source slot"),
    }),
    transition_rule = T.shape({
        from = T.string:describe("Source state that must match payload.state"),
        to   = T.string:describe("Destination state written on match"),
    }),
    slot_payload = T.shape({
        state = T.string:describe("Slot state label (domain-specific)"),
    }),
    transfer_record = T.shape({
        predecessor = T.number:describe("Predecessor slot index"),
        successor   = T.number:describe("Successor slot index"),
    }),
    lineage_edge = T.shape({
        parent = T.number:describe("Parent slot index"),
        child  = T.number:describe("Child slot index"),
        gen    = T.number:describe("Generation number (non-negative integer)"),
    }),
    ledger_tx = T.shape({
        kind   = T.string:describe("Transaction kind: 'credit' or 'transfer'"),
        amount = T.number:describe("Transaction amount (positive)"),
    }),
    scalar_bucket = T.shape({
        slot   = T.number:describe("Slot index (positive integer)"),
        source = T.string:describe("Source label (non-empty string)"),
        value  = T.number:describe("Accumulated scalar value"),
    }),
}

return M
