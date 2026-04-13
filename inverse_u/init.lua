--- inverse_u — Inverse-U scaling detection (Chen et al. NeurIPS 2024)
---
--- Pure-computation utility for detecting non-monotonic accuracy
--- scaling when increasing the number of LLM agents/calls.
---
--- Based on: Chen, Davis, Hanin, Bailis, Stoica, Zaharia, Zou.
--- "Are More LM Calls All You Need?" NeurIPS 2024. arXiv:2403.02419
---
--- Theorem 2: For a synthetic dataset D_{alpha,p1,p2},
--- if p1 + p2 > 1 AND alpha < 1 - 1/t, then Vote / Filter-Vote
--- accuracy is inverse-U shaped in N (number of agents).
---
--- Practical implication: blindly increasing N can DEGRADE accuracy
--- on the hard query subset. This package detects the peak and
--- recommends early stopping.
---
--- Usage:
---   local iu = require("inverse_u")
---   local r = iu.detect({0.70, 0.75, 0.73, 0.71})
---   -- r.peak_idx=2, r.is_declining=true, r.consecutive_drops=2

local M = {}

---@type AlcMeta
M.meta = {
    name = "inverse_u",
    version = "0.1.0",
    description = "Inverse-U scaling detection — detect non-monotonic "
        .. "accuracy-vs-N curves (Chen NeurIPS 2024 Theorem 2)",
    category = "foundation",
}

--- Detect inverse-U pattern in an accuracy-by-N series.
--- The series is indexed by N (number of agents/calls),
--- starting from N=1 at index 1.
---
---@param accuracy_by_n table list of accuracy values {acc_n1, acc_n2, ...}
---@param opts table|nil optional { flat_epsilon: number (default 1e-6) }
---@return table result {
---   peak_idx: index with highest accuracy,
---   peak_n: N value at peak (= peak_idx),
---   peak_acc: accuracy at peak,
---   is_declining: true if last 2+ entries decline from peak,
---   consecutive_drops: number of consecutive drops from peak,
---   trend: "monotone_up" | "inverse_u" | "monotone_down" | "flat" | "noisy" | "insufficient"
--- }
function M.detect(accuracy_by_n, opts)
    if type(accuracy_by_n) ~= "table" then
        error("inverse_u.detect: expected a table of accuracy values")
    end
    opts = opts or {}
    local flat_epsilon = opts.flat_epsilon or 1e-6
    local n = #accuracy_by_n
    if n == 0 then
        error("inverse_u.detect: empty accuracy series")
    end
    if n == 1 then
        return {
            peak_idx = 1, peak_n = 1,
            peak_acc = accuracy_by_n[1],
            is_declining = false,
            consecutive_drops = 0,
            trend = "insufficient",
        }
    end

    -- Find peak
    local peak_idx = 1
    local peak_acc = accuracy_by_n[1]
    for i = 2, n do
        if accuracy_by_n[i] > peak_acc then
            peak_acc = accuracy_by_n[i]
            peak_idx = i
        end
    end

    -- Count consecutive drops from peak
    local drops = 0
    for i = peak_idx + 1, n do
        if accuracy_by_n[i] < accuracy_by_n[i - 1] then
            drops = drops + 1
        else
            drops = 0
        end
    end

    -- Flat detection first: if range is tiny, nothing else matters
    local min_v, max_v = accuracy_by_n[1], accuracy_by_n[1]
    for i = 2, n do
        if accuracy_by_n[i] < min_v then min_v = accuracy_by_n[i] end
        if accuracy_by_n[i] > max_v then max_v = accuracy_by_n[i] end
    end

    local trend
    if max_v - min_v < flat_epsilon then
        trend = "flat"
    elseif peak_idx == 1 then
        -- Peak at start: monotone_down or noisy (non-monotonic but peak at edge)
        local all_down = true
        for i = 2, n do
            if accuracy_by_n[i] >= accuracy_by_n[i - 1] then
                all_down = false
                break
            end
        end
        trend = all_down and "monotone_down" or "noisy"
    elseif peak_idx == n then
        -- Peak at end: monotone_up or noisy
        local all_up = true
        for i = 2, n do
            if accuracy_by_n[i] <= accuracy_by_n[i - 1] then
                all_up = false
                break
            end
        end
        trend = all_up and "monotone_up" or "noisy"
    else
        trend = "inverse_u"
    end

    return {
        peak_idx = peak_idx,
        peak_n = peak_idx,
        peak_acc = peak_acc,
        is_declining = drops >= 2,
        consecutive_drops = drops,
        trend = trend,
    }
end

--- Recommend whether to stop adding agents based on the accuracy series.
--- Returns true (stop) if 2+ consecutive drops are detected from peak.
--- This is the G1 gate from application_layer.md section 4.3.
---
---@param accuracy_by_n table list of accuracy values
---@param min_drops integer consecutive drops to trigger stop (default: 2)
---@param opts table|nil optional { flat_epsilon: number } passed to detect()
---@return boolean should_stop true if should stop adding agents
---@return string reason
function M.should_stop(accuracy_by_n, min_drops, opts)
    min_drops = min_drops or 2
    local r = M.detect(accuracy_by_n, opts)
    if r.consecutive_drops >= min_drops then
        return true, string.format(
            "inverse-U detected: peak at N=%d (acc=%.4f), %d consecutive drops. Stop adding agents.",
            r.peak_n, r.peak_acc, r.consecutive_drops)
    end
    return false, string.format(
        "no inverse-U: peak at N=%d (acc=%.4f), %d drops (threshold=%d)",
        r.peak_n, r.peak_acc, r.consecutive_drops, min_drops)
end

--- Evaluate the theoretical condition from Chen 2024 Theorem 2.
--- Inverse-U occurs when: p1 + p2 > 1 AND alpha < 1 - 1/t
---
--- p1 = accuracy on easy queries
--- p2 = accuracy on hard queries  (Note: p2 can be < 0.5)
--- alpha = fraction of hard queries in the dataset
--- t = number of agents/voters
---
---@param p1 number accuracy on easy subset
---@param p2 number accuracy on hard subset
---@param alpha number fraction of hard queries (0 to 1)
---@param t integer number of agents
---@return boolean inverse_u_expected true if theory predicts inverse-U
---@return table conditions { p_sum_gt_1, alpha_lt_threshold, threshold }
function M.chen_condition(p1, p2, alpha, t)
    if type(p1) ~= "number" or type(p2) ~= "number" then
        error("inverse_u.chen_condition: p1, p2 must be numbers")
    end
    if type(alpha) ~= "number" or alpha < 0 or alpha > 1 then
        error("inverse_u.chen_condition: alpha must be in [0, 1]")
    end
    if type(t) ~= "number" or t < 1 then
        error("inverse_u.chen_condition: t must be >= 1")
    end
    local p_sum_gt_1 = (p1 + p2) > 1
    local threshold = 1 - 1 / t
    local alpha_lt = alpha < threshold
    return p_sum_gt_1 and alpha_lt, {
        p_sum = p1 + p2,
        p_sum_gt_1 = p_sum_gt_1,
        alpha = alpha,
        threshold = threshold,
        alpha_lt_threshold = alpha_lt,
    }
end

return M
