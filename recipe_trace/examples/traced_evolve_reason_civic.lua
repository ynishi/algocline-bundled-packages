--- Example: recipe_evolve_reason with tracing + civic state merge
---
--- Demonstrates the full pipeline: trace LLM calls during evolutionary
--- reasoning, then merge civic primitive state (slot_table, scalar_pool,
--- lineage) into the trace for Card/Eval consumption.
---
--- This example shows how civic internals remain pure while trace
--- captures both the LLM interaction layer and the civic state layer.

local trace  = require("recipe_trace")
local recipe = require("recipe_evolve_reason")

local ctx = trace.run({
    task     = "Explain why the sky is blue in exactly 3 sentences.",
    recipe   = recipe,
    pop_size = 4,
    max_gen  = 2,
    elite_ratio = 0.5,
    gen_tokens  = 400,
})

-- Recipe result
alc.log("info", string.format(
    "best_idx=%d best_score=%.1f generations=%d",
    ctx.result.best_idx or 0,
    ctx.result.best_score or 0,
    ctx.result.generations or 0
))

-- Trace data
alc.log("info", string.format(
    "trace: %d LLM calls, %.1f ms, completed=%s",
    ctx.result.trace.total_calls,
    ctx.result.trace.total_trace_ms,
    tostring(ctx.result.trace.completed)
))

-- Civic state merge (from recipe result fields)
-- recipe_evolve_reason exposes gen_history and lineage_edges in result
if ctx.result.gen_history then
    trace.civic_merge(ctx.result, {
        gen_history = ctx.result.gen_history,
    })
    alc.log("info", string.format(
        "civic merge: gen_history=%d generations",
        #ctx.result.trace.civic.gen_history
    ))
end

-- Build Card row with civic-enriched trace
local row = trace.card_row(ctx.result, {
    input    = "Explain why the sky is blue in exactly 3 sentences.",
    expected = {},
    name     = "sky_blue_evolve",
    tags     = { "evolve", "civic" },
}, { max_prompt_len = 300 })

alc.log("info", string.format(
    "card_row: trace_calls=%d, has_civic=%s",
    row.trace.total_calls,
    tostring(ctx.result.trace.civic ~= nil)
))

return ctx
