--- Example: recipe_quick_vote with tracing
---
--- Runs recipe_quick_vote through recipe_trace to collect per-call
--- LLM traces, then builds a Card-ready row from the result.
---
--- Usage (via alc_run):
---   alc_run({ code = io.open("recipe_trace/examples/traced_quick_vote.lua"):read("*a") })

local trace  = require("recipe_trace")
local recipe = require("recipe_quick_vote")

local ctx = trace.run({
    task   = "What is 17 + 25? Answer with just the number.",
    recipe = recipe,
    p0 = 0.5, p1 = 0.80,
    alpha = 0.05, beta = 0.10,
    min_n = 3, max_n = 8,
    gen_tokens = 200,
})

-- Recipe result is intact
alc.log("info", string.format(
    "answer=%s outcome=%s n_samples=%d",
    tostring(ctx.result.answer),
    tostring(ctx.result.outcome),
    ctx.result.n_samples or 0
))

-- Trace data is attached
alc.log("info", string.format(
    "trace: %d calls, %.1f ms total, completed=%s",
    ctx.result.trace.total_calls,
    ctx.result.trace.total_trace_ms,
    tostring(ctx.result.trace.completed)
))

-- Build Card samples row
local row = trace.card_row(ctx.result, {
    input    = "What is 17 + 25?",
    expected = { "42" },
    name     = "addition",
    tags     = {},
})

alc.log("info", string.format(
    "card_row: response=%s, trace_calls=%d",
    row.response.text:sub(1, 50),
    row.trace.total_calls
))

return ctx
