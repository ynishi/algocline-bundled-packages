--- Example: recipe_safe_panel with tracing
---
--- Wraps recipe_safe_panel to collect per-call traces including
--- the multi-stage Condorcet + calibration pipeline.

local trace  = require("recipe_trace")
local recipe = require("recipe_safe_panel")

local ctx = trace.run({
    task   = "What is the capital of France? Answer in one word.",
    recipe = recipe,
    target = 0.90,
    gen_tokens = 150,
})

alc.log("info", string.format(
    "answer=%s confidence=%.2f panel=%d",
    tostring(ctx.result.answer),
    ctx.result.confidence or 0,
    ctx.result.panel_size or 0
))

alc.log("info", string.format(
    "trace: %d calls, %.1f ms, completed=%s",
    ctx.result.trace.total_calls,
    ctx.result.trace.total_trace_ms,
    tostring(ctx.result.trace.completed)
))

return ctx
