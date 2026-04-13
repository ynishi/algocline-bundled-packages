--- condorcet — Condorcet Jury Theorem probability calculator
---
--- Pure-computation utility for majority-vote probability under
--- independent voters. Detects Anti-Jury conditions (p < 0.5),
--- estimates required group size for target accuracy, and measures
--- inter-agent correlation to verify the independence assumption.
---
--- Theory:
---   Condorcet, M. "Essai sur l'application de l'analyse à la
---   probabilité des décisions rendues à la pluralité des voix", 1785.
---   Modern formalization: Dietrich & List "Jury Theorems", SEP, 2008.
---
---   Core formula:
---     P(Maj_n) = SUM_{k=ceil(n/2)}^{n} C(n,k) * p^k * (1-p)^{n-k}
---
---   Jury Theorem: Under Uniform Independence (UI) and Uniform
---   Competence p > 0.5 (UC), P(Maj_n) → 1 as n → ∞.
---   Anti-Jury: If p < 0.5, P(Maj_n) → 0 as n → ∞ — adding
---   more voters makes the group *worse*.
---
--- Multi-Agent / Swarm context:
---   The Jury Theorem is the mathematical foundation for why
---   multi-agent voting (sc, panel, moa) can outperform single agents.
---   It also explains when it fails:
---
---   - Panel sizing: optimal_n() computes the minimum number of
---     agents needed to reach a target accuracy (e.g. 95%).
---   - Anti-Jury detection: is_anti_jury() catches the dangerous
---     case where agents are worse than random (p < 0.5), meaning
---     Self-Consistency and majority vote will *degrade* with more
---     agents. This validates the Chen NeurIPS 2024 finding
---     (see inverse_u package).
---   - Independence verification: correlation() measures pairwise
---     Pearson correlation between agent outputs. High correlation
---     (same model/prompt) violates UI and weakens the theorem's
---     guarantee — prompting strategy diversification.
---   - Composable with sc, panel, moa, pbft as the theoretical
---     justification for their majority-vote aggregation.
---
--- Usage:
---   local condorcet = require("condorcet")
---   condorcet.prob_majority(5, 0.7)  -- => ~0.837
---   condorcet.is_anti_jury(0.4)      -- => true

local M = {}

---@type AlcMeta
M.meta = {
    name = "condorcet",
    version = "0.1.0",
    description = "Condorcet Jury Theorem — majority-vote probability, "
        .. "Anti-Jury detection, optimal panel sizing, and independence "
        .. "verification for multi-agent voting systems "
        .. "(Condorcet 1785, Dietrich-List 2008).",
    category = "aggregation",
}

-- ─── Combinatorics helpers ───

--- Log-space binomial coefficient to avoid overflow.
--- Uses Stirling or direct computation for small values.
local function log_comb(n, k)
    if k < 0 or k > n then return -math.huge end
    if k == 0 or k == n then return 0 end
    -- Symmetry: C(n,k) = C(n, n-k)
    if k > n - k then k = n - k end
    local s = 0
    for i = 0, k - 1 do
        s = s + math.log(n - i) - math.log(i + 1)
    end
    return s
end

--- Binomial probability P(X = k) where X ~ Binom(n, p).
local function binom_pmf(n, k, p)
    if p <= 0 then return k == 0 and 1.0 or 0.0 end
    if p >= 1 then return k == n and 1.0 or 0.0 end
    local log_prob = log_comb(n, k) + k * math.log(p) + (n - k) * math.log(1 - p)
    return math.exp(log_prob)
end

-- ─── Public API ───

--- Probability that a majority of n independent voters with accuracy p
--- reaches the correct answer.
--- P(Maj_n) = SUM_{k=ceil(n/2)}^{n} C(n,k) * p^k * (1-p)^{n-k}
---@param n integer number of voters (must be odd for strict majority)
---@param p number individual accuracy probability in (0, 1)
---@return number prob majority probability
function M.prob_majority(n, p)
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("condorcet.prob_majority: n must be a positive integer, got " .. tostring(n))
    end
    if type(p) ~= "number" or p < 0 or p > 1 then
        error("condorcet.prob_majority: p must be in [0, 1], got " .. tostring(p))
    end
    local majority = math.ceil(n / 2)
    local total = 0
    for k = majority, n do
        total = total + binom_pmf(n, k, p)
    end
    return total
end

--- Check if the Anti-Jury condition holds.
--- When p < 0.5, increasing n makes the majority *worse*.
---@param p number individual accuracy
---@return boolean is_anti true if p < 0.5
---@return string reason explanation
function M.is_anti_jury(p)
    if type(p) ~= "number" then
        error("condorcet.is_anti_jury: p must be a number, got " .. tostring(p))
    end
    if p < 0.5 then
        return true, string.format(
            "p=%.3f < 0.5: Anti-Jury — increasing n DEGRADES majority accuracy", p)
    elseif p == 0.5 then
        return false, "p=0.5: coin flip — majority stays at 0.5 regardless of n"
    else
        return false, string.format(
            "p=%.3f > 0.5: Jury Theorem — increasing n improves majority accuracy", p)
    end
end

--- Find the minimum odd n such that P(Maj_n) >= target.
--- Returns nil if p <= 0.5 (impossible to reach target > 0.5).
---@param p number individual accuracy (must be > 0.5)
---@param target number target majority probability (default: 0.95)
---@param max_n number search ceiling (default: 999)
---@return integer|nil n minimum group size, or nil if unreachable
---@return number|nil prob achieved probability at that n
function M.optimal_n(p, target, max_n)
    target = target or 0.95
    max_n = max_n or 999
    if type(p) ~= "number" or p <= 0.5 then
        return nil, nil
    end
    -- Only check odd n for clean majority
    for n = 1, max_n, 2 do
        local prob = M.prob_majority(n, p)
        if prob >= target then
            return n, prob
        end
    end
    return nil, nil
end

--- Compute pairwise Pearson correlation matrix from numeric output vectors.
--- Used to verify the independence assumption (UI) that Condorcet requires.
---
--- Low correlations (near 0) support the independence assumption.
--- High positive correlations indicate shared bias (e.g., same model/prompt).
---@param outputs table list of numeric vectors, each {score1, score2, ...}
---@return table matrix correlation matrix [i][j]
---@return number avg_corr average off-diagonal correlation
function M.correlation(outputs)
    local n = #outputs
    if n < 2 then
        error("condorcet.correlation: need at least 2 output vectors")
    end
    local len = #outputs[1]
    for i = 2, n do
        if #outputs[i] ~= len then
            error("condorcet.correlation: all vectors must have equal length")
        end
    end
    if len < 2 then
        error("condorcet.correlation: vectors must have at least 2 elements")
    end

    -- Compute means
    local means = {}
    for i = 1, n do
        local s = 0
        for j = 1, len do s = s + outputs[i][j] end
        means[i] = s / len
    end

    -- Compute correlation matrix
    local matrix = {}
    local sum_corr, count_pairs = 0, 0
    for i = 1, n do
        matrix[i] = {}
        for j = 1, n do
            if i == j then
                matrix[i][j] = 1.0
            elseif j < i then
                matrix[i][j] = matrix[j][i]
                sum_corr = sum_corr + matrix[i][j]
                count_pairs = count_pairs + 1
            else
                local sum_xy, sum_x2, sum_y2 = 0, 0, 0
                for k = 1, len do
                    local dx = outputs[i][k] - means[i]
                    local dy = outputs[j][k] - means[j]
                    sum_xy = sum_xy + dx * dy
                    sum_x2 = sum_x2 + dx * dx
                    sum_y2 = sum_y2 + dy * dy
                end
                local denom = math.sqrt(sum_x2 * sum_y2)
                matrix[i][j] = denom > 0 and (sum_xy / denom) or 0
                sum_corr = sum_corr + matrix[i][j]
                count_pairs = count_pairs + 1
            end
        end
    end

    local avg_corr = count_pairs > 0 and (sum_corr / count_pairs) or 0
    return matrix, avg_corr
end

--- Estimate individual voter accuracy p-hat from binary outcomes.
---@param correct table list of boolean or 0/1 values (true/1 = correct)
---@return number p_hat estimated accuracy
---@return number ci_half 95% confidence interval half-width (normal approx)
function M.estimate_p(correct)
    if type(correct) ~= "table" or #correct == 0 then
        error("condorcet.estimate_p: need a non-empty list of outcomes")
    end
    local n = #correct
    local sum = 0
    for _, v in ipairs(correct) do
        if v == true or v == 1 then
            sum = sum + 1
        end
    end
    local p_hat = sum / n
    -- 95% CI: p_hat +/- 1.96 * sqrt(p*(1-p)/n)
    local ci_half = 1.96 * math.sqrt(p_hat * (1 - p_hat) / n)
    return p_hat, ci_half
end

return M
