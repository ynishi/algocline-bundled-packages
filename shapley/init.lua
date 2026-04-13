--- shapley — Shapley Value computation for agent contribution attribution
---
--- Pure-computation utility for attributing individual agent contributions
--- within a coalition (ensemble/swarm). Implements both exact computation
--- and Monte Carlo permutation sampling approximation.
---
--- The Shapley value is the UNIQUE allocation satisfying four axioms:
---   1. Efficiency:  SUM phi_i = v(N) - v({})
---   2. Symmetry:    i,j interchangeable => phi_i = phi_j
---   3. Dummy:       i contributes nothing => phi_i = 0
---   4. Additivity:  phi_i(v+w) = phi_i(v) + phi_i(w)
---
--- Central formula (Shapley 1953):
---   phi_i(v) = SUM_{S ⊆ N\{i}} [|S|! (n-|S|-1)! / n!] * [v(S∪{i}) - v(S)]
---
--- Monte Carlo approximation (Ghorbani & Zou, AISTATS 2019 "Data Shapley"):
---   Sample random permutations π, compute marginal contribution of i
---   as v(predecessors_of_i ∪ {i}) - v(predecessors_of_i).
---   Convergence: O(1/√M) by CLT.
---
--- Based on:
---   Shapley, L. S. "A Value for n-Person Games". Contributions to the
---   Theory of Games II, Annals of Mathematics Studies 28, pp.307-317, 1953.
---
---   Ghorbani, A., Zou, J. "Data Shapley: Equitable Valuation of Data for
---   Machine Learning". AISTATS 2019. arXiv:1904.02868.
---
--- Usage:
---   local shapley = require("shapley")
---
---   -- Exact computation (n <= 12)
---   local r = shapley.exact({"a","b","c"}, v_fn)
---
---   -- Monte Carlo approximation
---   local r = shapley.montecarlo({"a","b","c"}, v_fn, {samples=1000})
---
---   -- Helper: build v_fn from agent outputs + ground truth
---   local v_fn = shapley.accuracy_coalition(outputs, truth)

local M = {}

---@type AlcMeta
M.meta = {
    name = "shapley",
    version = "0.1.0",
    description = "Shapley Value — axiomatic contribution attribution via "
        .. "exact computation or Monte Carlo permutation sampling "
        .. "(Shapley 1953, Ghorbani-Zou AISTATS 2019)",
    category = "foundation",
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
    local s = seed
    return function()
        s = (s * 1103515245 + 12345) % 2147483648
        return s / 2147483648
    end
end

--- Fisher-Yates shuffle (in-place).
local function shuffle(arr, rng)
    for i = #arr, 2, -1 do
        local j = math.floor(rng() * i) + 1
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- ─── Internal: subset utilities ───

--- Build a subset table (set) from a bitmask and agent list.
--- Returns both the set (for v_fn) and the list (for ordering).
local function bitmask_to_set(mask, agents)
    local set = {}
    local list = {}
    for i = 1, #agents do
        if mask % 2 == 1 then
            set[agents[i]] = true
            list[#list + 1] = agents[i]
        end
        mask = math.floor(mask / 2)
    end
    return set, list
end

--- Compute factorial. Caches results.
local fact_cache = { [0] = 1, [1] = 1 }
local function factorial(n)
    if fact_cache[n] then return fact_cache[n] end
    local f = 1
    for i = 2, n do f = f * i end
    fact_cache[n] = f
    return f
end

-- ─── v_fn cache wrapper ───

--- Wraps v_fn with memoization keyed by sorted member list.
local function cached_v(v_fn)
    local cache = {}
    return function(subset_set, subset_list)
        -- Build canonical key from sorted list
        local sorted = {}
        for _, a in ipairs(subset_list) do sorted[#sorted + 1] = tostring(a) end
        table.sort(sorted)
        local key = table.concat(sorted, "\0")

        if cache[key] ~= nil then return cache[key] end
        local val = v_fn(subset_set, subset_list)
        if type(val) ~= "number" then
            error("shapley: v_fn must return a number, got " .. type(val))
        end
        cache[key] = val
        return val
    end
end

-- ─── Public API ───

--- Exact Shapley value computation.
--- Enumerates all 2^n subsets. Practical for n <= 12.
---
---@param agents table list of agent identifiers
---@param v_fn function v_fn(subset_set, subset_list) -> number
---@return table result { values, efficiency_check, v_N, v_empty, n, evaluations }
function M.exact(agents, v_fn)
    if type(agents) ~= "table" or #agents == 0 then
        error("shapley.exact: agents must be a non-empty list")
    end
    if type(v_fn) ~= "function" then
        error("shapley.exact: v_fn must be a function")
    end
    local n = #agents
    if n > 12 then
        error("shapley.exact: n=" .. n .. " too large for exact computation "
            .. "(2^" .. n .. " subsets). Use shapley.montecarlo instead")
    end

    local v = cached_v(v_fn)
    local evaluations = 0

    -- Precompute v for all subsets
    local v_cache = {}
    for mask = 0, 2^n - 1 do
        local set, list = bitmask_to_set(mask, agents)
        v_cache[mask] = v(set, list)
        evaluations = evaluations + 1
    end

    -- Compute Shapley values
    local n_fact = factorial(n)
    local values = {}

    for idx = 1, n do
        local agent_i = agents[idx]
        local bit_i = 2^(idx - 1)
        local phi = 0

        -- Iterate over all subsets S ⊆ N\{i}
        -- These are all masks where bit idx is 0
        for mask = 0, 2^n - 1 do
            if mask % (2 * bit_i) < bit_i then  -- bit idx is 0
                local s_size = 0
                local m = mask
                while m > 0 do
                    s_size = s_size + m % 2
                    m = math.floor(m / 2)
                end

                local weight = factorial(s_size) * factorial(n - s_size - 1) / n_fact
                local marginal = v_cache[mask + bit_i] - v_cache[mask]
                phi = phi + weight * marginal
            end
        end

        values[agent_i] = phi
    end

    -- Compute v(N) and v(empty)
    local v_N = v_cache[2^n - 1]
    local v_empty = v_cache[0]

    -- Efficiency check: sum(phi_i) ≈ v(N) - v({})
    local phi_sum = 0
    for _, phi in pairs(values) do phi_sum = phi_sum + phi end
    local efficiency_error = math.abs(phi_sum - (v_N - v_empty))
    local efficiency_check = efficiency_error < 1e-9

    return {
        values = values,
        efficiency_check = efficiency_check,
        efficiency_error = efficiency_error,
        v_N = v_N,
        v_empty = v_empty,
        n = n,
        evaluations = evaluations,
    }
end

--- Monte Carlo Shapley value via permutation sampling.
---
---@param agents table list of agent identifiers
---@param v_fn function v_fn(subset_set, subset_list) -> number
---@param opts table|nil { samples=1000, seed=42 }
---@return table result { values, std, ci95, samples, efficiency_check, v_N, v_empty, n }
function M.montecarlo(agents, v_fn, opts)
    if type(agents) ~= "table" or #agents == 0 then
        error("shapley.montecarlo: agents must be a non-empty list")
    end
    if type(v_fn) ~= "function" then
        error("shapley.montecarlo: v_fn must be a function")
    end
    opts = opts or {}
    local n = #agents
    local M_samples = opts.samples or 1000
    local rng = make_rng(opts.seed or 42)
    local v = cached_v(v_fn)

    -- Accumulators: sum and sum-of-squares for each agent
    local sum = {}
    local sum_sq = {}
    for _, a in ipairs(agents) do
        sum[a] = 0
        sum_sq[a] = 0
    end

    -- Agent index lookup
    local agent_idx = {}
    for i, a in ipairs(agents) do agent_idx[a] = i end

    -- Permutation sampling
    local perm = {}
    for i = 1, n do perm[i] = i end

    for _ = 1, M_samples do
        -- Generate random permutation
        shuffle(perm, rng)

        -- Walk through permutation, compute marginal contributions
        local pred_set = {}
        local pred_list = {}

        local v_prev = v(pred_set, pred_list)

        for pos = 1, n do
            local agent_i = agents[perm[pos]]
            pred_set[agent_i] = true
            pred_list[#pred_list + 1] = agent_i

            local v_curr = v(pred_set, pred_list)
            local marginal = v_curr - v_prev

            sum[agent_i] = sum[agent_i] + marginal
            sum_sq[agent_i] = sum_sq[agent_i] + marginal * marginal

            v_prev = v_curr
        end
    end

    -- Compute means, std, CI
    local values = {}
    local std = {}
    local ci95 = {}

    for _, a in ipairs(agents) do
        local mean = sum[a] / M_samples
        values[a] = mean

        local variance = sum_sq[a] / M_samples - mean * mean
        if variance < 0 then variance = 0 end  -- numerical safety
        local s = math.sqrt(variance)
        std[a] = s

        local ci_half = 1.96 * s / math.sqrt(M_samples)
        ci95[a] = { mean - ci_half, mean + ci_half }
    end

    -- Compute v(N) and v(empty) for efficiency check
    local all_set = {}
    local all_list = {}
    for _, a in ipairs(agents) do
        all_set[a] = true
        all_list[#all_list + 1] = a
    end
    local v_N = v(all_set, all_list)
    local v_empty = v({}, {})

    local phi_sum = 0
    for _, phi in pairs(values) do phi_sum = phi_sum + phi end
    local efficiency_error = math.abs(phi_sum - (v_N - v_empty))
    local efficiency_check = efficiency_error < 1e-6  -- looser tolerance for MC

    return {
        values = values,
        std = std,
        ci95 = ci95,
        samples = M_samples,
        efficiency_check = efficiency_check,
        efficiency_error = efficiency_error,
        v_N = v_N,
        v_empty = v_empty,
        n = n,
    }
end

--- Build a characteristic function from agent binary outputs and ground truth.
--- v(S) = majority vote accuracy of agents in S over all cases.
---
--- Each agent_outputs[i] is a list of binary predictions (0/1) for each case.
--- ground_truth is a list of correct answers (0/1).
---
---@param agent_outputs table { agent_id = {0,1,1,0,...}, ... } or indexed {{0,1,...},{1,0,...},...}
---@param ground_truth table {1,1,0,1,...}
---@param agents table|nil ordered agent list (required if agent_outputs is a map)
---@return function v_fn(subset_set, subset_list) -> number
---@return table agents ordered agent list
function M.accuracy_coalition(agent_outputs, ground_truth, agents)
    if type(agent_outputs) ~= "table" then
        error("shapley.accuracy_coalition: agent_outputs must be a table")
    end
    if type(ground_truth) ~= "table" or #ground_truth == 0 then
        error("shapley.accuracy_coalition: ground_truth must be a non-empty list")
    end

    -- Normalize agent_outputs to { agent_id = {predictions}, ... }
    local outputs = {}
    if not agents then
        -- Indexed array: agents are 1, 2, 3, ...
        agents = {}
        for i, preds in ipairs(agent_outputs) do
            agents[i] = i
            outputs[i] = preds
        end
    else
        for _, a in ipairs(agents) do
            if not agent_outputs[a] then
                error("shapley.accuracy_coalition: no outputs for agent " .. tostring(a))
            end
            outputs[a] = agent_outputs[a]
        end
    end

    local n_cases = #ground_truth
    for _, a in ipairs(agents) do
        if #outputs[a] ~= n_cases then
            error("shapley.accuracy_coalition: agent " .. tostring(a)
                .. " has " .. #outputs[a] .. " predictions, expected " .. n_cases)
        end
    end

    local v_fn = function(subset_set, _subset_list)
        -- Empty coalition: accuracy = 0
        local members = {}
        for _, a in ipairs(agents) do
            if subset_set[a] then members[#members + 1] = a end
        end
        if #members == 0 then return 0 end

        -- Majority vote for each case
        local correct = 0
        for c = 1, n_cases do
            local votes_1 = 0
            local votes_0 = 0
            for _, a in ipairs(members) do
                if outputs[a][c] == 1 then
                    votes_1 = votes_1 + 1
                else
                    votes_0 = votes_0 + 1
                end
            end
            local majority = votes_1 > votes_0 and 1 or 0
            -- Tie-break: 0 (conservative)
            if votes_1 == votes_0 then majority = 0 end
            if majority == ground_truth[c] then
                correct = correct + 1
            end
        end

        return correct / n_cases
    end

    return v_fn, agents
end

return M
