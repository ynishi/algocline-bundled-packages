--- anti_cascade — Pipeline error cascade amplification detection
---
--- Detects when small errors compound through multi-step pipelines
--- by independently re-deriving conclusions from original inputs at
--- each checkpoint, then comparing with the pipeline's accumulated
--- output. Flags steps where drift exceeds threshold.
---
--- Generalizes the "Cascade Amplification" countermeasure from "From
--- Spark to Fire: Diagnosing and Overcoming the Fragility of Multi-
--- Agent Systems" (Xie et al., AAMAS 2026). The paper proved that a
--- single atomic error injection can collapse an entire multi-agent
--- system, and that independent re-derivation is one of the key
--- structural defenses.
---
--- Also addresses MAST (Cemri et al., 2025) failure modes F3
--- ("error propagation through pipeline") and F9 ("accumulated
--- context drift").
---
--- Pipeline (~1 + 2×N LLM calls, N = number of steps):
---   For each step:
---     1. Independent re-derivation from original task (parallel)
---     2. Comparison with pipeline output to compute drift score
---   Final: Summary with flagged steps and overall cascade risk
---
--- Usage:
---   local anti_cascade = require("anti_cascade")
---   return anti_cascade.run(ctx)
---
--- ctx.task (required): Original task/input
--- ctx.steps (required): Ordered table of pipeline step outputs
---     Each entry: { name = "step_name", instruction = "what this step does", output = "text" }
--- ctx.drift_threshold (optional): Drift score above which a step is flagged (default: 0.4)
--- ctx.rederive_tokens: Max tokens for re-derivation (default: 500)
--- ctx.compare_tokens: Max tokens for comparison (default: 400)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "anti_cascade",
    version = "0.1.0",
    description = "Pipeline error cascade detection — independently re-derives "
        .. "from original inputs at each step and compares with pipeline output "
        .. "to detect error amplification. Generalizes Cascade Amplification "
        .. "countermeasure from 'From Spark to Fire' (Xie et al., AAMAS 2026). "
        .. "Addresses MAST failure modes F3/F9.",
    category = "governance",
}

local step_input_shape = T.shape({
    name        = T.string:describe("Step identifier used in logs and result keys"),
    instruction = T.string:is_optional():describe("What this step should produce; falls back to step.name when absent"),
    output      = T.string:describe("Pipeline step's actual output text (subject of drift comparison)"),
})

local step_result_shape = T.shape({
    name         = T.string:describe("Step name (echo of input steps[i].name)"),
    drift_score  = T.number:describe("Parsed DRIFT_SCORE in [0, 1]; 0 when the compare LLM output was unparseable"),
    drift_type   = T.string:describe("Parsed DRIFT_TYPE (NONE|MINOR_REFINEMENT|ADDED_DETAIL|SHIFTED_FOCUS|FACTUAL_DIVERGENCE|CONTRADICTORY|UNKNOWN)"),
    cascade_risk = T.string:describe("Parsed CASCADE_RISK (LOW|MEDIUM|HIGH|UNKNOWN)"),
    flagged      = T.boolean:describe("True when drift_score >= ctx.drift_threshold"),
    raw          = T.string:describe("Full raw LLM comparison output for this step"),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task            = T.string:describe("Original task/input that the pipeline was given (required)"),
                steps           = T.array_of(step_input_shape):describe("Ordered pipeline step outputs; at least 1 entry (required)"),
                drift_threshold = T.number:is_optional():describe("Drift score threshold at which a step is flagged (default 0.4)"),
                rederive_tokens = T.number:is_optional():describe("Max tokens per independent re-derivation (default 500)"),
                compare_tokens  = T.number:is_optional():describe("Max tokens per pipeline-vs-independent comparison (default 400)"),
                summary_tokens  = T.number:is_optional():describe("Max tokens for the final summary analysis (default 500)"),
            }),
            result = T.shape({
                step_results  = T.array_of(step_result_shape):describe("Per-step drift analysis in pipeline order"),
                flagged_steps = T.array_of(T.string):describe("Names of steps whose drift_score crossed the threshold"),
                max_drift     = T.number:describe("Highest drift_score observed across all steps"),
                summary       = T.string:describe("LLM-generated cascade analysis summary text"),
            }),
        },
    },
}

-- ─── Prompts ───

local REDERIVE_SYSTEM = [[You are an independent analyst. Given ONLY the original task and the instruction for what this step should produce, generate your own output. You must work ONLY from the original task — do NOT rely on any prior pipeline context.

This is a fresh, independent derivation to check for pipeline drift.]]

local REDERIVE_PROMPT = [[Original task:
{task}

Step instruction: {instruction}

Produce your independent output for this step, working only from the original task above.]]

local COMPARE_SYSTEM = [[You are a drift detection analyst. Compare two outputs for the same step:
1. PIPELINE output (produced by the actual pipeline, which may have accumulated errors)
2. INDEPENDENT output (freshly derived from original inputs)

Assess the semantic drift between them.

Respond in this exact format:
DRIFT_SCORE: <0.0 to 1.0> (0.0 = identical meaning, 1.0 = completely divergent)
DRIFT_TYPE: NONE | MINOR_REFINEMENT | ADDED_DETAIL | SHIFTED_FOCUS | FACTUAL_DIVERGENCE | CONTRADICTORY
DIVERGENCES:
- <specific divergence 1>
- <specific divergence 2>
(or "None")
CASCADE_RISK: LOW | MEDIUM | HIGH
EXPLANATION: <brief explanation of the drift pattern>]]

local COMPARE_PROMPT = [[Step: {name}
Instruction: {instruction}

PIPELINE OUTPUT:
{pipeline_output}

INDEPENDENT OUTPUT:
{independent_output}

Assess the semantic drift between these two outputs.]]

local SUMMARY_SYSTEM = [[You are a pipeline integrity analyst. Summarize the cascade analysis results.

Report:
1. Which steps show significant drift
2. Whether drift is increasing through the pipeline (cascade pattern)
3. Overall pipeline reliability assessment
4. Specific recommendations for which steps need re-examination

Format:
## Cascade Analysis Summary
<brief overall assessment>

## Flagged Steps
<steps with drift above threshold, with specific concerns>

## Cascade Pattern
DETECTED: YES | NO
TREND: INCREASING | STABLE | DECREASING
DESCRIPTION: <how drift evolves through the pipeline>

## Recommendations
<specific actionable recommendations>

## Overall Risk
RISK_LEVEL: LOW | MEDIUM | HIGH | CRITICAL]]

local SUMMARY_PROMPT = [[Original task: {task}

Step-by-step drift analysis:
{drift_details}

Summarize the cascade analysis.]]

-- ─── Helpers ───

local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

local function parse_drift_score(raw)
    local score = raw:match("DRIFT_SCORE:%s*(%d*%.?%d+)")
    if score then
        return math.max(0, math.min(1, tonumber(score)))
    end
    return nil
end

local function parse_drift_type(raw)
    local dtype = raw:match("DRIFT_TYPE:%s*(%S+)")
    return dtype or "UNKNOWN"
end

local function parse_cascade_risk(raw)
    local risk = raw:match("CASCADE_RISK:%s*(%S+)")
    return risk or "UNKNOWN"
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local steps = ctx.steps or error("ctx.steps is required")
    if #steps < 1 then
        error("ctx.steps must contain at least 1 step")
    end

    local drift_threshold = ctx.drift_threshold or 0.4
    local rederive_tokens = ctx.rederive_tokens or 500
    local compare_tokens = ctx.compare_tokens or 400
    local summary_tokens = ctx.summary_tokens or 500

    alc.log("info", string.format("anti_cascade: analyzing %d steps", #steps))

    -- Phase 1: Independent re-derivation for each step (parallel)
    local independent = alc.map(steps, function(step)
        local instruction = step.instruction or step.name
        local prompt = expand(REDERIVE_PROMPT, {
            task = task,
            instruction = instruction,
        })
        return alc.llm(prompt, {
            system = REDERIVE_SYSTEM,
            max_tokens = rederive_tokens,
        })
    end)

    -- Phase 2: Compare pipeline vs independent for each step (parallel)
    local comparisons_input = {}
    for i, step in ipairs(steps) do
        comparisons_input[#comparisons_input + 1] = {
            step = step,
            independent = independent[i],
        }
    end

    local comparisons = alc.map(comparisons_input, function(item)
        local prompt = expand(COMPARE_PROMPT, {
            name = item.step.name,
            instruction = item.step.instruction or item.step.name,
            pipeline_output = item.step.output,
            independent_output = item.independent,
        })
        return alc.llm(prompt, {
            system = COMPARE_SYSTEM,
            max_tokens = compare_tokens,
        })
    end)

    -- Phase 3: Parse results and build drift profile
    local step_results = {}
    local flagged = {}
    local drift_details_lines = {}

    for i, raw in ipairs(comparisons) do
        local score = parse_drift_score(raw) or 0
        local dtype = parse_drift_type(raw)
        local risk = parse_cascade_risk(raw)

        step_results[#step_results + 1] = {
            name = steps[i].name,
            drift_score = score,
            drift_type = dtype,
            cascade_risk = risk,
            flagged = score >= drift_threshold,
            raw = raw,
        }

        if score >= drift_threshold then
            flagged[#flagged + 1] = steps[i].name
        end

        drift_details_lines[#drift_details_lines + 1] = string.format(
            "--- Step %d: %s ---\nDrift: %.2f (%s) | Risk: %s\n%s",
            i, steps[i].name, score, dtype, risk, raw
        )

        alc.log("info", string.format(
            "anti_cascade: step %s drift=%.2f type=%s risk=%s%s",
            steps[i].name, score, dtype, risk,
            score >= drift_threshold and " [FLAGGED]" or ""
        ))
    end

    -- Phase 4: Summary analysis
    local summary_prompt = expand(SUMMARY_PROMPT, {
        task = task,
        drift_details = table.concat(drift_details_lines, "\n\n"),
    })
    local summary_raw = alc.llm(summary_prompt, {
        system = SUMMARY_SYSTEM,
        max_tokens = summary_tokens,
    })

    local max_drift = 0
    for _, sr in ipairs(step_results) do
        if sr.drift_score > max_drift then
            max_drift = sr.drift_score
        end
    end

    alc.stats.record("anti_cascade_steps", #steps)
    alc.stats.record("anti_cascade_flagged", #flagged)
    alc.stats.record("anti_cascade_max_drift", max_drift)

    ctx.result = {
        step_results = step_results,
        flagged_steps = flagged,
        max_drift = max_drift,
        summary = summary_raw,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
