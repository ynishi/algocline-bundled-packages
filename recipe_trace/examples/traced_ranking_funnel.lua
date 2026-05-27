--- Example: recipe_ranking_funnel with tracing
---
--- Wraps the 3-stage ranking funnel to trace per-call LLM interactions
--- across screening, pairwise comparison, and final ranking stages.

local trace  = require("recipe_trace")
local recipe = require("recipe_ranking_funnel")

local ctx = trace.run({
    task   = "Rank these programming languages by ease of learning for beginners: "
        .. "Rust, Python, JavaScript, C++",
    recipe = recipe,
    gen_tokens = 400,
})

alc.log("info", string.format(
    "trace: %d calls, %.1f ms, completed=%s",
    ctx.result.trace.total_calls,
    ctx.result.trace.total_trace_ms,
    tostring(ctx.result.trace.completed)
))

return ctx
