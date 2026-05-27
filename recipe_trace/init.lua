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
        card_row = {},
        civic_merge = {},
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

--- Build a Card samples row from a traced recipe result.
---
--- Combines the recipe's own result fields with trace summary into a
--- flat row suitable for Card JSONL sidecar. The `case` field follows
--- the evalframe convention (input/expected/name/tags).
---
---@param result table   ctx.result from a traced run
---@param case   table   {input=string, expected=string[], name=string, tags={}}
---@param opts   table?  {include_prompts=bool, include_responses=bool, max_prompt_len=int}
---@return table row     Card samples row
function M.card_row(result, case, opts)
    opts = opts or {}
    local include_prompts   = opts.include_prompts ~= false
    local include_responses = opts.include_responses ~= false
    local max_prompt_len    = opts.max_prompt_len or 500

    local trace = result.trace or {}
    local calls = trace.calls or {}

    local call_summaries = {}
    for i, c in ipairs(calls) do
        local entry = {
            seq         = c.seq,
            duration_ms = c.duration_ms,
        }
        if include_prompts then
            local p = c.prompt or ""
            entry.prompt = (#p > max_prompt_len)
                and p:sub(1, max_prompt_len) .. "..."
                or p
        end
        if include_responses then
            entry.response = c.response
        end
        call_summaries[i] = entry
    end

    return {
        case = case,
        response = {
            text       = tostring(result.answer or ""),
            model      = "algocline:traced",
            latency_ms = trace.total_trace_ms or 0,
        },
        trace = {
            total_calls    = trace.total_calls or 0,
            total_trace_ms = trace.total_trace_ms or 0,
            completed      = trace.completed or false,
            calls          = call_summaries,
        },
    }
end

--- Merge civic state snapshots into trace data.
---
--- For recipes that use civic primitives (slot_table, scalar_pool,
--- lineage, etc.), this function attaches civic observable state to
--- the trace. Call after M.run() completes.
---
---@param result table          ctx.result (with .trace from M.run)
---@param civic_state table     { slots=table?, pool=table?, lineage=table?, ledger=table? }
---@return table result         same result with .trace.civic merged
function M.civic_merge(result, civic_state)
    if not result.trace then
        return result
    end

    local civic = {}

    if civic_state.slots then
        local snapshot = {}
        local st = civic_state.slots
        for idx = 1, st:size() do
            snapshot[idx] = st:get(idx)
        end
        civic.slots = snapshot
    end

    if civic_state.pool then
        local pool = civic_state.pool
        local scores = {}
        for idx = 1, (civic_state.pool_size or 0) do
            scores[idx] = { idx = idx, total = pool:total(idx) }
        end
        civic.scores = scores
    end

    if civic_state.lineage then
        civic.lineage_edges = civic_state.lineage:edges()
    end

    if civic_state.ledger then
        civic.transactions = civic_state.ledger:transactions()
        civic.ledger_total = civic_state.ledger:total()
    end

    if civic_state.gen_history then
        civic.gen_history = civic_state.gen_history
    end

    result.trace.civic = civic
    return result
end

-- Test hooks
M._internal = {
    -- exposed for spec: verify wrapper install/restore
}

return M
