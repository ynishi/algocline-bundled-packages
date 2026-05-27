--- recipe_trace — generic LLM call tracer for recipe execution
---
--- Wraps `alc.llm` before running a recipe, collects per-call trace
--- entries (prompt, response, duration, opts), then restores the
--- original function. The recipe itself is not modified — tracing is
--- fully external.
---
--- ## Usage
---
--- ```lua
--- local trace = require("recipe_trace")
--- local recipe = require("recipe_quick_vote")
--- local result = trace.run({
---     task = "What is 2+2?",
---     recipe = recipe,
---     -- all other fields forwarded to recipe.run as-is
--- })
--- -- result.trace = { calls = { {prompt, response, opts, duration_ms}, ... } }
--- ```
---
--- ## Caveats
---
--- The wrapper replaces `alc.llm` on the global `alc` table for the
--- duration of recipe.run. Recipes that capture `alc.llm` into a local
--- at load time bypass the hook — all 5 current recipe_* packages call
--- `alc.llm(...)` directly, so this is safe today. If a future recipe
--- caches the reference, the hook will miss those calls.
---
--- Trace data lives in `ctx.result.trace` alongside the recipe's own
--- result fields. The trace table is additive — it never overwrites
--- recipe output keys.

local M = {}

M.meta = {
    name        = "recipe_trace",
    version     = "0.1.0",
    category    = "adapter",
    tags        = { "trace", "logging", "recipe", "card", "eval" },
    description = "Generic LLM call tracer for recipe execution. Wraps "
        .. "alc.llm to collect per-call prompt/response/timing without "
        .. "modifying the recipe itself.",
    license     = "MIT",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {},
        extract = {},
    },
}

--- Run a recipe with LLM call tracing enabled.
---
--- Accepts the same ctx fields as the target recipe, plus `recipe`
--- (the required module table). Injects `alc.llm` wrapper, delegates
--- to `recipe.run(ctx)`, restores the original, and merges trace data
--- into `ctx.result.trace`.
---
---@param ctx table
---@return table ctx
function M.run(ctx)
    local recipe = ctx.recipe
    if not recipe then
        error("recipe_trace.run: ctx.recipe is required (pass the recipe module table)")
    end
    if type(recipe.run) ~= "function" then
        error("recipe_trace.run: ctx.recipe.run must be a function")
    end

    -- Strip adapter-specific fields before forwarding
    local recipe_ref = ctx.recipe
    ctx.recipe = nil

    local calls = {}
    local original_llm = alc.llm

    -- Install tracing wrapper
    alc.llm = function(prompt, opts)
        local t0 = os.clock()
        local response = original_llm(prompt, opts)
        local duration_ms = (os.clock() - t0) * 1000

        calls[#calls + 1] = {
            prompt      = prompt,
            response    = response,
            opts        = opts,
            duration_ms = duration_ms,
            seq         = #calls + 1,
        }

        return response
    end

    -- Run the recipe (protected to guarantee llm restore)
    local ok, err = pcall(function()
        recipe_ref.run(ctx)
    end)

    -- Restore original alc.llm unconditionally
    alc.llm = original_llm

    if not ok then
        -- Attach partial trace even on failure
        ctx.result = ctx.result or {}
        ctx.result.trace = {
            calls        = calls,
            total_calls  = #calls,
            completed    = false,
            error        = tostring(err),
        }
        error("recipe_trace: recipe.run failed: " .. tostring(err))
    end

    -- Merge trace into result
    ctx.result = ctx.result or {}

    local total_ms = 0
    for _, c in ipairs(calls) do
        total_ms = total_ms + c.duration_ms
    end

    ctx.result.trace = {
        calls          = calls,
        total_calls    = #calls,
        total_trace_ms = total_ms,
        completed      = true,
    }

    return ctx
end

--- Extract a Card-ready summary from trace data.
---
--- Takes ctx.result (with .trace attached by run()) and returns a flat
--- table suitable for Card samples row augmentation.
---
---@param result table  ctx.result from a traced run
---@return table summary
function M.extract(result)
    local trace = result.trace
    if not trace then
        return { traced = false }
    end

    local prompts = {}
    local responses = {}
    for i, c in ipairs(trace.calls) do
        prompts[i] = c.prompt
        responses[i] = c.response
    end

    return {
        traced          = true,
        total_calls     = trace.total_calls,
        total_trace_ms  = trace.total_trace_ms,
        completed       = trace.completed,
        prompts         = prompts,
        responses       = responses,
    }
end

-- Test hooks
M._internal = {
    -- exposed for spec: verify wrapper install/restore
}

return M
