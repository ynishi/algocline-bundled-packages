--- abm(ABM) — agent-based modeling framework with Monte Carlo and sensitivity sweep
---
--- Two-layer toolkit for structural simulation. The Frame layer defines and
--- runs simulations through `Agent`, `Model`, and `Scheduler` primitives; the
--- Analysis layer aggregates and analyzes results through `mc`, `sweep`, and
--- `stats` modules.
---
--- ## Usage
---
--- ```lua
--- local abm = require("abm")
---
--- local buyer = abm.Agent.define {
---     state = { budget = 100, tag = "buyer" },
---     step = function(self, model)
---         -- decision logic
---     end,
--- }
---
--- local m = abm.Model.new({ scheduler = abm.Scheduler.shuffle })
--- abm.Model.add_agents(m, abm.Agent.populate(buyer, 50))
--- abm.Model.run(m, 24)
---
--- local result = abm.mc.run({
---     sim_fn = function(seed) ... end,
---     runs = 200,
---     extract = { "survived", "users" },
--- })
---
--- local sens = abm.sweep.run({
---     base_params = params,
---     param_names = { "price", "quality" },
---     eval_fn = function(p) return score(p) end,
--- })
--- ```
---
--- ## Architecture
---
--- - Frame layer: `Agent` / `Model` / `Scheduler` — define and run simulations.
--- - Analysis layer: `mc` / `sweep` / `stats` — aggregate and analyze results.

local M = {}

---@type AlcMeta
M.meta = {
    name = "abm",
    version = "0.1.0-beta",
    description = "Agent-based modeling framework with Monte Carlo and sensitivity sweep.",
    category = "simulation",
}

-- Frame layer
M.Agent     = require("abm.frame.agent")
M.Model     = require("abm.frame.model")
M.Scheduler = require("abm.frame.scheduler")

-- Analysis layer
M.mc    = require("abm.mc")
M.sweep = require("abm.sweep")
M.stats = require("abm.stats")

return M
