--- orch_escalate — Cascade Escalation Orchestration
--- Start with lightest strategy, escalate to heavier ones if quality
--- is insufficient. Minimizes cost for easy tasks, guarantees quality
--- for hard ones.
---
--- Based on Cascade Escalation (Microsoft + DAAO cost optimization).
---
--- Usage:
---   local orch = require("orch_escalate")
---   return orch.run(ctx)
---
--- ctx.task    (required): Task description
--- ctx.levels  (optional): Custom escalation chain [{name, prompt_template|multi_phase, threshold, ...}]
--- ctx.on_fail (optional): "error" | "partial" (default: "partial")

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "orch_escalate",
    version = "0.1.0",
    description = "Cascade escalation: start with lightest strategy, "
        .. "escalate to heavier ones if quality is insufficient. "
        .. "Minimizes cost for easy tasks, guarantees quality for hard ones. "
        .. "Based on Cascade Escalation (Microsoft + DAAO cost optimization).",
    category = "orchestration",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task    = T.string:describe("Task description"),
                levels  = T.array_of(T.any):is_optional()
                    :describe("Custom escalation chain [{name, prompt_template|multi_phase, threshold, ...}]"),
                on_fail = T.string:is_optional()
                    :describe("\"error\" | \"partial\" (default: \"partial\")"),
            }),
            result = T.shape({
                status           = T.string
                    :describe("\"completed\" / \"failed\" / \"partial\""),
                selected_level   = T.string
                    :describe("Level name whose output was returned (best effort on exhaustion)"),
                escalation_depth = T.number
                    :describe("1-based index of the level that produced the selected output"),
                output           = T.string
                    :describe("Final selected output text"),
                score            = T.number
                    :describe("Evaluator score (1-10) of the selected output"),
                levels           = T.array_of(T.shape({
                    name          = T.string:describe("Level name"),
                    output        = T.string:describe("Level's final output"),
                    phase_outputs = T.array_of(T.string):is_optional()
                        :describe("Multi-phase intermediate outputs (absent for single-prompt levels)"),
                    score         = T.number:describe("Evaluator score"),
                    threshold     = T.number:describe("Required score to pass at this level"),
                    passed        = T.boolean:describe("score >= threshold"),
                    feedback      = T.string:describe("Evaluator's feedback / parse failure hint"),
                })):describe("Per-level execution record (up to escalation_depth)"),
                total_llm_calls  = T.number:describe("Total LLM invocations"),
            }),
        },
    },
}

local EVAL_SYSTEM = [[You are a quality evaluator for software engineering outputs.
Score on a scale of 1-10:
- Correctness (solves the task?)
- Completeness (covers all requirements?)
- Quality (clean, well-structured?)
Respond with ONLY JSON: {"score": N, "passed": true, "feedback": "what's missing"}]]

-- Default escalation chain.
-- Thresholds are intentionally descending (quick=8 > structured=7 > thorough=6):
-- lighter strategies must meet a higher bar to accept, while heavier strategies
-- are allowed to pass with a lower score since they already represent max effort.
local DEFAULT_LEVELS = {
    {
        name = "quick",
        description = "Single-shot direct answer",
        prompt_template = "Solve directly:\n\n{task}",
        system = "You are a senior developer. Give a direct, complete answer.",
        max_tokens = 2000,
        threshold = 8,
    },
    {
        name = "structured",
        description = "Chain-of-thought with self-review",
        prompt_template = "Previous attempt (score below threshold):\n{prev_output}\n\n"
            .. "Feedback: {feedback}\n\n"
            .. "Solve with step-by-step reasoning:\n\n{task}",
        system = "You are a senior developer. Think step by step. Review your own work before finalizing.",
        max_tokens = 3000,
        threshold = 7,
    },
    {
        name = "thorough",
        description = "Multi-phase: plan, implement, critique, revise",
        multi_phase = true,
        phases = {
            {
                prompt = "Plan a solution for:\n{task}\n\nPrevious attempts:\n{prev_output}\n\nFeedback: {feedback}",
                system = "You are a software architect.",
            },
            {
                prompt = "Implement based on this plan:\n{prev_phase_output}",
                system = "You are a senior developer.",
            },
            {
                prompt = "Critique this implementation:\n{prev_phase_output}\n\nOriginal task: {task}",
                system = "You are a harsh code reviewer. Find all issues.",
            },
            {
                prompt = "Revise based on critique:\n{prev_phase_output}\n\nOriginal implementation:\n{phase_2_output}",
                system = "You are a senior developer. Address all critique points.",
            },
        },
        max_tokens = 4000,
        threshold = 6,
    },
}

--- Expand template variables.
local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

--- Parse JSON from a potentially noisy LLM response.
local function parse_json(raw)
    local ok, decoded = pcall(alc.json_decode, raw)
    if ok and type(decoded) == "table" then
        return decoded
    end
    local json_str = raw:match("%b{}")
    if json_str then
        local ok2, decoded2 = pcall(alc.json_decode, json_str)
        if ok2 and type(decoded2) == "table" then
            return decoded2
        end
    end
    return nil
end

--- Evaluate output quality against threshold.
local function evaluate(output, task, threshold)
    local raw = alc.llm(
        string.format("Task: %s\n\nOutput:\n%s\n\nThreshold: %d/10", task, output, threshold),
        { system = EVAL_SYSTEM, max_tokens = 100 }
    )
    local parsed = parse_json(raw)
    if parsed then
        local score = tonumber(parsed.score) or 5
        return {
            score = score,
            passed = score >= threshold,
            feedback = parsed.feedback or "",
        }
    end
    return { score = 5, passed = false, feedback = "Evaluation parse failed" }
end

--- Execute multi-phase level (thorough level).
local function execute_multi_phase(level, task, prev_output, feedback)
    local phase_outputs = {}
    local prev_phase = ""
    local llm_calls = 0

    for i, phase in ipairs(level.phases) do
        local vars = {
            task = task,
            prev_output = prev_output or "",
            feedback = feedback or "",
            prev_phase_output = prev_phase,
        }
        -- Add phase_N_output variables
        for j, po in ipairs(phase_outputs) do
            vars["phase_" .. j .. "_output"] = po
        end

        local prompt = expand(phase.prompt, vars)
        local out = alc.llm(prompt, {
            system = phase.system,
            max_tokens = level.max_tokens or 3000,
        })
        llm_calls = llm_calls + 1
        phase_outputs[i] = out
        prev_phase = out
    end

    return prev_phase, phase_outputs, llm_calls
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local levels = ctx.levels or DEFAULT_LEVELS
    local on_fail = ctx.on_fail or "partial"

    local total_llm_calls = 0
    local level_results = {}
    local prev_output = ""
    local feedback = ""
    local best = { score = 0, output = "", level = "" }

    for level_idx, level in ipairs(levels) do
        alc.log("info", string.format(
            "escalate: level %d/%d [%s] (threshold: %d)",
            level_idx, #levels, level.name, level.threshold
        ))

        local output
        local phase_outputs

        if level.multi_phase then
            local calls
            output, phase_outputs, calls = execute_multi_phase(
                level, task, prev_output, feedback
            )
            total_llm_calls = total_llm_calls + calls
        else
            local prompt = expand(level.prompt_template, {
                task = task,
                prev_output = prev_output,
                feedback = feedback,
            })
            output = alc.llm(prompt, {
                system = level.system,
                max_tokens = level.max_tokens or 2000,
            })
            total_llm_calls = total_llm_calls + 1
        end

        -- Quality evaluation
        local eval_result = evaluate(output, task, level.threshold)
        total_llm_calls = total_llm_calls + 1

        level_results[#level_results + 1] = {
            name = level.name,
            output = output,
            phase_outputs = phase_outputs,
            score = eval_result.score,
            threshold = level.threshold,
            passed = eval_result.passed,
            feedback = eval_result.feedback,
        }

        -- Update best
        if eval_result.score > best.score then
            best = {
                score = eval_result.score,
                output = output,
                level = level.name,
            }
        end

        if eval_result.passed then
            alc.log("info", string.format(
                "escalate: [%s] PASSED (score %d >= threshold %d)",
                level.name, eval_result.score, level.threshold
            ))

            ctx.result = {
                status = "completed",
                selected_level = level.name,
                escalation_depth = level_idx,
                output = output,
                score = eval_result.score,
                levels = level_results,
                total_llm_calls = total_llm_calls,
            }
            return ctx
        end

        -- Escalate: pass feedback to next level
        alc.log("info", string.format(
            "escalate: [%s] BELOW threshold (score %d < %d), escalating",
            level.name, eval_result.score, level.threshold
        ))
        prev_output = output
        feedback = eval_result.feedback
    end

    -- All levels exhausted: return best effort
    alc.log("warn", "escalate: all levels exhausted, returning best effort")

    ctx.result = {
        status = (on_fail == "error") and "failed" or "partial",
        selected_level = best.level,
        escalation_depth = #levels,
        output = best.output,
        score = best.score,
        levels = level_results,
        total_llm_calls = total_llm_calls,
    }

    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
