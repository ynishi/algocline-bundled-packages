--- Least-to-Most — progressive subproblem decomposition
--- Decomposes a complex problem into subproblems ordered from simplest to
--- most complex, then solves each in sequence, using previous solutions
--- as context for the next.
---
--- Based on: Zhou et al., "Least-to-Most Prompting Enables Complex Reasoning
--- in Large Language Models" (2022, arXiv:2205.10625)
---
--- Usage:
---   local ltm = require("least_to_most")
---   return ltm.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.max_subproblems: Maximum number of subproblems (default: 5)

local M = {}

---@type AlcMeta
M.meta = {
    name = "least_to_most",
    version = "0.1.0",
    description = "Least-to-Most — decompose into ordered subproblems, solve simplest first, build up",
    category = "reasoning",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_sub = ctx.max_subproblems or 5

    -- Phase 1: Decompose into ordered subproblems (simplest first)
    local decomposition = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Decompose this into subproblems, ordered from SIMPLEST to MOST COMPLEX.\n"
                .. "Each subproblem should:\n"
                .. "- Be self-contained enough to solve independently (given prior answers)\n"
                .. "- Build toward the final answer\n"
                .. "- Be ordered so later problems can use earlier solutions\n\n"
                .. "List up to %d subproblems. Format:\n"
                .. "1. [simplest subproblem]\n"
                .. "2. [next subproblem]\n"
                .. "...\n"
                .. "N. [most complex / final subproblem]",
            task, max_sub
        ),
        {
            system = "You are an expert at problem decomposition. Order subproblems "
                .. "so each builds on the previous. The simplest must come first.",
            max_tokens = 400,
        }
    )

    -- Parse subproblems
    local subproblems = {}
    for line in decomposition:gmatch("[^\n]+") do
        local sub = line:match("^%d+%.%s*(.+)")
        if sub and #sub > 5 then
            subproblems[#subproblems + 1] = sub
        end
    end

    -- Fallback: if parsing failed, treat entire decomposition as guidance
    if #subproblems == 0 then
        alc.log("warn", "least_to_most: subproblem parsing failed, using single-pass fallback")
        subproblems = { task }
    end

    alc.log("info", string.format("least_to_most: decomposed into %d subproblems", #subproblems))

    -- Phase 2: Solve each subproblem sequentially, building context
    local solutions = {}
    local accumulated_context = ""

    for i, sub in ipairs(subproblems) do
        local prompt
        if i == 1 then
            prompt = string.format(
                "Original task: %s\n\n"
                    .. "Subproblem %d/%d (simplest): %s\n\n"
                    .. "Solve this subproblem.",
                task, i, #subproblems, sub
            )
        else
            prompt = string.format(
                "Original task: %s\n\n"
                    .. "Previously solved:\n%s\n"
                    .. "Subproblem %d/%d: %s\n\n"
                    .. "Using the solutions above as context, solve this subproblem.",
                task, accumulated_context, i, #subproblems, sub
            )
        end

        local solution = alc.llm(prompt, {
            system = "You are a methodical problem solver. Use all available context from "
                .. "previously solved subproblems. Be precise and thorough.",
            max_tokens = 400,
        })

        solutions[#solutions + 1] = {
            subproblem = sub,
            solution = solution,
        }

        accumulated_context = accumulated_context .. string.format(
            "  [%d] %s → %s\n", i, sub, solution
        )
    end

    -- Phase 3: Synthesize final answer from all solutions
    local synthesis = alc.llm(
        string.format(
            "Original task: %s\n\n"
                .. "Subproblem solutions (from simplest to most complex):\n%s\n"
                .. "Synthesize all solutions into a comprehensive final answer.",
            task, accumulated_context
        ),
        {
            system = "You are an expert synthesizer. Combine the progressive solutions "
                .. "into a coherent, complete answer.",
            max_tokens = 600,
        }
    )

    ctx.result = {
        answer = synthesis,
        subproblems = solutions,
        total_subproblems = #subproblems,
    }
    return ctx
end

return M
