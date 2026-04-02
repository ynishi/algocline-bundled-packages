--- Reflect — self-critique and iterative refinement
---
--- Generate → Critique → Revise loop. The same LLM critiques
--- its own output and refines until convergence or max rounds.
---
--- Based on: Madaan et al., "Self-Refine: Iterative Refinement with
--- Self-Feedback" (2023, arXiv:2303.17651)
---
--- Usage:
---   local reflect = require("reflect")
---   return reflect.run(ctx)
---
--- ctx.task (required): The task to perform
--- ctx.initial_draft: Pre-generated draft to refine (skips initial LLM generation)
--- ctx.max_rounds: Maximum critique-revise cycles (default: 3)
--- ctx.stop_when: Stop condition — "no_major_issues" or "no_issues" (default: "no_major_issues")
--- ctx.gen_tokens: Max tokens for generation (default: 500)
--- ctx.critique_tokens: Max tokens for critique (default: 300)

local M = {}

---@type AlcMeta
M.meta = {
    name = "reflect",
    version = "0.1.0",
    description = "Self-critique loop — generate, critique, revise until convergence",
    category = "refinement",
}

local STOP_PATTERNS = {
    no_issues = { "NO_ISSUES" },
    no_major_issues = { "NO_MAJOR_ISSUES", "NO_ISSUES" },
}

--- Check if critique indicates convergence.
local function should_stop(critique, stop_when)
    local patterns = STOP_PATTERNS[stop_when] or STOP_PATTERNS.no_major_issues
    for _, pat in ipairs(patterns) do
        if critique:match(pat) then
            return true
        end
    end
    return false
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_rounds = ctx.max_rounds or 3
    local stop_when = ctx.stop_when or "no_major_issues"
    local gen_tokens = ctx.gen_tokens or 500
    local critique_tokens = ctx.critique_tokens or 300

    -- Initial generation (skip if caller provides a draft)
    local draft
    if ctx.initial_draft then
        draft = ctx.initial_draft
    else
        draft = alc.llm(
            string.format("Task: %s\n\nProvide a thorough response.", task),
            {
                system = "You are an expert. Produce a high-quality, detailed response.",
                max_tokens = gen_tokens,
            }
        )
    end

    local rounds = {}

    for i = 1, max_rounds do
        -- Critique
        local critique = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Current draft:\n%s\n\n"
                    .. "Critique this draft. Identify:\n"
                    .. "- Errors or inaccuracies\n"
                    .. "- Missing information\n"
                    .. "- Unclear or weak reasoning\n"
                    .. "- Improvements needed\n\n"
                    .. "If there are no major issues, output: NO_MAJOR_ISSUES\n"
                    .. "If the draft is excellent with no issues at all, output: NO_ISSUES",
                task, draft
            ),
            {
                system = "You are a rigorous critic. Be specific about problems "
                    .. "and what exactly needs improvement. Do not be lenient.",
                max_tokens = critique_tokens,
            }
        )

        rounds[#rounds + 1] = {
            round = i,
            critique = critique,
            converged = should_stop(critique, stop_when),
        }

        if should_stop(critique, stop_when) then
            alc.log("info", string.format("reflect: converged at round %d", i))
            break
        end

        -- Revise
        draft = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Previous draft:\n%s\n\n"
                    .. "Critique:\n%s\n\n"
                    .. "Revise the draft to address ALL issues raised in the critique. "
                    .. "Maintain what was already good.",
                task, draft, critique
            ),
            {
                system = "You are an expert reviser. Address every critique point "
                    .. "while preserving the strengths of the original.",
                max_tokens = gen_tokens,
            }
        )
    end

    ctx.result = {
        output = draft,
        rounds = rounds,
        total_rounds = #rounds,
        converged = #rounds > 0 and rounds[#rounds].converged,
    }
    return ctx
end

return M
