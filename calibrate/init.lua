--- Calibrate — confidence-gated adaptive reasoning
---
--- Asks LLM to solve a task and self-assess confidence.
--- If confidence is below threshold, escalates to a heavier
--- strategy (ensemble, panel, or custom fallback).
---
--- Based on: CISC — Confidence-Informed Self-Consistency
--- (ACL Findings 2025)
---
--- Usage:
---   local calibrate = require("calibrate")
---   return calibrate.run(ctx)        -- full gated escalation
---   return calibrate.assess(ctx)     -- confidence assessment only (1 call)
---
--- ctx.task (required): The task to solve
--- ctx.threshold: Confidence threshold 0.0-1.0 (default: 0.7) [run only]
--- ctx.fallback: Strategy on low confidence — "ensemble", "panel", "retry" (default: "ensemble") [run only]
--- ctx.fallback_opts: Options passed to fallback strategy (default: {}) [run only]
--- ctx.gen_tokens: Max tokens for initial attempt (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "calibrate",
    version = "0.2.0",
    description = "Confidence-gated reasoning — fast path when confident, escalation when not",
    category = "meta",
    result_shape = "calibrated",
}

--- Extract confidence score from LLM self-assessment.
--- Returns a number between 0.0 and 1.0.
local function parse_confidence(raw)
    -- Try decimal: "0.85" or "CONFIDENCE: 0.85"
    local decimal = raw:match("(%d+%.%d+)")
    if decimal then
        local n = tonumber(decimal)
        if n and n >= 0 and n <= 1 then return n end
    end
    -- Try percentage: "85%" or "CONFIDENCE: 85%"
    local pct = raw:match("(%d+)%%")
    if pct then
        local n = tonumber(pct)
        if n and n >= 0 and n <= 100 then return n / 100 end
    end
    -- Try integer 1-10 scale: "8/10"
    local num, denom = raw:match("(%d+)/(%d+)")
    if num and denom then
        local n, d = tonumber(num), tonumber(denom)
        if n and d and d > 0 then return math.min(n / d, 1.0) end
    end
    -- Fallback: assume low confidence to trigger escalation
    return 0.0
end

--- Self-assess only: answer + confidence in a single LLM call.
--- Returns shape `assessed` (see alc_shapes.assessed).
---
--- Use this when the caller performs its own confidence-based routing
--- (e.g. recipe_safe_panel applies a recipe-level `needs_investigation`
--- gate on the returned confidence, and does not want calibrate's own
--- threshold/escalation logic — calibrate's built-in retry does NOT
--- reassess confidence, so it cannot improve the signal such callers
--- consume).
---
--- Public contract: exactly 1 LLM call, no escalation, no threshold.
--- `M.run` delegates here for its Phase 1, guaranteeing that both
--- entry points share the same prompt and parser.
---@param ctx AlcCtx
---@return AlcCtx
function M.assess(ctx)
    local task = ctx.task or error("ctx.task is required")
    local gen_tokens = ctx.gen_tokens or 400

    local response = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Provide your answer, then assess your confidence.\n\n"
                .. "Format:\n"
                .. "ANSWER: [your response]\n"
                .. "CONFIDENCE: [0.0 to 1.0, where 1.0 = absolutely certain]",
            task
        ),
        {
            system = "You are an expert. Answer the task, then honestly assess "
                .. "how confident you are in your answer. Be well-calibrated: "
                .. "use low scores when uncertain, high scores when you have "
                .. "strong evidence.",
            max_tokens = gen_tokens,
        }
    )

    local answer = response:match("ANSWER:%s*(.-)%s*CONFIDENCE:") or response
    local conf_raw = response:match("CONFIDENCE:%s*(.+)") or ""
    local confidence = parse_confidence(conf_raw)

    alc.stats.record("initial_confidence", confidence)

    ctx.result = {
        answer = answer,
        confidence = confidence,
        total_llm_calls = 1,
    }
    require("alc_shapes").assert_dev(ctx.result, "assessed", "calibrate.assess")
    return ctx
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local threshold = ctx.threshold or 0.7
    local fallback = ctx.fallback or "ensemble"
    local fallback_opts = ctx.fallback_opts or {}
    local gen_tokens = ctx.gen_tokens or 400

    -- Phase 1: delegated to M.assess (1 LLM call, answer + confidence).
    M.assess(ctx)
    local assessed = ctx.result
    local answer = assessed.answer
    local confidence = assessed.confidence
    local total_llm_calls = assessed.total_llm_calls

    alc.log("info", string.format(
        "calibrate: confidence=%.2f, threshold=%.2f", confidence, threshold
    ))

    -- Phase 2: Accept or escalate
    if confidence >= threshold then
        ctx.result = {
            answer = answer,
            confidence = confidence,
            escalated = false,
            strategy = "direct",
            total_llm_calls = total_llm_calls,
        }
        require("alc_shapes").assert_dev(ctx.result, "calibrated", "calibrate.run/direct")
        return ctx
    end

    -- Escalate to fallback strategy
    alc.log("info", string.format("calibrate: escalating to %s", fallback))

    if fallback == "retry" then
        -- Simple retry with explicit instruction to be more careful
        local retry_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "A previous attempt had low confidence. "
                    .. "Think more carefully. Consider edge cases. "
                    .. "Provide a thorough, well-reasoned answer.",
                task
            ),
            {
                system = "You are an expert taking extra care. "
                    .. "Your initial attempt was uncertain — now reason more deeply.",
                max_tokens = gen_tokens,
            }
        )
        total_llm_calls = total_llm_calls + 1
        ctx.result = {
            answer = retry_answer,
            confidence = confidence,
            escalated = true,
            strategy = "retry",
            total_llm_calls = total_llm_calls,
        }
    elseif fallback == "panel" then
        local panel_pkg = require("panel")
        local Shapes = require("alc_shapes")
        local panel_ctx = {
            task = task,
        }
        for k, v in pairs(fallback_opts) do panel_ctx[k] = v end
        local panel_result = panel_pkg.run(panel_ctx)
        Shapes.assert(panel_result.result, "paneled", "calibrate: panel fallback")
        -- panel issues one LLM call per role plus one synthesis call.
        local panel_calls = (panel_result.result.arguments
            and (#panel_result.result.arguments + 1)) or 0
        total_llm_calls = total_llm_calls + panel_calls
        ctx.result = {
            answer = panel_result.result.synthesis,
            confidence = confidence,
            escalated = true,
            strategy = "panel",
            fallback_detail = panel_result.result,
            total_llm_calls = total_llm_calls,
        }
    else
        -- Default: ensemble
        local sc = require("sc")
        local Shapes = require("alc_shapes")
        local ens_ctx = {
            task = task,
        }
        for k, v in pairs(fallback_opts) do ens_ctx[k] = v end
        local ens_result = sc.run(ens_ctx)
        Shapes.assert(ens_result.result, "voted", "calibrate: ensemble fallback")
        total_llm_calls = total_llm_calls
            + (ens_result.result.total_llm_calls or 0)
        ctx.result = {
            answer = ens_result.result.consensus,
            confidence = confidence,
            escalated = true,
            strategy = "ensemble",
            fallback_detail = ens_result.result,
            total_llm_calls = total_llm_calls,
        }
    end

    require("alc_shapes").assert_dev(ctx.result, "calibrated", "calibrate.run/" .. fallback)
    return ctx
end

return M
