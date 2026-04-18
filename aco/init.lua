--- aco — Ant Colony Optimization for discrete path search
---
--- Implements the Ant System (Dorigo 1996) with convergence guarantees
--- from Gutjahr 2000 (GBAS). Provides both a pure-computation engine
--- and an LLM-integrated run(ctx) for workflow/path optimization.
---
--- Based on:
---   Dorigo, Maniezzo, Colorni. "Ant system: optimization by a colony
---   of cooperating agents". IEEE TSMC-B 26(1), 29-41, 1996.
---
---   Gutjahr, W. J. "A Graph-based Ant System and its convergence".
---   Future Generation Computer Systems 16, 873-888, 2000.
---
--- Core equations:
---   Transition probability (Eq.1):
---     p_{xy}^k = [tau_{xy}^alpha * eta_{xy}^beta] /
---                SUM_z [tau_{xz}^alpha * eta_{xz}^beta]
---
---   Pheromone update (Eq.2):
---     tau_{xy}(t+1) = (1 - rho) * tau_{xy}(t) + SUM_k delta_tau_{xy}^k
---
---   Stützle-Dorigo 2002: pheromone bounds [tau_min, tau_max]
---   prevent premature convergence (MAX-MIN AS).
---
--- Usage (pure engine):
---   local aco = require("aco")
---   local colony = aco.new(graph, {rho = 0.1})
---   colony:iterate(eval_fn)
---   local best = colony:best()
---
--- Usage (LLM-integrated):
---   return aco.run(ctx)
---   -- ctx.task, ctx.nodes, ctx.budget

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "aco",
    version = "0.1.0",
    description = "Ant Colony Optimization — discrete path search with "
        .. "pheromone-based learning (Dorigo 1996, Gutjahr 2000 convergence)",
    category = "exploration",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task             = T.string:describe("The task to solve"),
                nodes            = T.array_of(T.string):is_optional()
                    :describe("Node labels for the graph; generated via decompose LLM when omitted"),
                budget           = T.number:is_optional():describe("Max iterations (default: 20)"),
                n_ants           = T.number:is_optional():describe("Ants per iteration (default: 5)"),
                rho              = T.number:is_optional():describe("Pheromone evaporation rate ρ ∈ (0,1) (default: 0.2)"),
                alpha            = T.number:is_optional():describe("Pheromone exponent α (default: 1.0)"),
                beta             = T.number:is_optional():describe("Heuristic exponent β (default: 2.0)"),
                stagnation       = T.number:is_optional():describe("Stagnation iteration threshold (default: 5)"),
                seed             = T.number:is_optional():describe("RNG seed (default: 42)"),
                answer_tokens    = T.number:is_optional():describe("Max tokens for final answer synthesis (default: 500)"),
                decompose_system = T.string:is_optional():describe("System prompt for the decompose LLM"),
                eval_system      = T.string:is_optional():describe("System prompt for the eval LLM"),
                exec_system      = T.string:is_optional():describe("System prompt for the exec LLM"),
                eval_fn          = T.any:is_optional()
                    :describe("Optional user-supplied scorer: function(path) -> score; when absent an LLM-based scorer is used"),
            }),
            result = T.shape({
                answer     = T.string:describe("Final answer synthesized from the best path"),
                best_path  = T.array_of(T.string)
                    :describe("Best step sequence (excludes start/end sentinel nodes)"),
                best_score = T.number:describe("Best path score"),
                iterations = T.number:describe("Iterations actually performed"),
                history = T.array_of(T.shape({
                    iteration  = T.number:describe("Iteration index"),
                    best_score = T.number:describe("Best score at this iteration"),
                    avg_score  = T.number:describe("Average score across ants in this iteration"),
                })):describe("Per-iteration convergence history"),
                n_nodes = T.number:describe("Total number of graph nodes"),
                n_ants  = T.number:describe("Ant count used"),
                rho     = T.number:describe("Evaporation rate used"),
            }),
        },
    },
}

-- ─── RNG helper ───

--- Create a deterministic RNG.
--- Uses alc.math.rng_create/rng_float when available (runtime),
--- falls back to a simple LCG for testing without alc global.
local function make_rng(seed)
    seed = seed or 42
    if _G.alc and alc.math and alc.math.rng_create then
        local state = alc.math.rng_create(seed)
        return function() return alc.math.rng_float(state) end
    end
    -- Fallback LCG for test environments without alc.math
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- ─── Colony class ───

local Colony = {}
Colony.__index = Colony

--- Create a new ACO colony.
---
--- graph: adjacency structure.
---   graph.nodes = list of node identifiers (e.g., {1,2,3,4})
---   graph.edges = table of edges: edges[from][to] = {eta = heuristic_value}
---                 If edges is nil, a fully-connected graph with eta=1 is assumed.
---   graph.start = start node (default: nodes[1])
---   graph.finish = end node (default: nodes[#nodes])
---
--- opts:
---   rho:     pheromone evaporation rate (default: 0.1, in (0,1))
---   alpha:   pheromone weight exponent (default: 1.0)
---   beta:    heuristic weight exponent (default: 2.0)
---   n_ants:  number of ants per iteration (default: 10)
---   tau_init: initial pheromone level (default: 1.0)
---   tau_min: minimum pheromone (MAX-MIN AS) (default: 0.01)
---   tau_max: maximum pheromone (default: 10.0)
---   seed:    RNG seed (default: 42)
---
function M.new(graph, opts)
    if type(graph) ~= "table" or not graph.nodes or #graph.nodes < 2 then
        error("aco.new: graph must have a .nodes list with >= 2 elements")
    end
    opts = opts or {}

    local self = setmetatable({}, Colony)
    self.nodes = graph.nodes
    self.start = graph.start or graph.nodes[1]
    self.finish = graph.finish or graph.nodes[#graph.nodes]
    self.rho = opts.rho or 0.1
    self.alpha = opts.alpha or 1.0
    self.beta = opts.beta or 2.0
    self.n_ants = opts.n_ants or 10
    self.tau_min = opts.tau_min or 0.01
    self.tau_max = opts.tau_max or 10.0
    self.rng = make_rng(opts.seed or 42)

    -- Validate rho
    if self.rho <= 0 or self.rho >= 1 then
        error("aco.new: rho must be in (0, 1), got " .. tostring(self.rho))
    end

    -- Build node index for fast lookup
    self.node_idx = {}
    for i, n in ipairs(self.nodes) do self.node_idx[n] = i end

    -- Initialize pheromone matrix
    local tau_init = opts.tau_init or 1.0
    self.tau = {}
    for _, from in ipairs(self.nodes) do
        self.tau[from] = {}
        for _, to in ipairs(self.nodes) do
            if from ~= to then
                self.tau[from][to] = tau_init
            end
        end
    end

    -- Build heuristic matrix (eta)
    self.eta = {}
    for _, from in ipairs(self.nodes) do
        self.eta[from] = {}
        for _, to in ipairs(self.nodes) do
            if from ~= to then
                local e = 1.0
                if graph.edges and graph.edges[from] and graph.edges[from][to] then
                    e = graph.edges[from][to].eta or 1.0
                end
                self.eta[from][to] = e
            end
        end
    end

    self.best_path = nil
    self.best_score = -math.huge
    self.iteration = 0
    self.history = {}

    return self
end

--- Construct a path for one ant using probabilistic transition rule (Eq.1).
function Colony:_construct_path()
    local path = { self.start }
    local visited = { [self.start] = true }
    local current = self.start

    while current ~= self.finish do
        -- Compute transition probabilities to unvisited neighbors
        local candidates = {}
        local total = 0
        for _, node in ipairs(self.nodes) do
            if not visited[node] and self.tau[current] and self.tau[current][node] then
                local tau_val = self.tau[current][node] ^ self.alpha
                local eta_val = (self.eta[current][node] or 1.0) ^ self.beta
                local desirability = tau_val * eta_val
                candidates[#candidates + 1] = { node = node, d = desirability }
                total = total + desirability
            end
        end

        if #candidates == 0 then break end  -- dead end

        -- Roulette wheel selection
        local r = self.rng() * total
        local cumsum = 0
        local chosen = candidates[1].node
        for _, c in ipairs(candidates) do
            cumsum = cumsum + c.d
            if cumsum >= r then
                chosen = c.node
                break
            end
        end

        path[#path + 1] = chosen
        visited[chosen] = true
        current = chosen
    end

    return path
end

--- Run one iteration: all ants construct paths, evaluate, update pheromone.
--- eval_fn(path) -> score (higher is better)
function Colony:iterate(eval_fn)
    if type(eval_fn) ~= "function" then
        error("aco:iterate: eval_fn must be a function(path) -> score")
    end

    self.iteration = self.iteration + 1
    local paths = {}
    local scores = {}

    -- Construct paths for all ants
    for k = 1, self.n_ants do
        paths[k] = self:_construct_path()
        scores[k] = eval_fn(paths[k])
    end

    -- Evaporate pheromone (Eq.2 part 1)
    for _, from in ipairs(self.nodes) do
        if self.tau[from] then
            for to, val in pairs(self.tau[from]) do
                self.tau[from][to] = (1 - self.rho) * val
            end
        end
    end

    -- Deposit pheromone (Eq.2 part 2)
    for k = 1, self.n_ants do
        if scores[k] > 0 then
            local deposit = scores[k]
            local path = paths[k]
            for i = 1, #path - 1 do
                local from, to = path[i], path[i + 1]
                if self.tau[from] and self.tau[from][to] then
                    self.tau[from][to] = self.tau[from][to] + deposit
                end
            end
        end
    end

    -- Clamp pheromone to [tau_min, tau_max] (MAX-MIN AS, Stützle-Dorigo 2002)
    for _, from in ipairs(self.nodes) do
        if self.tau[from] then
            for to, val in pairs(self.tau[from]) do
                self.tau[from][to] = math.max(self.tau_min, math.min(self.tau_max, val))
            end
        end
    end

    -- Update best
    for k = 1, self.n_ants do
        if scores[k] > self.best_score then
            self.best_score = scores[k]
            self.best_path = paths[k]
        end
    end

    self.history[#self.history + 1] = {
        iteration = self.iteration,
        best_score = self.best_score,
        avg_score = 0,
    }
    local sum = 0
    for _, s in ipairs(scores) do sum = sum + s end
    self.history[#self.history].avg_score = sum / #scores

    return self.best_path, self.best_score
end

--- Get the best path found so far.
function Colony:best()
    return self.best_path, self.best_score
end

--- Get the current pheromone matrix (for Stats S7 monitoring).
function Colony:pheromone()
    return self.tau
end

--- Get convergence history.
function Colony:get_history()
    return self.history
end

--- Run until convergence or budget exhaustion.
--- eval_fn(path) -> score
--- opts: { max_iter=100, stagnation=10 }
function Colony:run(eval_fn, opts)
    opts = opts or {}
    local max_iter = opts.max_iter or 100
    local stagnation_limit = opts.stagnation or 10

    local stagnation = 0
    local prev_best = self.best_score

    for _ = 1, max_iter do
        self:iterate(eval_fn)
        if self.best_score > prev_best then
            stagnation = 0
            prev_best = self.best_score
        else
            stagnation = stagnation + 1
        end
        if stagnation >= stagnation_limit then break end
    end

    return self.best_path, self.best_score
end

--- LLM-integrated run: generate node labels via LLM, then optimize paths.
---
--- ctx.task (required): problem description
--- ctx.nodes: list of node descriptions (default: LLM generates 4-6 steps)
--- ctx.budget: ACO iterations (default: 20)
--- ctx.n_ants: ants per iteration (default: 5)
--- ctx.rho: evaporation rate (default: 0.2)
--- ctx.alpha: pheromone weight exponent (default: 1.0)
--- ctx.beta: heuristic weight exponent (default: 2.0)
--- ctx.stagnation: iterations without improvement to stop (default: 5)
--- ctx.seed: RNG seed (default: 42)
--- ctx.answer_tokens: max tokens for final answer (default: 500)
--- ctx.decompose_system: system prompt for node generation phase
--- ctx.eval_system: system prompt for path evaluation phase
--- ctx.exec_system: system prompt for final answer phase
--- ctx.eval_fn: custom evaluation function(path) -> score (bypasses LLM eval)
---
---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("aco: ctx.task is required")
    local budget = ctx.budget or 20
    local n_ants = ctx.n_ants or 5
    local rho = ctx.rho or 0.2
    local stagnation = ctx.stagnation or 5
    local decompose_system = ctx.decompose_system or
        "You are a task decomposition expert. List steps clearly."
    local eval_system = ctx.eval_system or
        "You are an evaluator. Rate 1-10. Reply with only the number."
    local exec_system = ctx.exec_system or
        "You are an expert executor. Follow the optimized approach sequence."

    -- Generate or use provided nodes
    local node_labels
    if ctx.nodes then
        node_labels = ctx.nodes
    else
        local raw = alc.llm(
            string.format(
                "Task: %s\n\nBreak this task into 4-6 distinct steps or approaches. "
                .. "List each on a separate line, numbered 1-N. Be specific.",
                task
            ),
            { system = decompose_system,
              max_tokens = 300 }
        )
        node_labels = {}
        for line in raw:gmatch("[^\n]+") do
            local step = line:match("^%s*%d+[%.%)%:]%s*(.+)")
            if step and #step > 5 then
                node_labels[#node_labels + 1] = step
            end
        end
        if #node_labels < 2 then
            node_labels = { "Approach A", "Approach B", "Approach C" }
        end
    end

    -- Add start/end nodes
    local nodes = { "START" }
    for _, label in ipairs(node_labels) do
        nodes[#nodes + 1] = label
    end
    nodes[#nodes + 1] = "END"

    -- Build fully-connected graph
    local graph = {
        nodes = nodes,
        start = "START",
        finish = "END",
    }

    -- Create colony
    local colony = M.new(graph, {
        rho = rho,
        alpha = ctx.alpha or 1.0,
        beta = ctx.beta or 2.0,
        n_ants = n_ants,
        seed = ctx.seed or 42,
    })

    -- Evaluation function: custom or LLM-scored
    local eval_fn
    if ctx.eval_fn then
        eval_fn = ctx.eval_fn
    else
        local eval_cache = {}
        eval_fn = function(path)
            -- Skip START/END for description
            local steps = {}
            for i = 2, #path - 1 do
                steps[#steps + 1] = path[i]
            end
            local key = table.concat(steps, " -> ")
            if eval_cache[key] then return eval_cache[key] end

            local score_raw = alc.llm(
                string.format(
                    "Task: %s\n\nProposed approach sequence:\n%s\n\n"
                    .. "Rate this approach sequence on a scale of 1-10 for "
                    .. "effectiveness, coherence, and completeness. "
                    .. "Reply with ONLY the number.",
                    task, key
                ),
                { system = eval_system, max_tokens = 10 }
            )
            local score = tonumber(tostring(score_raw):match("(%d+%.?%d*)")) or 5
            score = math.max(1, math.min(10, score)) / 10  -- normalize to [0.1, 1.0]
            eval_cache[key] = score
            return score
        end
    end

    -- Run ACO
    colony:run(eval_fn, { max_iter = budget, stagnation = stagnation })

    -- Extract best path description
    local best_path, best_score = colony:best()
    local best_steps = {}
    if best_path then
        for i = 2, #best_path - 1 do
            best_steps[#best_steps + 1] = best_path[i]
        end
    end

    -- Generate final answer using best path
    local answer = alc.llm(
        string.format(
            "Task: %s\n\nOptimal approach sequence (found by ACO search):\n%s\n\n"
            .. "Execute this approach to solve the task. Provide a complete answer.",
            task, table.concat(best_steps, "\n-> ")
        ),
        { system = exec_system,
          max_tokens = ctx.answer_tokens or 500 }
    )

    ctx.result = {
        answer = answer,
        best_path = best_steps,
        best_score = best_score,
        iterations = colony.iteration,
        history = colony:get_history(),
        n_nodes = #node_labels,
        n_ants = n_ants,
        rho = rho,
    }
    return ctx
end

-- Malli-style self-decoration: wrapper asserts ctx against
-- M.spec.entries.run.input and ret.result against .result when
-- ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
