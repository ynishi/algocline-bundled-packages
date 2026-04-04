--- boids_abm — Boids Flocking Model
---
--- N agents (boids) in 2D continuous space follow three simple rules:
---   1. Separation: steer away from nearby boids to avoid crowding
---   2. Alignment: steer towards the average heading of nearby boids
---   3. Cohesion: steer towards the average position of nearby boids
---
--- Emergent phenomena: flocking, lane formation, obstacle avoidance,
--- predator evasion. The balance of three weights determines flock
--- structure (tight swarm, loose stream, scattered individuals).
---
--- Based on:
---   Reynolds, "Flocks, Herds, and Schools: A Distributed Behavioral
---   Model", SIGGRAPH 1987
---
--- Usage:
---   local boids = require("boids_abm")
---   return boids.run(ctx)
---
--- ctx.task?: string Description
--- ctx.n_boids?: number (default 50)
--- ctx.steps?: number (default 100)
--- ctx.separation_weight?: number (default 1.5)
--- ctx.alignment_weight?: number (default 1.0)
--- ctx.cohesion_weight?: number (default 1.0)
--- ctx.perception_radius?: number (default 50)
--- ctx.max_speed?: number (default 4)
--- ctx.max_force?: number Steering force limit (default 0.3)
--- ctx.world_size?: number Side length of square world (default 300)
--- ctx.runs?: number MC runs (default 100)

local abm = require("abm")

local M = {}

---@type AlcMeta
M.meta = {
    name = "boids_abm",
    version = "0.1.0",
    description = "Boids flocking model — separation, alignment, cohesion "
        .. "produce emergent flocking behavior. Tunable weights for "
        .. "Hybrid LLM parameter optimization. Based on Reynolds (1987).",
    category = "simulation",
}

---------------------------------------------------------------------------
-- Vector helpers (2D)
---------------------------------------------------------------------------

local function vec_add(a, b) return { a[1] + b[1], a[2] + b[2] } end
local function vec_sub(a, b) return { a[1] - b[1], a[2] - b[2] } end
local function vec_scale(v, s) return { v[1] * s, v[2] * s } end

local function vec_mag(v)
    return math.sqrt(v[1] * v[1] + v[2] * v[2])
end

local function vec_normalize(v)
    local m = vec_mag(v)
    if m < 1e-10 then return { 0, 0 } end
    return { v[1] / m, v[2] / m }
end

local function vec_limit(v, max_val)
    local m = vec_mag(v)
    if m > max_val then
        return vec_scale(vec_normalize(v), max_val)
    end
    return v
end

local function vec_dist(a, b)
    local dx = a[1] - b[1]
    local dy = a[2] - b[2]
    return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Boid steering behaviors
---------------------------------------------------------------------------

--- Separation: steer to avoid crowding local flockmates.
local function separation(boid, neighbors, sep_dist)
    local steer = { 0, 0 }
    local count = 0
    for _, other in ipairs(neighbors) do
        local d = vec_dist(boid.pos, other.pos)
        if d > 0 and d < sep_dist then
            local diff = vec_sub(boid.pos, other.pos)
            diff = vec_scale(vec_normalize(diff), 1 / math.max(d, 0.01))
            steer = vec_add(steer, diff)
            count = count + 1
        end
    end
    if count > 0 then
        steer = vec_scale(steer, 1 / count)
    end
    return steer
end

--- Alignment: steer towards the average heading of local flockmates.
local function alignment(boid, neighbors)
    local avg_vel = { 0, 0 }
    local count = 0
    for _, other in ipairs(neighbors) do
        avg_vel = vec_add(avg_vel, other.vel)
        count = count + 1
    end
    if count > 0 then
        avg_vel = vec_scale(avg_vel, 1 / count)
        return vec_sub(avg_vel, boid.vel)
    end
    return { 0, 0 }
end

--- Cohesion: steer to move toward the average position of local flockmates.
local function cohesion(boid, neighbors)
    local center = { 0, 0 }
    local count = 0
    for _, other in ipairs(neighbors) do
        center = vec_add(center, other.pos)
        count = count + 1
    end
    if count > 0 then
        center = vec_scale(center, 1 / count)
        return vec_sub(center, boid.pos)
    end
    return { 0, 0 }
end

---------------------------------------------------------------------------
-- Flock metrics
---------------------------------------------------------------------------

--- Average distance to nearest neighbor (measure of spacing).
local function avg_nearest_distance(boids)
    local total = 0
    for i, a in ipairs(boids) do
        local min_d = math.huge
        for j, b in ipairs(boids) do
            if i ~= j then
                local d = vec_dist(a.pos, b.pos)
                if d < min_d then min_d = d end
            end
        end
        if min_d < math.huge then total = total + min_d end
    end
    return #boids > 0 and total / #boids or 0
end

--- Alignment metric: average cosine similarity of velocity vectors.
local function flock_alignment(boids)
    if #boids < 2 then return 1.0 end
    local sum = 0
    local count = 0
    for i = 1, #boids do
        local mi = vec_mag(boids[i].vel)
        if mi < 1e-10 then goto next_i end
        for j = i + 1, #boids do
            local mj = vec_mag(boids[j].vel)
            if mj < 1e-10 then goto next_j end
            local dot = boids[i].vel[1] * boids[j].vel[1]
                      + boids[i].vel[2] * boids[j].vel[2]
            sum = sum + dot / (mi * mj)
            count = count + 1
            ::next_j::
        end
        ::next_i::
    end
    return count > 0 and sum / count or 0
end

--- Number of distinct clusters (connected components within radius).
local function count_clusters(boids, radius)
    local n = #boids
    if n == 0 then return 0 end
    local visited = {}
    local clusters = 0

    for i = 1, n do
        if not visited[i] then
            clusters = clusters + 1
            -- BFS
            local queue = { i }
            visited[i] = true
            local head = 1
            while head <= #queue do
                local cur = queue[head]
                head = head + 1
                for j = 1, n do
                    if not visited[j] and vec_dist(boids[cur].pos, boids[j].pos) < radius then
                        visited[j] = true
                        queue[#queue + 1] = j
                    end
                end
            end
        end
    end

    return clusters
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------

local function run_single(params, seed)
    local rng_state = alc.math.rng_create(seed)
    local rng = function() return alc.math.rng_float(rng_state) end

    local n = params.n_boids or 50
    local steps = params.steps or 100
    local w_sep = params.separation_weight or 1.5
    local w_ali = params.alignment_weight or 1.0
    local w_coh = params.cohesion_weight or 1.0
    local radius = params.perception_radius or 50
    local max_speed = params.max_speed or 4
    local max_force = params.max_force or 0.3
    local world = params.world_size or 300

    -- Initialize boids at random positions with random velocities
    local boids = {}
    for i = 1, n do
        local angle = rng() * 2 * math.pi
        local speed = rng() * max_speed * 0.5 + max_speed * 0.25
        boids[i] = {
            pos = { rng() * world, rng() * world },
            vel = { math.cos(angle) * speed, math.sin(angle) * speed },
        }
    end

    for _ = 1, steps do
        -- Compute forces for all boids
        local forces = {}
        for i = 1, n do
            -- Find neighbors within perception radius
            local neighbors = {}
            for j = 1, n do
                if i ~= j and vec_dist(boids[i].pos, boids[j].pos) < radius then
                    neighbors[#neighbors + 1] = boids[j]
                end
            end

            local sep = vec_scale(separation(boids[i], neighbors, radius * 0.5), w_sep)
            local ali = vec_scale(alignment(boids[i], neighbors), w_ali)
            local coh = vec_scale(cohesion(boids[i], neighbors), w_coh)

            local accel = vec_add(vec_add(sep, ali), coh)
            forces[i] = vec_limit(accel, max_force)
        end

        -- Update positions and velocities
        for i = 1, n do
            boids[i].vel = vec_limit(vec_add(boids[i].vel, forces[i]), max_speed)
            boids[i].pos = vec_add(boids[i].pos, boids[i].vel)

            -- Toroidal wrap
            boids[i].pos[1] = boids[i].pos[1] % world
            boids[i].pos[2] = boids[i].pos[2] % world
        end
    end

    -- Metrics
    local avg_nn_dist = avg_nearest_distance(boids)
    local align_score = flock_alignment(boids)
    local clusters = count_clusters(boids, radius)

    return {
        avg_nearest_distance = avg_nn_dist,
        alignment_score = align_score,
        clusters = clusters,
        cohesive_flock = clusters <= 3 and align_score > 0.5,
        scattered = clusters > n * 0.3,
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
        n_boids = ctx.n_boids or 50,
        steps = ctx.steps or 100,
        separation_weight = ctx.separation_weight or 1.5,
        alignment_weight = ctx.alignment_weight or 1.0,
        cohesion_weight = ctx.cohesion_weight or 1.0,
        perception_radius = ctx.perception_radius or 50,
        max_speed = ctx.max_speed or 4,
        max_force = ctx.max_force or 0.3,
        world_size = ctx.world_size or 300,
    }

    local mc_result = abm.mc.run({
        sim_fn = function(seed) return run_single(params, seed) end,
        runs = ctx.runs or 100,
        extract = {
            "avg_nearest_distance", "alignment_score",
            "clusters", "cohesive_flock", "scattered",
        },
    })

    local sensitivity = abm.sweep.run({
        base_params = params,
        param_names = {
            "separation_weight", "alignment_weight", "cohesion_weight",
            "perception_radius",
        },
        eval_fn = function(p)
            local quick = abm.mc.run({
                sim_fn = function(seed) return run_single(p, seed) end,
                runs = 30,
                extract = { "cohesive_flock" },
            })
            return quick.cohesive_flock_rate or 0
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

return M
