--- Decompose — task decomposition and parallel sub-task execution
---
--- Breaks a complex task into sub-tasks via LLM, executes each
--- in parallel, then merges results into a unified answer.
---
--- Based on: TDAG (2025), HiPlan (2025), Agent-Oriented Planning
---
--- Usage:
---   local decompose = require("decompose")
---   return decompose.run(ctx)
---
--- ctx.task (required): The complex task to decompose
--- ctx.max_subtasks: Maximum sub-tasks to generate (default: 5)
--- ctx.subtask_tokens: Max tokens per sub-task (default: 400)
--- ctx.merge_tokens: Max tokens for final merge (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "decompose",
    version = "0.1.0",
    description = "Task decomposition — LLM-driven split, parallel execution, merge",
    category = "planning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task           = T.string:describe("The complex task to decompose"),
                max_subtasks   = T.number:is_optional():describe("Maximum sub-tasks to generate (default: 5)"),
                subtask_tokens = T.number:is_optional():describe("Max tokens per sub-task (default: 400)"),
                merge_tokens   = T.number:is_optional():describe("Max tokens for final merge (default: 600)"),
            }),
            result = T.shape({
                answer            = T.string:describe("Unified merged answer across sub-tasks"),
                subtasks          = T.array_of(T.string):describe("Parsed sub-task descriptions (fallback: single-element = original task)"),
                subtask_results   = T.array_of(T.string):describe("Per-sub-task LLM outputs, same order as subtasks"),
                decomposition_raw = T.string:describe("Raw decomposition LLM output before parsing"),
            }),
        },
    },
}

--- Parse sub-tasks from LLM output.
--- Expects numbered list: "1. ...\n2. ...\n"
local function parse_subtasks(raw, max)
    local tasks = {}
    for line in raw:gmatch("[^\n]+") do
        local num, desc = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if desc and #tasks < max then
            tasks[#tasks + 1] = desc:match("^%s*(.-)%s*$")
        end
    end
    return tasks
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_subtasks = ctx.max_subtasks or 5
    local subtask_tokens = ctx.subtask_tokens or 400
    local merge_tokens = ctx.merge_tokens or 600

    -- Phase 1: Decompose
    local decomposition = alc.llm(
        string.format(
            "Complex task:\n%s\n\n"
                .. "Break this into %d or fewer independent sub-tasks. "
                .. "Each sub-task should be self-contained and answerable on its own. "
                .. "Order by logical dependency (independent tasks first).\n\n"
                .. "Output a numbered list:\n"
                .. "1. [sub-task description]\n"
                .. "2. [sub-task description]\n...",
            task, max_subtasks
        ),
        {
            system = "You are an expert task planner. Decompose into sub-tasks that are: "
                .. "(1) self-contained, (2) collectively exhaustive, (3) non-overlapping. "
                .. "Each sub-task should produce a concrete, useful partial result.",
            max_tokens = 300,
        }
    )

    local subtasks = parse_subtasks(decomposition, max_subtasks)

    if #subtasks == 0 then
        -- Fallback: treat as single task
        subtasks = { task }
    end

    alc.log("info", string.format("decompose: %d sub-tasks", #subtasks))

    -- Phase 2: Execute sub-tasks in parallel
    local results = alc.map(subtasks, function(subtask, i)
        return alc.llm(
            string.format(
                "You are working on part of a larger task.\n\n"
                    .. "Overall goal: %s\n\n"
                    .. "Your specific sub-task (%d of %d): %s\n\n"
                    .. "Provide a thorough, self-contained answer for this sub-task.",
                task, i, #subtasks, subtask
            ),
            {
                system = "You are a focused specialist. Solve only the assigned sub-task "
                    .. "thoroughly. Be specific and detailed.",
                max_tokens = subtask_tokens,
            }
        )
    end)

    -- Phase 3: Merge
    local parts = ""
    for i, subtask in ipairs(subtasks) do
        parts = parts .. string.format(
            "## Sub-task %d: %s\n%s\n\n",
            i, subtask, results[i]
        )
    end

    local merged = alc.llm(
        string.format(
            "Overall task: %s\n\n"
                .. "Sub-task results:\n\n%s\n"
                .. "Merge these results into a unified, coherent response. "
                .. "Resolve any inconsistencies between sub-tasks. "
                .. "Ensure completeness — nothing from the sub-results should be lost.",
            task, parts
        ),
        {
            system = "You are an expert integrator. Synthesize partial results "
                .. "into a complete, well-structured answer. "
                .. "Eliminate redundancy while preserving all unique contributions.",
            max_tokens = merge_tokens,
        }
    )

    ctx.result = {
        answer = merged,
        subtasks = subtasks,
        subtask_results = results,
        decomposition_raw = decomposition,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
