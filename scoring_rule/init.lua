--- scoring_rule — Proper Scoring Rules for calibration measurement
---
--- Pure-computation utility for evaluating the calibration of
--- probabilistic predictions. A scoring rule S(p, y) is "proper"
--- if reporting one's true belief maximizes expected score, and
--- "strictly proper" if this maximum is unique.
---
--- Theory:
---   Brier, G. W. "Verification of forecasts expressed in terms of
---   probability". Monthly Weather Review 78(1), pp.1-3, 1950.
---
---   Savage, L. J. "Elicitation of personal probabilities and expectations".
---   JASA 66(336), pp.783-801, 1971.
---
---   Gneiting, T., Raftery, A. E. "Strictly Proper Scoring Rules, Prediction,
---   and Estimation". JASA 102(477), pp.359-378, 2007.
---
---   Naeini, M. P., Cooper, G. F., Hauskrecht, M. "Obtaining Well Calibrated
---   Probabilities Using Bayesian Binning into Quantiles". AAAI 2015.
---
---   Properness (Savage 1971):
---     S is proper ⟺ ∀q: E_{Y~q}[S(q, Y)] ≥ E_{Y~q}[S(p, Y)]  ∀p
---     Strictly proper: equality only when p = q
---
---   Provided rules (all strictly proper):
---     Brier (1950):     S(p, y) = -(p - y)²
---     Logarithmic:      S(p, y) = y·ln(p) + (1-y)·ln(1-p)
---     Spherical:        S(p, y) = [p·y + (1-p)·(1-y)] / √(p² + (1-p)²)
---
--- Multi-Agent / Swarm context:
---   Proper scoring rules are the mathematically correct way to evaluate
---   whether an agent's confidence matches its actual accuracy. An agent
---   that says "80% sure" should be right ~80% of the time.
---
---   - Agent calibration audit: evaluate() scores a series of
---     agent predictions against outcomes. Poorly calibrated agents
---     (overconfident or underconfident) are identified quantitatively.
---   - Calibration diagnosis: calibration() computes the Expected
---     Calibration Error (ECE) with binned analysis, and flags
---     whether the agent is systematically overconfident or
---     underconfident. This is critical for trust — an overconfident
---     agent's "90% sure" answers may only be right 60% of the time.
---   - Multi-agent comparison: compare() ranks multiple agents by
---     calibration quality, identifying which agent's probability
---     estimates are most trustworthy. The best-calibrated agent
---     should receive the highest weight in ensemble decisions.
---   - Rule selection: Brier is robust and easy to interpret;
---     log score is more sensitive to extreme miscalibration;
---     spherical has less extreme penalties than log.
---   - Connects to mwu (calibration scores as loss input for weight
---     learning), condorcet (well-calibrated p > 0.5 validates the
---     Jury Theorem), and eval_guard (calibration as evaluation
---     quality metric).
---
--- Usage:
---   local sr = require("scoring_rule")
---   sr.brier(0.8, 1)           -- => -0.04
---   sr.log_score(0.8, 1)       -- => -0.2231...
---   local cal = sr.calibration(predictions, outcomes, { bins = 10 })

local M = {}

---@type AlcMeta
M.meta = {
    name = "scoring_rule",
    version = "0.1.0",
    description = "Proper Scoring Rules — Brier, logarithmic, spherical "
        .. "scores + ECE calibration measurement for evaluating agent "
        .. "prediction quality. Audits whether agent confidence matches "
        .. "actual accuracy (Brier 1950, Gneiting-Raftery JASA 2007).",
    category = "evaluation",
}

-- ─── Internal helpers ───

local EPS = 1e-15  -- clamp bound to avoid log(0)

--- Normalize outcome to 0 or 1.
local function to_binary(y)
    if y == true or y == 1 then return 1 end
    if y == false or y == 0 then return 0 end
    error("scoring_rule: outcome must be 0/1 or true/false, got " .. tostring(y))
end

--- Validate prediction in [0, 1].
local function check_pred(p, context)
    if type(p) ~= "number" or p < 0 or p > 1 then
        error("scoring_rule" .. (context or "") .. ": prediction must be in [0, 1], got "
            .. tostring(p))
    end
end

--- Clamp prediction to [EPS, 1-EPS] for log safety.
--- Returns clamped value and whether clamping occurred.
local function clamp(p)
    if p < EPS then return EPS, true end
    if p > 1 - EPS then return 1 - EPS, true end
    return p, false
end

-- ─── Individual scoring rules ───

--- Brier score: S(p, y) = -(p - y)²
--- Range: [-1, 0], 0 is best.
--- Strictly proper.
---@param p number predicted probability in [0, 1]
---@param y number|boolean actual outcome (0/1 or true/false)
---@return number score
function M.brier(p, y)
    check_pred(p, ".brier")
    local y_bin = to_binary(y)
    local d = p - y_bin
    return -(d * d)
end

--- Logarithmic score: S(p, y) = y·ln(p) + (1-y)·ln(1-p)
--- Range: (-∞, 0], 0 is best (achieved only at p=y∈{0,1}).
--- Strictly proper. More sensitive to small calibration errors than Brier.
--- Predictions are clamped to [ε, 1-ε] to avoid -∞.
---@param p number predicted probability in [0, 1]
---@param y number|boolean actual outcome
---@return number score
---@return boolean clamped whether p was clamped
function M.log_score(p, y)
    check_pred(p, ".log_score")
    local y_bin = to_binary(y)
    local pc, was_clamped = clamp(p)
    local score = y_bin * math.log(pc) + (1 - y_bin) * math.log(1 - pc)
    return score, was_clamped
end

--- Spherical score: S(p, y) = [p·y + (1-p)·(1-y)] / √(p² + (1-p)²)
--- Range: [1/√2, 1], 1 is best.
--- Strictly proper. Less extreme penalties than log score.
---@param p number predicted probability in [0, 1]
---@param y number|boolean actual outcome
---@return number score
function M.spherical(p, y)
    check_pred(p, ".spherical")
    local y_bin = to_binary(y)
    local numerator = p * y_bin + (1 - p) * (1 - y_bin)
    local denominator = math.sqrt(p * p + (1 - p) * (1 - p))
    if denominator < EPS then return 1 / math.sqrt(2) end
    return numerator / denominator
end

-- ─── Batch evaluation ───

--- Evaluate a series of predictions against outcomes.
---@param predictions table { p_1, p_2, ..., p_n } each in [0, 1]
---@param outcomes table { y_1, y_2, ..., y_n } each 0/1 or true/false
---@param opts table|nil { rule = "brier"|"log"|"spherical" }
---@return table result { mean_score, scores, n, clamped_count? }
function M.evaluate(predictions, outcomes, opts)
    if type(predictions) ~= "table" or #predictions == 0 then
        error("scoring_rule.evaluate: predictions must be a non-empty list")
    end
    if type(outcomes) ~= "table" or #outcomes ~= #predictions then
        error("scoring_rule.evaluate: outcomes must match predictions length")
    end
    opts = opts or {}
    local rule = opts.rule or "brier"

    local scores = {}
    local total = 0
    local clamped_count = 0

    for i = 1, #predictions do
        local s
        if rule == "brier" then
            s = M.brier(predictions[i], outcomes[i])
        elseif rule == "log" then
            local clamped
            s, clamped = M.log_score(predictions[i], outcomes[i])
            if clamped then clamped_count = clamped_count + 1 end
        elseif rule == "spherical" then
            s = M.spherical(predictions[i], outcomes[i])
        else
            error("scoring_rule.evaluate: unknown rule '" .. rule
                .. "', expected brier/log/spherical")
        end
        scores[i] = s
        total = total + s
    end

    local result = {
        mean_score = total / #predictions,
        scores = scores,
        n = #predictions,
        rule = rule,
    }
    if rule == "log" then
        result.clamped_count = clamped_count
    end
    return result
end

-- ─── Calibration analysis ───

--- Compute calibration curve and Expected Calibration Error (ECE).
---
--- ECE = Σ_{b} (n_b / N) · |acc(b) - conf(b)|
---
---@param predictions table { p_1, ..., p_n }
---@param outcomes table { y_1, ..., y_n }
---@param opts table|nil { bins = 10 }
---@return table cal { ece, bins, overconfident, underconfident }
function M.calibration(predictions, outcomes, opts)
    if type(predictions) ~= "table" or #predictions == 0 then
        error("scoring_rule.calibration: predictions must be a non-empty list")
    end
    if type(outcomes) ~= "table" or #outcomes ~= #predictions then
        error("scoring_rule.calibration: outcomes must match predictions length")
    end
    opts = opts or {}
    local n_bins = opts.bins or 10
    local N = #predictions

    -- Adjust bins if more bins than samples
    if n_bins > N then n_bins = N end

    -- Initialize bins
    local bin_sum_conf = {}
    local bin_sum_acc = {}
    local bin_count = {}
    for b = 1, n_bins do
        bin_sum_conf[b] = 0
        bin_sum_acc[b] = 0
        bin_count[b] = 0
    end

    -- Assign samples to bins
    for i = 1, N do
        local p = predictions[i]
        check_pred(p, ".calibration")
        local y = to_binary(outcomes[i])

        -- Bin index: equal-width bins [0, 1/B), [1/B, 2/B), ..., [(B-1)/B, 1]
        local b = math.floor(p * n_bins) + 1
        if b > n_bins then b = n_bins end  -- p = 1.0 edge case

        bin_sum_conf[b] = bin_sum_conf[b] + p
        bin_sum_acc[b] = bin_sum_acc[b] + y
        bin_count[b] = bin_count[b] + 1
    end

    -- Compute ECE and bin statistics
    local ece = 0
    local bins = {}
    local total_overconf = 0
    local total_underconf = 0

    for b = 1, n_bins do
        if bin_count[b] > 0 then
            local conf = bin_sum_conf[b] / bin_count[b]
            local acc = bin_sum_acc[b] / bin_count[b]
            local gap = math.abs(acc - conf)

            ece = ece + (bin_count[b] / N) * gap

            if conf > acc then
                total_overconf = total_overconf + bin_count[b]
            elseif conf < acc then
                total_underconf = total_underconf + bin_count[b]
            end

            bins[#bins + 1] = {
                conf = conf,
                acc = acc,
                count = bin_count[b],
                gap = gap,
            }
        end
    end

    return {
        ece = ece,
        bins = bins,
        overconfident = total_overconf > total_underconf,
        underconfident = total_underconf > total_overconf,
        n = N,
        n_bins = n_bins,
    }
end

-- ─── Multi-agent comparison ───

--- Compare multiple agents' calibration using a scoring rule.
---@param agents table { { name, predictions, outcomes }, ... }
---@param opts table|nil { rule = "brier"|"log"|"spherical" }
---@return table cmp { ranking, scores, best }
function M.compare(agents, opts)
    if type(agents) ~= "table" or #agents == 0 then
        error("scoring_rule.compare: agents must be a non-empty list")
    end
    opts = opts or {}

    local entries = {}
    local scores = {}

    for _, agent in ipairs(agents) do
        if not agent.name then
            error("scoring_rule.compare: each agent must have a .name")
        end
        if not agent.predictions or not agent.outcomes then
            error("scoring_rule.compare: agent '" .. agent.name
                .. "' must have .predictions and .outcomes")
        end
        local r = M.evaluate(agent.predictions, agent.outcomes, opts)
        scores[agent.name] = r.mean_score
        entries[#entries + 1] = { name = agent.name, score = r.mean_score }
    end

    -- Sort by score descending (higher = better for all rules)
    table.sort(entries, function(a, b) return a.score > b.score end)

    local ranking = {}
    for _, e in ipairs(entries) do
        ranking[#ranking + 1] = e.name
    end

    return {
        ranking = ranking,
        scores = scores,
        best = ranking[1],
    }
end

return M
