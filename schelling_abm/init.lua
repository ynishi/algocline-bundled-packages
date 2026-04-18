--- schelling_abm — Schelling Segregation Model
---
--- Agents of two types on a 2D grid. Each agent has a tolerance
--- threshold: if the fraction of same-type neighbors is below threshold,
--- the agent moves to a random empty cell.
---
--- Emergent phenomena: even mild preferences (threshold ~0.3) produce
--- strong macro-level segregation. Demonstrates how micro-motives
--- produce macro-behavior that no individual intended.
---
--- Based on:
---   Schelling, "Dynamic Models of Segregation",
---   Journal of Mathematical Sociology 1(2), 1971
---
---   Schelling, "Micromotives and Macrobehavior", Norton, 1978
---
--- Usage:
---   local schelling = require("schelling_abm")
---   return schelling.run(ctx)
---
--- ctx.task (required): Description
--- ctx.grid_size?: number Side length of square grid (default 20)
--- ctx.threshold?: number Tolerance threshold (default 0.375)
--- ctx.density?: number Fraction of cells occupied (default 0.8)
--- ctx.type_ratio?: number Fraction of type A among agents (default 0.5)
--- ctx.steps?: number Max steps (default 100)
--- ctx.runs?: number MC runs (default 100)

local abm = require("abm")
local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "schelling_abm",
    version = "0.1.0",
    description = "Schelling Segregation model — agents on a 2D grid relocate "
        .. "when local same-type fraction falls below tolerance threshold. "
        .. "Mild preferences produce strong emergent segregation.",
    category = "simulation",
}

---@type AlcSpec
-- Phase 6-a: ABM MC-sweep pattern. 2D grid is pkg-private; result
-- sub-tables stay opaque.
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:is_optional(),
                grid_size  = T.number:is_optional(),
                threshold  = T.number:is_optional(),
                density    = T.number:is_optional(),
                type_ratio = T.number:is_optional(),
                steps      = T.number:is_optional(),
                runs       = T.number:is_optional(),
            }),
            result = T.shape({
                params      = T.table,
                simulation  = T.table,
                sensitivity = T.table,
            }),
        },
    },
}

---------------------------------------------------------------------------
-- Grid operations
---------------------------------------------------------------------------

local EMPTY = 0
local TYPE_A = 1
local TYPE_B = 2

--- Create grid and return grid + list of empty cells.
local function create_grid(size, density, type_ratio, rng)
    local grid = {}
    local empty_cells = {}
    local n_total = size * size
    local n_occupied = math.floor(n_total * density)
    local n_a = math.floor(n_occupied * type_ratio)

    -- Fill flat array
    local cells = {}
    for i = 1, n_a do cells[i] = TYPE_A end
    for i = n_a + 1, n_occupied do cells[i] = TYPE_B end
    for i = n_occupied + 1, n_total do cells[i] = EMPTY end

    -- Fisher-Yates shuffle
    for i = #cells, 2, -1 do
        local j = math.floor(rng() * i) + 1
        cells[i], cells[j] = cells[j], cells[i]
    end

    -- Place on grid
    for row = 1, size do
        grid[row] = {}
        for col = 1, size do
            local idx = (row - 1) * size + col
            grid[row][col] = cells[idx]
            if cells[idx] == EMPTY then
                empty_cells[#empty_cells + 1] = { row, col }
            end
        end
    end

    return grid, empty_cells
end

--- Count same-type neighbors (Moore neighborhood, wrapping).
local function count_neighbors(grid, size, row, col, agent_type)
    local same = 0
    local total = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local nr = ((row - 1 + dr) % size) + 1
                local nc = ((col - 1 + dc) % size) + 1
                local neighbor = grid[nr][nc]
                if neighbor ~= EMPTY then
                    total = total + 1
                    if neighbor == agent_type then
                        same = same + 1
                    end
                end
            end
        end
    end
    if total == 0 then return 1.0 end  -- no neighbors = satisfied
    return same / total
end

--- Compute segregation index (average fraction of same-type neighbors).
local function segregation_index(grid, size)
    local sum = 0
    local count = 0
    for row = 1, size do
        for col = 1, size do
            local t = grid[row][col]
            if t ~= EMPTY then
                sum = sum + count_neighbors(grid, size, row, col, t)
                count = count + 1
            end
        end
    end
    if count == 0 then return 0 end
    return sum / count
end

--- Count unhappy agents.
local function count_unhappy(grid, size, threshold)
    local unhappy = 0
    for row = 1, size do
        for col = 1, size do
            local t = grid[row][col]
            if t ~= EMPTY then
                if count_neighbors(grid, size, row, col, t) < threshold then
                    unhappy = unhappy + 1
                end
            end
        end
    end
    return unhappy
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local function run_single(params, seed)
    local rng_state = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(rng_state) end

    local size = params.grid_size or 20
    local threshold = params.threshold or 0.375
    local density = params.density or 0.8
    local type_ratio = params.type_ratio or 0.5
    local max_steps = params.steps or 100

    local grid, empty_cells = create_grid(size, density, type_ratio, rng)

    local initial_segregation = segregation_index(grid, size)
    local converged = false
    local steps_to_converge = max_steps

    for step = 1, max_steps do
        local moved = 0

        -- Collect unhappy agents
        local unhappy_agents = {}
        for row = 1, size do
            for col = 1, size do
                local t = grid[row][col]
                if t ~= EMPTY then
                    if count_neighbors(grid, size, row, col, t) < threshold then
                        unhappy_agents[#unhappy_agents + 1] = { row, col }
                    end
                end
            end
        end

        if #unhappy_agents == 0 then
            converged = true
            steps_to_converge = step
            break
        end

        -- Shuffle unhappy agents
        for i = #unhappy_agents, 2, -1 do
            local j = math.floor(rng() * i) + 1
            unhappy_agents[i], unhappy_agents[j] = unhappy_agents[j], unhappy_agents[i]
        end

        -- Move each unhappy agent to a random empty cell
        for _, pos in ipairs(unhappy_agents) do
            if #empty_cells == 0 then break end

            -- Guard: skip if cell was already vacated by a prior move
            local agent_type = grid[pos[1]][pos[2]]
            if agent_type == EMPTY then goto continue end

            local pick = math.floor(rng() * #empty_cells) + 1
            local target = empty_cells[pick]

            grid[target[1]][target[2]] = agent_type
            grid[pos[1]][pos[2]] = EMPTY

            -- Replace used empty cell with the vacated position
            empty_cells[pick] = { pos[1], pos[2] }

            moved = moved + 1
            ::continue::
        end

        if moved == 0 then
            converged = true
            steps_to_converge = step
            break
        end
    end

    local final_segregation = segregation_index(grid, size)
    local final_unhappy = count_unhappy(grid, size, threshold)
    local n_occupied = math.floor(size * size * density)

    return {
        initial_segregation = initial_segregation,
        final_segregation = final_segregation,
        segregation_increase = final_segregation - initial_segregation,
        converged = converged,
        steps_to_converge = steps_to_converge,
        unhappy_fraction = final_unhappy / math.max(n_occupied, 1),
        high_segregation = final_segregation > 0.7,
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
        grid_size = ctx.grid_size or 20,
        threshold = ctx.threshold or 0.375,
        density = ctx.density or 0.8,
        type_ratio = ctx.type_ratio or 0.5,
        steps = ctx.steps or 100,
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = {
            "final_segregation", "segregation_increase",
            "converged", "steps_to_converge",
            "unhappy_fraction", "high_segregation",
        },
    })

    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = { "threshold", "density", "type_ratio" },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "final_segregation" },
            })
            return quick.final_segregation_median or 0
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
