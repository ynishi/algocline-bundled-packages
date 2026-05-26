---
name: civic
version: 0.1.0
category: substrate
description: "civic-frame primitives — bus / state / channel / policy components for swarm simulations."
source: civic/init.lua
generated: gen_docs (V0)
---

# civic — civic-frame primitives for swarm simulations

> Aggregation hub for the civic-frame component library. Each component is a flat Lua module that exposes a domain-specific primitive for swarm simulations. This file is the single entry point callers use to access all components.

## Contents

- [Usage](#usage)
- [Caveats](#caveats)

## Usage {#usage}

```lua
local civic = require("civic")

-- Create a broadcast bus for a swarm round
local bus = civic.broadcast_bus.new()

-- Producers publish (e.g. every cell in one step)
bus:publish(1, { signal = 0.9 })
bus:publish(2, { signal = 0.4 })

-- Consumer aggregates selected signals
local max_signal = bus:aggregate_for(
    99,
    function(src) return src == 1 or src == 2 end,
    function(msgs)
        local best = 0
        for _, m in ipairs(msgs) do
            if m.signal > best then best = m.signal end
        end
        return best
    end
)

bus:reset()  -- clear before next round
```

## Caveats {#caveats}

**Module structure**: `civic/init.lua` (this file) owns `M.meta` and the
aggregate `M.shape` table. Each `civic/<name>.lua` is a component module
with no `M.meta` and no `M.shape`. components expose only their own API.

**Shape descriptors**: `M.shape.broadcast_entry` documents the entry shape
used internally by `broadcast_bus`. Callers may reference it for documentation
or tooling; the bus itself does not enforce it at runtime (payload is opaque).

**Planned components**: Phase 1 provides `broadcast_bus`. Phase 2/3 will add
`slot_table`, `scalar_pool`, `ledger`, `lineage`, `knowledge_channel`,
`transition_rules`.

**Phase 1 scope**: only `broadcast_bus` is wired. Accessing unimplemented
components via `civic.<name>` will raise a require error until Phase 2/3
adds the remaining modules.

**No LLM dependency**: all civic-frame components in Phase 1 are pure
in-memory data-structure primitives. `alc.llm` is never called. civic may
be used freely in synchronous, non-LLM orchestration and simulation code.

**Component independence**: each Component can also be required directly
(`require("civic.broadcast_bus")`) for callers that want to import only
a subset. The canonical path for most callers is `require("civic")`.

**Feature detection**: unimplemented Phase 2/3 components can be probed
with `pcall(require, "civic.<name>")` without raising.
