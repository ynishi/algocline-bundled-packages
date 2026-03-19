--- plan_solve — Plan-and-Solve prompting
---
--- Devises an explicit step-by-step plan before execution, then carries
--- out each step sequentially. More structured than Chain-of-Thought,
--- lighter than full decompose (no parallel subtask dispatch).
---
--- Based on: Wang et al., "Plan-and-Solve Prompting: Improving Zero-Shot
--- Chain-of-Thought Reasoning by Large Language Models" (2023, arXiv:2305.04091)
---
--- Pipeline (2-3 LLM calls):
---   Step 1: Plan     — devise a numbered plan of reasoning steps
---   Step 2: Execute  — carry out the plan step by step
---   Step 3: Extract  — (optional) extract concise final answer
---
--- Usage:
---   local plan_solve = require("plan_solve")
---   return plan_solve.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.extract: Whether to extract a concise answer (default: true)
--- ctx.plan_tokens: Max tokens for plan generation (default: 300)
--- ctx.solve_tokens: Max tokens for execution (default: 500)

local M = {}

M.meta = {
    name = "plan_solve",
    version = "0.1.0",
    description = "Plan-and-Solve — devise an explicit plan, then execute step by step",
    category = "reasoning",
}

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local extract = ctx.extract
    if extract == nil then extract = true end
    local plan_tokens = ctx.plan_tokens or 300
    local solve_tokens = ctx.solve_tokens or 500

    -- ─── Step 1: Plan ───
    alc.log("info", "plan_solve: Step 1 — devising plan")

    local plan = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Before solving, devise a step-by-step plan.\n\n"
                .. "Requirements for the plan:\n"
                .. "- Number each step\n"
                .. "- Each step should be a concrete, actionable reasoning operation\n"
                .. "- Pay attention to intermediate variables and calculations\n"
                .. "- Include a final step that synthesizes the answer\n\n"
                .. "Output ONLY the numbered plan, no solutions yet.",
            task
        ),
        {
            system = "You are a methodical problem solver. Create a clear, "
                .. "complete plan before solving. Each step should be specific "
                .. "enough that it can be executed unambiguously.",
            max_tokens = plan_tokens,
        }
    )

    -- Count plan steps
    local step_count = 0
    for _ in plan:gmatch("\n?%s*%d+[%.%)]") do
        step_count = step_count + 1
    end

    alc.log("info", string.format(
        "plan_solve: plan devised (%d steps)", step_count
    ))

    -- ─── Step 2: Execute ───
    alc.log("info", "plan_solve: Step 2 — executing plan")

    local execution = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Follow this plan exactly, executing each step and showing "
                .. "your work:\n\n%s\n\n"
                .. "Execute each step now. Show intermediate results for every step. "
                .. "At the end, state your final answer clearly.",
            task, plan
        ),
        {
            system = "You are a precise executor. Follow the plan step by step. "
                .. "Show all intermediate calculations and reasoning. "
                .. "Do not skip steps or deviate from the plan.",
            max_tokens = solve_tokens,
        }
    )

    alc.log("info", "plan_solve: execution complete")

    -- ─── Step 3: Extract (optional) ───
    local final_answer = execution
    if extract then
        alc.log("info", "plan_solve: Step 3 — extracting concise answer")

        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Full solution:\n%s\n\n"
                    .. "Extract the final answer concisely. Include the key "
                    .. "conclusion and any important caveats, but omit the "
                    .. "step-by-step derivation.",
                task, execution
            ),
            {
                system = "Extract the final answer. Be concise but complete.",
                max_tokens = 200,
            }
        )
    end

    ctx.result = {
        answer = final_answer,
        plan = plan,
        execution = execution,
        plan_steps = step_count,
    }
    return ctx
end

return M
