--- cost_pareto — Multi-objective Pareto dominance computation
---
--- Pure-computation utility for comparing candidates on multiple
--- objectives (accuracy, cost, diversity, latency, etc.) using
--- Pareto dominance and frontier extraction.
---
--- Theory:
---   Pareto optimality (Vilfredo Pareto, 1896): candidate A dominates
---   candidate B iff A is at least as good as B on ALL objectives and
---   strictly better on at least one. The Pareto frontier is the set
---   of all non-dominated candidates.
---
---   Applied to AI agents by:
---   Kapoor, Stroebl, Siegel, Nadgir, Narayanan (Princeton).
---   "AI Agents That Matter". arXiv:2407.01502, 2024.
---
---   Key finding: HumanEval warming baseline ($2.45 / 93.2%) Pareto-
---   dominates LATS ($134.50 / 88.0%) and Reflexion ($3.90 / 87.8%).
---
--- Multi-Agent / Swarm context:
---   Multi-agent strategies often improve accuracy at massive cost
---   increases. Pareto analysis prevents the trap of chasing marginal
---   accuracy gains with disproportionate resource expenditure.
---
---   - Strategy selection: frontier() extracts non-dominated agent
---     configurations from a candidate pool. Only Pareto-optimal
---     configurations should be considered for deployment.
---   - Baseline gate: is_dominated() checks if a complex multi-agent
---     strategy is Pareto-dominated by a simple baseline (e.g.,
---     single-agent + Self-Consistency). If dominated, the complex
---     strategy should be rejected regardless of absolute accuracy.
---   - Layered ranking: layers() assigns candidates to Pareto layers
---     (layer 0 = frontier, layer 1 = next frontier, etc.) for
---     progressive elimination in tournament-style agent selection.
---   - Connects to eval_guard (N5 baseline gate), inverse_u (more
---     agents at declining accuracy = dominated), and mwu (weight
---     allocation should favor Pareto-optimal agents).
---
--- Convention: ALL objectives are "higher is better". For cost,
--- pass the negative or inverse (e.g., -cost or 1/cost).
---
--- Usage:
---   local cp = require("cost_pareto")
---   local a = {accuracy = 0.93, neg_cost = -2.45}
---   local b = {accuracy = 0.88, neg_cost = -134.50}
---   cp.dominates(a, b) -- => true (a dominates b)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "cost_pareto",
    version = "0.1.0",
    description = "Multi-objective Pareto dominance — frontier extraction, "
        .. "dominance testing, and layered ranking for agent strategy "
        .. "selection on accuracy/cost/diversity trade-offs "
        .. "(Kapoor et al. 'AI Agents That Matter', 2024).",
    category = "selection",
}

---@type AlcSpec
local CAND_A = "Candidate A (objective_name -> numeric value)"
local CAND_B = "Candidate B (objective_name -> numeric value)"
local KEYS   = "Objective keys to compare (default: all numeric keys)"
M.spec = {
    entries = {
        dominates = {
            args   = {
                T.table:describe(CAND_A),
                T.table:describe(CAND_B),
                T.array_of(T.string):is_optional():describe(KEYS),
            },
            result = T.boolean:describe("True iff A Pareto-dominates B"),
        },
        frontier = {
            args   = {
                T.array_of(T.table):describe("Candidate pool"),
                T.array_of(T.string):is_optional():describe(KEYS),
            },
            result = T.array_of(T.table):describe("Non-dominated (Pareto-optimal) subset"),
        },
        is_dominated = {
            args   = {
                T.table:describe(CAND_A),
                T.table:describe(CAND_B),
                T.array_of(T.string):is_optional():describe(KEYS),
            },
            result = T.boolean:describe("True iff A is dominated by B"),
        },
        layers = {
            args   = {
                T.array_of(T.table):describe("Candidate pool"),
                T.array_of(T.string):is_optional():describe(KEYS),
            },
            result = T.array_of(T.array_of(T.table)):describe(
                "Successive Pareto frontiers (layer 1 = topmost)"),
        },
    },
}

--- Extract numeric values from a candidate table.
--- Returns a sorted list of (key, value) pairs for deterministic comparison.
local function extract_objectives(candidate, keys)
    local vals = {}
    for _, k in ipairs(keys) do
        local v = candidate[k]
        if type(v) ~= "number" then
            error("cost_pareto: objective '" .. k .. "' must be a number, got " .. tostring(v))
        end
        vals[#vals + 1] = v
    end
    return vals
end

--- Get sorted objective keys from a candidate.
local function get_keys(candidate)
    local keys = {}
    for k, v in pairs(candidate) do
        if type(v) == "number" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    return keys
end

--- Check if candidate A Pareto-dominates candidate B.
--- A dominates B iff: for all objectives, A >= B, AND
--- for at least one objective, A > B.
---
--- All objectives are "higher is better". For cost, pass negative values.
---
---@param a table candidate A with numeric objective fields
---@param b table candidate B with numeric objective fields
---@param keys table|nil explicit list of objective keys (default: all numeric keys)
---@return boolean dominates true if A dominates B
function M.dominates(a, b, keys)
    if type(a) ~= "table" or type(b) ~= "table" then
        error("cost_pareto.dominates: candidates must be tables")
    end
    keys = keys or get_keys(a)
    if #keys == 0 then
        error("cost_pareto.dominates: no numeric objectives found")
    end
    local va = extract_objectives(a, keys)
    local vb = extract_objectives(b, keys)

    local all_ge = true
    local any_gt = false
    for i = 1, #keys do
        if va[i] < vb[i] then
            all_ge = false
            break
        end
        if va[i] > vb[i] then
            any_gt = true
        end
    end
    return all_ge and any_gt
end

--- Compute the Pareto frontier from a list of candidates.
--- Returns only non-dominated candidates.
---
---@param candidates table list of candidate tables
---@param keys table|nil explicit list of objective keys
---@return table frontier list of non-dominated candidates (with original indices)
function M.frontier(candidates, keys)
    if type(candidates) ~= "table" or #candidates == 0 then
        error("cost_pareto.frontier: need a non-empty list of candidates")
    end
    keys = keys or get_keys(candidates[1])
    if #keys == 0 then
        error("cost_pareto.frontier: no numeric objectives found")
    end

    local result = {}
    for i = 1, #candidates do
        local dominated = false
        for j = 1, #candidates do
            if i ~= j and M.dominates(candidates[j], candidates[i], keys) then
                dominated = true
                break
            end
        end
        if not dominated then
            local entry = {}
            for k, v in pairs(candidates[i]) do entry[k] = v end
            entry._index = i
            result[#result + 1] = entry
        end
    end
    return result
end

--- Check if a candidate is dominated by a baseline.
--- This is the N5 gate: if the simple baseline dominates your candidate,
--- the candidate should be rejected.
---
---@param candidate table the candidate to test
---@param baseline table the baseline (e.g., warming + SC)
---@param keys table|nil objective keys
---@return boolean is_dominated true if baseline dominates candidate
---@return string reason
function M.is_dominated(candidate, baseline, keys)
    keys = keys or get_keys(candidate)
    if M.dominates(baseline, candidate, keys) then
        return true, "baseline Pareto-dominates candidate on all objectives"
    end
    return false, "candidate is not dominated by baseline"
end

--- Rank candidates by Pareto layers.
--- Layer 0 = Pareto frontier, Layer 1 = frontier after removing layer 0, etc.
---
---@param candidates table list of candidate tables
---@param keys table|nil objective keys
---@return table layers list of layers, each a list of {candidate, _index, _layer}
function M.layers(candidates, keys)
    if type(candidates) ~= "table" or #candidates == 0 then
        error("cost_pareto.layers: need a non-empty list of candidates")
    end
    keys = keys or get_keys(candidates[1])

    -- Track which candidates are still active
    local active = {}
    for i = 1, #candidates do active[i] = true end

    local layers = {}
    local layer_idx = 0

    while true do
        -- Collect indices of active candidates
        local alive = {}
        for i = 1, #candidates do
            if active[i] then alive[#alive + 1] = i end
        end
        if #alive == 0 then break end

        -- Find non-dominated among active
        local layer = {}
        for _, i in ipairs(alive) do
            local dominated = false
            for _, j in ipairs(alive) do
                if i ~= j and M.dominates(candidates[j], candidates[i], keys) then
                    dominated = true
                    break
                end
            end
            if not dominated then
                local entry = {}
                for k, v in pairs(candidates[i]) do entry[k] = v end
                entry._index = i
                entry._layer = layer_idx
                layer[#layer + 1] = entry
                active[i] = false
            end
        end

        if #layer == 0 then break end  -- safety
        layers[#layers + 1] = layer
        layer_idx = layer_idx + 1
    end

    return layers
end

-- Malli-style self-decoration. is_dominated returns (bool, string) —
-- Option A' preserves the 2nd value.
M.dominates    = S.instrument(M, "dominates")
M.frontier     = S.instrument(M, "frontier")
M.is_dominated = S.instrument(M, "is_dominated")
M.layers       = S.instrument(M, "layers")

return M
