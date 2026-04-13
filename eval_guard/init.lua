--- eval_guard — Evaluation safety gates (N2 + N3 + N4 Red Lines)
---
--- Pure-computation gate checks for evaluation safety in multi-agent
--- systems. Each gate returns (passed, reason) and can be used
--- independently or combined via check_all().
---
--- Gates:
---   N2 self_critique  — Huang et al. ICLR 2024: "Large Language Models
---                        Cannot Self-Correct Reasoning Yet". Intrinsic
---                        self-correction degrades accuracy without an
---                        external grader (GPT-4 GSM8K 95.5→89.0).
---   N3 baseline       — Wang Q et al. ACL 2024 Findings + Kapoor 2024:
---                        multi-agent must run with same-budget SC/CoT
---                        baseline for fair comparison. Without baseline,
---                        complex multi-agent setups often lose to simple
---                        single-agent + Self-Consistency.
---   N4 contamination  — Zhu et al. EMNLP 2024: absolute accuracy on
---                        standard benchmarks is unreliable due to data
---                        contamination (GSM8K -22.9pt, MMLU -19.0pt
---                        after decontamination).
---
--- N1 (inverse_u) and N5 (cost_pareto) are separate packages due to
--- non-trivial computation. This package handles structural checks.
---
--- Multi-Agent / Swarm context:
---   These gates are pre-flight checks before trusting any multi-agent
---   evaluation result. Without them, common pitfalls go undetected:
---
---   - N2: Reflexion/self-critique loops without external verification
---     are a known failure mode in multi-agent pipelines (MAST F5).
---     The gate enforces that self-correction always has a ground-truth
---     signal (unit test, symbolic check, cross-model verification).
---   - N3: The most common multi-agent evaluation error is comparing
---     a 5-agent system against a single agent WITHOUT equalizing the
---     compute budget. This gate enforces baseline fairness.
---   - N4: Standard benchmarks (GSM8K, MMLU, HumanEval) are
---     contaminated in most LLMs. The gate requires hold-out delta +
---     cost + Pareto as the evaluation criterion set.
---   - check_all() runs all three gates and produces a combined report,
---     suitable for automated pipeline enforcement.
---   - Composable with scoring_rule (calibration measurement after
---     gates pass) and cost_pareto (N5 Pareto dominance check).
---
--- Usage:
---   local eg = require("eval_guard")
---   local ok, reason = eg.self_critique({has_external_grader = false})
---   local report = eg.check_all({
---     has_external_grader = false,
---     has_baseline = true,
---     metric_type = "absolute",
---   })

local M = {}

---@type AlcMeta
M.meta = {
    name = "eval_guard",
    version = "0.1.0",
    description = "Evaluation safety gates for multi-agent systems — "
        .. "self-critique guard (N2, Huang ICLR 2024), baseline "
        .. "enforcement (N3, Wang-Kapoor 2024), contamination shield "
        .. "(N4, Zhu EMNLP 2024). Pre-flight checks before trusting "
        .. "any multi-agent evaluation result.",
    category = "validation",
}

--- N2: Self-critique gate.
--- Huang ICLR 2024: GPT-4 GSM8K 95.5->89.0, GPT-3.5 CSQA 75.8->41.8
--- when using intrinsic self-correction without external feedback.
---
--- Rule: self-critique loops MUST have an external grader (unit test,
--- symbolic checker, different-provider LLM) to be used as a
--- deterministic decision path.
---
---@param opts table { has_external_grader: boolean, grader_type: string|nil }
---@return boolean passed
---@return string reason
function M.self_critique(opts)
    if type(opts) ~= "table" then
        error("eval_guard.self_critique: opts must be a table")
    end
    if opts.has_external_grader then
        return true, string.format(
            "N2 PASS: external grader present%s",
            opts.grader_type and (" (type: " .. opts.grader_type .. ")") or "")
    end
    return false, "N2 FAIL: self-critique without external grader. "
        .. "Huang ICLR 2024 shows intrinsic self-correction degrades accuracy "
        .. "(GPT-4 GSM8K 95.5->89.0, GPT-3.5 CSQA 75.8->41.8). "
        .. "Add an external grader or disable the self-critique loop."
end

--- N3: Baseline enforcement gate.
--- Wang Q ACL 2024 Findings: Single 75.63% vs MAD 70.04% (-5.59pt)
--- Kapoor 2024: warming $2.45/93.2% > LATS $134.50/88.0%
---
--- Rule: multi-agent evaluation MUST include a same-budget
--- single-agent + CoT/SC baseline for fair comparison.
---
---@param opts table { has_baseline: boolean, baseline_budget_matches: boolean|nil }
---@return boolean passed
---@return string reason
function M.baseline(opts)
    if type(opts) ~= "table" then
        error("eval_guard.baseline: opts must be a table")
    end
    if not opts.has_baseline then
        return false, "N3 FAIL: no baseline run. Multi-agent evaluation requires "
            .. "a same-budget single-agent + CoT/SC baseline. "
            .. "Wang Q ACL 2024: Single 75.63% vs MAD 70.04% (-5.59pt)."
    end
    if opts.baseline_budget_matches == false then
        return false, "N3 FAIL: baseline exists but budget does not match. "
            .. "Baseline must use the same total token budget as the multi-agent run."
    end
    return true, "N3 PASS: baseline present" ..
        (opts.baseline_budget_matches and " with matching budget" or "")
end

--- N4: Contamination shield gate.
--- Zhu EMNLP 2024: GSM8K -22.9pt, MMLU -19.0pt after decontamination.
---
--- Rule: absolute accuracy on standard benchmarks (GSM8K, MMLU,
--- HumanEval) MUST NOT be used as the sole design/merge criterion.
--- Required: hold-out delta + cost + Pareto (3-point set).
---
---@param opts table { metric_type: string, has_holdout: boolean|nil, has_cost: boolean|nil, has_pareto: boolean|nil }
---@return boolean passed
---@return string reason
function M.contamination(opts)
    if type(opts) ~= "table" then
        error("eval_guard.contamination: opts must be a table")
    end
    local mt = opts.metric_type or "unknown"
    if mt == "absolute" then
        return false, "N4 FAIL: absolute accuracy on standard benchmark is unreliable. "
            .. "Zhu EMNLP 2024: GSM8K -22.9pt, MMLU -19.0pt after decontamination. "
            .. "Use hold-out delta + cost + Pareto instead."
    end
    -- Check 3-point set if metric_type is "delta" or similar
    local missing = {}
    if opts.has_holdout == false then missing[#missing + 1] = "hold-out delta" end
    if opts.has_cost == false then missing[#missing + 1] = "cost metric" end
    if opts.has_pareto == false then missing[#missing + 1] = "Pareto comparison" end
    if #missing > 0 then
        return false, "N4 FAIL: missing required metrics: " .. table.concat(missing, ", ")
            .. ". All three (hold-out delta, cost, Pareto) are required."
    end
    return true, "N4 PASS: evaluation uses contamination-safe metrics"
end

--- Run all gates and return a combined report.
---
---@param opts table combined options for all gates:
---   has_external_grader: boolean (N2)
---   grader_type: string|nil (N2)
---   has_baseline: boolean (N3)
---   baseline_budget_matches: boolean|nil (N3)
---   metric_type: string (N4)
---   has_holdout: boolean|nil (N4)
---   has_cost: boolean|nil (N4)
---   has_pareto: boolean|nil (N4)
---@return table report { passed: boolean, violations: list, details: list }
function M.check_all(opts)
    if type(opts) ~= "table" then
        error("eval_guard.check_all: opts must be a table")
    end
    local checks = {
        { name = "N2_self_critique", fn = M.self_critique, args = {
            has_external_grader = opts.has_external_grader,
            grader_type = opts.grader_type,
        }},
        { name = "N3_baseline", fn = M.baseline, args = {
            has_baseline = opts.has_baseline,
            baseline_budget_matches = opts.baseline_budget_matches,
        }},
        { name = "N4_contamination", fn = M.contamination, args = {
            metric_type = opts.metric_type,
            has_holdout = opts.has_holdout,
            has_cost = opts.has_cost,
            has_pareto = opts.has_pareto,
        }},
    }

    local violations = {}
    local details = {}
    local all_passed = true

    for _, c in ipairs(checks) do
        local ok, reason = c.fn(c.args)
        details[#details + 1] = { gate = c.name, passed = ok, reason = reason }
        if not ok then
            all_passed = false
            violations[#violations + 1] = { gate = c.name, reason = reason }
        end
    end

    return {
        passed = all_passed,
        violations = violations,
        details = details,
        n_passed = #details - #violations,
        n_failed = #violations,
        n_total = #details,
    }
end

return M
