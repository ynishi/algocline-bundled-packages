--- kemeny — Kemeny-Young optimal rank aggregation
---
--- Aggregates multiple rankings (total orders) into a single consensus
--- ranking that minimizes the total Kendall tau distance to all input
--- rankings. The Kemeny rule is the UNIQUE aggregation method satisfying
--- Condorcet consistency + neutrality + consistency (Young-Levenglick 1978).
---
--- Central formula:
---   σ* = argmin_{σ} Σ_{k=1}^{N} d_KT(σ, σ_k)
---
--- where d_KT is the Kendall tau distance (number of pairwise disagreements).
---
--- Computational complexity: NP-hard (Bartholdi, Tovey, Trick 1989).
---   - m ≤ 8 candidates: exact computation via full enumeration (m! ≤ 40320)
---   - m > 8: Borda count approximation (O(N·m), Kemeny 2-approximation)
---
--- Also provides:
---   - Borda count (de Borda 1781): independent rank aggregation method
---     with its own axiomatic characterization (Young 1974)
---   - Condorcet winner detection from pairwise majority matrix
---   - Kendall tau distance computation
---
--- Based on:
---   Kemeny, J. G. "Mathematics without Numbers". Daedalus 88(4),
---   pp.577-591, 1959.
---
---   Young, H. P., Levenglick, A. "A Consistent Extension of Condorcet's
---   Election Principle". SIAM J. Applied Mathematics 35(2), pp.285-300, 1978.
---
---   Bartholdi, J., Tovey, C., Trick, M. "Voting schemes for which it can
---   be difficult to tell who won the election". Social Choice and Welfare 6,
---   pp.157-165, 1989.
---
--- Usage:
---   local kemeny = require("kemeny")
---   local r = kemeny.aggregate(rankings)
---   -- r.ranking, r.total_distance, r.method

local M = {}

---@type AlcMeta
M.meta = {
    name = "kemeny",
    version = "0.1.0",
    description = "Kemeny-Young rank aggregation — distance-minimizing "
        .. "consensus ranking with axiomatic uniqueness "
        .. "(Kemeny 1959, Young-Levenglick 1978)",
    category = "foundation",
}

-- ─── Internal helpers ───

--- Build a position lookup table from a ranking.
--- ranking = { "A", "B", "C" } → { A=1, B=2, C=3 }
local function rank_positions(ranking)
    local pos = {}
    for i, item in ipairs(ranking) do
        pos[item] = i
    end
    return pos
end

--- Extract the set of all candidates from multiple rankings.
local function extract_candidates(rankings)
    local seen = {}
    local candidates = {}
    for _, r in ipairs(rankings) do
        for _, item in ipairs(r) do
            if not seen[item] then
                seen[item] = true
                candidates[#candidates + 1] = item
            end
        end
    end
    return candidates
end

--- Generate all permutations of a list (for exact computation).
--- Yields permutations via callback to avoid building full list in memory.
local function each_permutation(items, callback)
    local n = #items
    local perm = {}
    for i = 1, n do perm[i] = items[i] end

    -- Heap's algorithm (non-recursive)
    local c = {}
    for i = 1, n do c[i] = 1 end

    callback(perm)

    local i = 1
    while i <= n do
        if c[i] < i then
            if i % 2 == 1 then
                perm[1], perm[i] = perm[i], perm[1]
            else
                perm[c[i]], perm[i] = perm[i], perm[c[i]]
            end
            callback(perm)
            c[i] = c[i] + 1
            i = 1
        else
            c[i] = 1
            i = i + 1
        end
    end
end

-- ─── Public API ───

--- Compute Kendall tau distance between two rankings.
--- The number of pairwise disagreements (pairs in different order).
---
---@param r1 table first ranking (ordered list of candidates)
---@param r2 table second ranking (ordered list of candidates)
---@return number distance number of discordant pairs
function M.kendall_tau(r1, r2)
    if type(r1) ~= "table" or #r1 == 0 then
        error("kemeny.kendall_tau: r1 must be a non-empty list")
    end
    if type(r2) ~= "table" or #r2 == 0 then
        error("kemeny.kendall_tau: r2 must be a non-empty list")
    end

    local pos1 = rank_positions(r1)
    local pos2 = rank_positions(r2)

    -- Validate same candidate sets
    if #r1 ~= #r2 then
        error("kemeny.kendall_tau: rankings must have same length")
    end
    for _, item in ipairs(r1) do
        if not pos2[item] then
            error("kemeny.kendall_tau: candidate '" .. tostring(item)
                .. "' in r1 but not in r2")
        end
    end

    local m = #r1
    local dist = 0
    for i = 1, m do
        for j = i + 1, m do
            local a = r1[i]
            local b = r1[j]
            -- In r1: a is before b (pos1[a] < pos1[b])
            -- Check if they are reversed in r2
            if pos2[a] > pos2[b] then
                dist = dist + 1
            end
        end
    end
    return dist
end

--- Compute total Kendall tau distance from a candidate ranking to all input rankings.
local function total_distance(candidate, rankings)
    local total = 0
    for _, r in ipairs(rankings) do
        total = total + M.kendall_tau(candidate, r)
    end
    return total
end

--- Exact Kemeny aggregation: enumerate all m! permutations.
--- Practical for m ≤ 8 (40320 permutations).
---
---@param rankings table list of rankings (each is an ordered list of candidates)
---@return table result { ranking, total_distance, is_unique, ties, method }
function M.exact(rankings)
    if type(rankings) ~= "table" or #rankings == 0 then
        error("kemeny.exact: rankings must be a non-empty list")
    end

    local candidates = extract_candidates(rankings)
    local m = #candidates
    if m > 8 then
        error("kemeny.exact: m=" .. m .. " candidates too large for exact "
            .. "computation (" .. m .. "! permutations). Use kemeny.borda instead")
    end
    if m == 0 then
        error("kemeny.exact: no candidates found in rankings")
    end

    -- Validate all rankings have same candidates
    for k, r in ipairs(rankings) do
        if #r ~= m then
            error("kemeny.exact: ranking " .. k .. " has " .. #r
                .. " candidates, expected " .. m)
        end
    end

    local best_dist = math.huge
    local best_rankings = {}

    each_permutation(candidates, function(perm)
        -- Copy permutation (callback reuses the array)
        local candidate = {}
        for i = 1, m do candidate[i] = perm[i] end

        local dist = total_distance(candidate, rankings)
        if dist < best_dist then
            best_dist = dist
            best_rankings = { candidate }
        elseif dist == best_dist then
            local copy = {}
            for i = 1, m do copy[i] = perm[i] end
            best_rankings[#best_rankings + 1] = copy
        end
    end)

    local ties = {}
    if #best_rankings > 1 then
        for i = 2, #best_rankings do
            ties[#ties + 1] = best_rankings[i]
        end
    end

    return {
        ranking = best_rankings[1],
        total_distance = best_dist,
        is_unique = #best_rankings == 1,
        ties = ties,
        method = "exact",
        candidates = m,
        rankings_count = #rankings,
    }
end

--- Borda count aggregation.
--- B_a = Σ_{k} (m - rank_k(a)) for each candidate a.
--- Ranking = candidates sorted by descending Borda score.
---
---@param rankings table list of rankings
---@return table result { ranking, scores, total_distance, ties, method }
function M.borda(rankings)
    if type(rankings) ~= "table" or #rankings == 0 then
        error("kemeny.borda: rankings must be a non-empty list")
    end

    local candidates = extract_candidates(rankings)
    local m = #candidates
    if m == 0 then
        error("kemeny.borda: no candidates found in rankings")
    end

    -- Compute Borda scores
    local scores = {}
    for _, c in ipairs(candidates) do scores[c] = 0 end

    for _, r in ipairs(rankings) do
        local n_items = #r
        for pos, item in ipairs(r) do
            scores[item] = scores[item] + (n_items - pos)
        end
    end

    -- Sort candidates by descending score
    local sorted = {}
    for _, c in ipairs(candidates) do
        sorted[#sorted + 1] = c
    end
    table.sort(sorted, function(a, b)
        if scores[a] ~= scores[b] then
            return scores[a] > scores[b]
        end
        -- Tie-break by string representation for determinism
        return tostring(a) < tostring(b)
    end)

    -- Detect ties
    local ties = {}
    for i = 1, #sorted - 1 do
        if scores[sorted[i]] == scores[sorted[i + 1]] then
            if #ties == 0 or ties[#ties][2] ~= sorted[i] then
                ties[#ties + 1] = { sorted[i], sorted[i + 1] }
            else
                ties[#ties][#ties[#ties] + 1] = sorted[i + 1]
            end
        end
    end

    local dist = total_distance(sorted, rankings)

    return {
        ranking = sorted,
        scores = scores,
        total_distance = dist,
        ties = ties,
        method = "borda",
        candidates = m,
        rankings_count = #rankings,
    }
end

--- Auto-select: exact if m ≤ 8, borda otherwise.
---
---@param rankings table list of rankings
---@return table result
function M.aggregate(rankings)
    if type(rankings) ~= "table" or #rankings == 0 then
        error("kemeny.aggregate: rankings must be a non-empty list")
    end

    local candidates = extract_candidates(rankings)
    if #candidates <= 8 then
        return M.exact(rankings)
    else
        return M.borda(rankings)
    end
end

--- Build pairwise majority matrix.
--- matrix[a][b] = number of rankings where a is preferred over b.
---
---@param rankings table list of rankings
---@return table matrix matrix[a][b] = count
function M.pairwise(rankings)
    if type(rankings) ~= "table" or #rankings == 0 then
        error("kemeny.pairwise: rankings must be a non-empty list")
    end

    local candidates = extract_candidates(rankings)
    local matrix = {}
    for _, a in ipairs(candidates) do
        matrix[a] = {}
        for _, b in ipairs(candidates) do
            matrix[a][b] = 0
        end
    end

    for _, r in ipairs(rankings) do
        local pos = rank_positions(r)
        for i = 1, #r do
            for j = i + 1, #r do
                local a = r[i]
                local b = r[j]
                -- In this ranking, a is preferred over b
                matrix[a][b] = matrix[a][b] + 1
            end
        end
    end

    return matrix
end

--- Detect Condorcet winner: a candidate who beats every other
--- candidate in pairwise majority.
---
---@param rankings table list of rankings
---@return any|nil winner the Condorcet winner, or nil if none exists
function M.condorcet_winner(rankings)
    if type(rankings) ~= "table" or #rankings == 0 then
        error("kemeny.condorcet_winner: rankings must be a non-empty list")
    end

    local matrix = M.pairwise(rankings)
    local candidates = extract_candidates(rankings)
    local n_voters = #rankings

    for _, c in ipairs(candidates) do
        local beats_all = true
        for _, other in ipairs(candidates) do
            if c ~= other then
                if matrix[c][other] <= n_voters / 2 then
                    beats_all = false
                    break
                end
            end
        end
        if beats_all then return c end
    end

    return nil
end

return M
