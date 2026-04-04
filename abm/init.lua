--- abm — Agent-Based Model framework for algocline
---
--- Two-layer architecture:
---   Frame layer: Agent/Model/Scheduler — define and run simulations
---   Analysis layer: MC/Sweep/Stats — aggregate and analyze results
---
--- Usage:
---   local abm = require("abm")
---
---   -- Define agents
---   local buyer = abm.Agent.define {
---       state = { budget = 100, tag = "buyer" },
---       step = function(self, model)
---           -- decision logic
---       end,
---   }
---
---   -- Create and run model
---   local m = abm.Model.new({ scheduler = abm.Scheduler.shuffle })
---   abm.Model.add_agents(m, abm.Agent.populate(buyer, 50))
---   abm.Model.run(m, 24)
---
---   -- Monte Carlo
---   local result = abm.mc.run({
---       sim_fn = function(seed) ... end,
---       runs = 200,
---       extract = { "survived", "users" },
---   })
---
---   -- Sensitivity sweep
---   local sens = abm.sweep.run({
---       base_params = params,
---       param_names = { "price", "quality" },
---       eval_fn = function(p) return score(p) end,
---   })

local M = {}

---@type AlcMeta
M.meta = {
    name = "abm",
    version = "0.1.0-beta",
    description = "Agent-Based Model framework — Agent/Model/Scheduler "
        .. "+ Monte Carlo runner + sensitivity sweep. "
        .. "LLM-amplified simulation for structural reasoning.",
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
