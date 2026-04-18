--- sugarscape_abm — Sugarscape Agent-Based Model
---
--- Agents on a 2D toroidal grid forage for sugar. Each cell has a sugar
--- capacity and regrows at a fixed rate. Agents have metabolism (sugar
--- consumed per step) and vision (how far they can see). Each step,
--- an agent looks in four cardinal directions up to its vision range
--- and moves to the nearest unoccupied cell with the most sugar.
--- Agents die when sugar wealth reaches zero.
---
--- Emergent phenomena: wealth inequality (Gini coefficient),
--- skewed wealth distributions (Pareto-like), carrying capacity,
--- spatial clustering near sugar peaks.
---
--- Based on:
---   Epstein & Axtell, "Growing Artificial Societies: Social Science
---   from the Bottom Up", MIT Press, 1996
---
--- Usage:
---   local sugarscape = require("sugarscape_abm")
---   return sugarscape.run(ctx)
---
--- ctx.task?: string Description
--- ctx.grid_size?: number Side length of square grid (default 25)
--- ctx.n_agents?: number Initial population (default 100)
--- ctx.max_sugar?: number Peak sugar capacity per cell (default 4)
--- ctx.regrow_rate?: number Sugar regrowth per step (default 1)
--- ctx.metabolism_range?: {number, number} Min/max metabolism (default {1, 4})
--- ctx.vision_range?: {number, number} Min/max vision (default {1, 6})
--- ctx.initial_wealth_range?: {number, number} (default {5, 25})
--- ctx.steps?: number (default 100)
--- ctx.runs?: number MC runs (default 100)

local abm = require("abm")
local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "sugarscape_abm",
    version = "0.1.0",
    description = "Sugarscape model — agents forage on a sugar landscape, "
        .. "emergent wealth inequality, Pareto-like distributions, "
        .. "and carrying capacity. Based on Epstein & Axtell (1996).",
    category = "simulation",
}

---@type AlcSpec
-- Phase 6-a-fix: result is shaped precisely via abm.mc.shape /
-- abm.sweep.shape helpers. metabolism_range / vision_range /
-- initial_wealth_range are {lo, hi} number pairs — declared as
-- T.array_of(T.number) (length-2 invariant is enforced at runtime
-- by the rand_int lookups in run_single, not at the shape layer).
local params_shape = T.shape({
    grid_size            = T.number:describe("Square-grid side length (default 25)"),
    n_agents             = T.number:describe("Initial population (default 100)"),
    max_sugar            = T.number:describe("Peak sugar capacity per cell (default 4)"),
    regrow_rate          = T.number:describe("Sugar regrowth per step (default 1)"),
    metabolism_range     = T.array_of(T.number):describe("[min, max] metabolism (default {1, 4})"),
    vision_range         = T.array_of(T.number):describe("[min, max] vision (default {1, 6})"),
    initial_wealth_range = T.array_of(T.number):describe("[min, max] initial wealth (default {5, 25})"),
    steps                = T.number:describe("Simulation steps (default 100)"),
})

M.spec = {
    entries = {
        run = {
            input = T.shape({
                task                 = T.string:is_optional():describe("Task description (free text)"),
                grid_size            = T.number:is_optional():describe("Square-grid side length (default 25)"),
                n_agents             = T.number:is_optional():describe("Initial population (default 100)"),
                max_sugar            = T.number:is_optional():describe("Peak sugar capacity per cell (default 4)"),
                regrow_rate          = T.number:is_optional():describe("Sugar regrowth per step (default 1)"),
                metabolism_range     = T.array_of(T.number):is_optional():describe("[min, max] metabolism (default {1, 4})"),
                vision_range         = T.array_of(T.number):is_optional():describe("[min, max] vision (default {1, 6})"),
                initial_wealth_range = T.array_of(T.number):is_optional():describe("[min, max] initial wealth (default {5, 25})"),
                steps                = T.number:is_optional():describe("Simulation steps (default 100)"),
                runs                 = T.number:is_optional():describe("Monte Carlo runs (default 100)"),
            }),
            result = T.shape({
                params      = params_shape,
                simulation  = abm.mc.shape({
                    numbers  = { "survival_rate", "gini", "mean_wealth" },
                    booleans = { "high_inequality", "population_collapsed" },
                }),
                sensitivity = abm.sweep.shape(),
            }),
        },
    },
}

---------------------------------------------------------------------------
-- Grid: sugar landscape
---------------------------------------------------------------------------

--- Create a sugar landscape with two Gaussian-like peaks.
--- @return number[][] capacity, number[][] current sugar
local function create_landscape(size, max_sugar, rng)
    local capacity = {}
    local sugar = {}

    -- Two sugar peaks at roughly (size/4, size/4) and (3*size/4, 3*size/4)
    local p1r, p1c = math.floor(size / 4), math.floor(size / 4)
    local p2r, p2c = math.floor(3 * size / 4), math.floor(3 * size / 4)
    local radius = size / 3

    for r = 1, size do
        capacity[r] = {}
        sugar[r] = {}
        for c = 1, size do
            local d1 = math.sqrt((r - p1r) ^ 2 + (c - p1c) ^ 2)
            local d2 = math.sqrt((r - p2r) ^ 2 + (c - p2c) ^ 2)
            local d = math.min(d1, d2)
            local level = math.max(0, math.floor(max_sugar * (1 - d / radius) + 0.5))
            level = math.min(level, max_sugar)
            capacity[r][c] = level
            sugar[r][c] = level
        end
    end

    return capacity, sugar
end

---------------------------------------------------------------------------
-- Agent logic
---------------------------------------------------------------------------

--- Random integer in [lo, hi].
local function rand_int(rng, lo, hi)
    return math.floor(rng() * (hi - lo + 1)) + lo
end

--- Look in four cardinal directions up to vision range.
--- Returns the best unoccupied cell (most sugar, nearest).
local function find_best_cell(grid_sugar, occupied, size, row, col, vision)
    local best_sugar = -1
    local best_dist = vision + 1
    local best_r, best_c = row, col

    -- Four directions: up, down, left, right
    local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    for _, d in ipairs(dirs) do
        for dist = 1, vision do
            local nr = ((row - 1 + d[1] * dist) % size) + 1
            local nc = ((col - 1 + d[2] * dist) % size) + 1
            if not occupied[nr * size + nc] then
                local s = grid_sugar[nr][nc]
                if s > best_sugar or (s == best_sugar and dist < best_dist) then
                    best_sugar = s
                    best_dist = dist
                    best_r = nr
                    best_c = nc
                end
            end
        end
    end

    return best_r, best_c
end

--- Compute Gini coefficient from a list of values.
local function gini(values)
    local n = #values
    if n == 0 then return 0 end
    local sorted = {}
    for i, v in ipairs(values) do sorted[i] = v end
    table.sort(sorted)
    local sum_num = 0
    local sum_den = 0
    for i = 1, n do
        sum_num = sum_num + (2 * i - n - 1) * sorted[i]
        sum_den = sum_den + sorted[i]
    end
    if sum_den == 0 then return 0 end
    return sum_num / (n * sum_den)
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local function run_single(params, seed)
    local rng_state = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(rng_state) end

    local size = params.grid_size or 25
    local n_agents = params.n_agents or 100
    local max_sugar = params.max_sugar or 4
    local regrow_rate = params.regrow_rate or 1
    local met_lo = (params.metabolism_range or { 1, 4 })[1]
    local met_hi = (params.metabolism_range or { 1, 4 })[2]
    local vis_lo = (params.vision_range or { 1, 6 })[1]
    local vis_hi = (params.vision_range or { 1, 6 })[2]
    local wealth_lo = (params.initial_wealth_range or { 5, 25 })[1]
    local wealth_hi = (params.initial_wealth_range or { 5, 25 })[2]
    local steps = params.steps or 100

    local capacity, grid_sugar = create_landscape(size, max_sugar, rng)

    -- Place agents on random unoccupied cells
    local agents = {}
    local occupied = {}  -- key: row*size+col → agent index

    for i = 1, n_agents do
        local r, c
        repeat
            r = rand_int(rng, 1, size)
            c = rand_int(rng, 1, size)
        until not occupied[r * size + c]

        agents[i] = {
            row = r, col = c,
            metabolism = rand_int(rng, met_lo, met_hi),
            vision = rand_int(rng, vis_lo, vis_hi),
            wealth = rand_int(rng, wealth_lo, wealth_hi),
            alive = true,
        }
        occupied[r * size + c] = i
    end

    local initial_pop = n_agents

    for _ = 1, steps do
        -- Shuffle activation order
        local order = {}
        for i = 1, #agents do
            if agents[i].alive then order[#order + 1] = i end
        end
        for i = #order, 2, -1 do
            local j = math.floor(rng() * i) + 1
            order[i], order[j] = order[j], order[i]
        end

        -- Each agent: move → harvest → metabolize
        for _, idx in ipairs(order) do
            local a = agents[idx]
            if not a.alive then goto next_agent end

            -- Move to best visible cell
            local nr, nc = find_best_cell(
                grid_sugar, occupied, size, a.row, a.col, a.vision
            )
            occupied[a.row * size + a.col] = nil
            a.row, a.col = nr, nc
            occupied[nr * size + nc] = idx

            -- Harvest sugar
            a.wealth = a.wealth + grid_sugar[nr][nc]
            grid_sugar[nr][nc] = 0

            -- Metabolize
            a.wealth = a.wealth - a.metabolism
            if a.wealth <= 0 then
                a.alive = false
                occupied[a.row * size + a.col] = nil
            end

            ::next_agent::
        end

        -- Regrow sugar
        for r = 1, size do
            for c = 1, size do
                grid_sugar[r][c] = math.min(
                    capacity[r][c],
                    grid_sugar[r][c] + regrow_rate
                )
            end
        end
    end

    -- Final statistics
    local alive_count = 0
    local wealths = {}
    for _, a in ipairs(agents) do
        if a.alive then
            alive_count = alive_count + 1
            wealths[#wealths + 1] = a.wealth
        end
    end

    local survival_rate = alive_count / initial_pop
    local gini_coeff = gini(wealths)

    local max_wealth = 0
    local mean_wealth = 0
    if #wealths > 0 then
        local sum = 0
        for _, w in ipairs(wealths) do
            sum = sum + w
            if w > max_wealth then max_wealth = w end
        end
        mean_wealth = sum / #wealths
    end

    return {
        survival_rate = survival_rate,
        alive_count = alive_count,
        gini = gini_coeff,
        mean_wealth = mean_wealth,
        max_wealth = max_wealth,
        high_inequality = gini_coeff > 0.4,
        population_collapsed = survival_rate < 0.3,
    }
end

---------------------------------------------------------------------------
-- M.run(ctx)
---------------------------------------------------------------------------

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    -- ctx.task is available for LLM prompt integration (e.g. via hybrid_abm)

    local params = {
        grid_size = ctx.grid_size or 25,
        n_agents = ctx.n_agents or 100,
        max_sugar = ctx.max_sugar or 4,
        regrow_rate = ctx.regrow_rate or 1,
        metabolism_range = ctx.metabolism_range or { 1, 4 },
        vision_range = ctx.vision_range or { 1, 6 },
        initial_wealth_range = ctx.initial_wealth_range or { 5, 25 },
        steps = ctx.steps or 100,
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = {
            "survival_rate", "gini", "mean_wealth",
            "high_inequality", "population_collapsed",
        },
    })

    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = { "regrow_rate", "n_agents", "max_sugar" },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "gini" },
            })
            return quick.gini_median or 0
        end,
    })

    ctx.result = {
        params = params,
        simulation = mc_result,
        sensitivity = sensitivity,
    }
    return ctx
end

M.run_single = run_single

-- Malli-style self-decoration. run_single stays uninstrumented
-- (hot-loop helper + hybrid_abm sim_fn callback).
M.run = S.instrument(M, "run")

return M
