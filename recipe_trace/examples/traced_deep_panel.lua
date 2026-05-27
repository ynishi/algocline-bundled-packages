--- Example: recipe_deep_panel with tracing
---
--- Wraps the ab_mcts-powered deep panel recipe to trace the full
--- tree search + panel integration LLM calls.

local trace  = require("recipe_trace")
local recipe = require("recipe_deep_panel")

local ctx = trace.run({
    task   = "What is the sum of the first 10 prime numbers?",
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
