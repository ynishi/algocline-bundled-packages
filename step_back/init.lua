--- Step-Back — abstraction-first reasoning
--- Instead of solving directly, first "step back" to identify the underlying
--- principle or concept, then apply that principle to solve the original problem.
---
--- Based on: Zheng et al., "Take a Step Back: Evoking Reasoning via
--- Abstraction in Large Language Models" (2023, arXiv:2310.06117)
---
--- Usage:
---   local step_back = require("step_back")
---   return step_back.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.abstraction_levels: Number of abstraction rounds (default: 1)
--- ctx.domain_hint: Optional domain hint to guide abstraction

local M = {}

M.meta = {
    name = "step_back",
    version = "0.1.0",
    description = "Step-Back prompting — abstract the principle first, then solve from principles",
    category = "reasoning",
}

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local levels = ctx.abstraction_levels or 1
    local domain_hint = ctx.domain_hint or nil

    local abstractions = {}

    -- Phase 1: Step back — extract underlying principles
    for i = 1, levels do
        local target
        if i == 1 then
            target = task
        else
            target = abstractions[i - 1].question
        end

        local domain_context = ""
        if domain_hint and i == 1 then
            domain_context = string.format(" (Domain: %s)", domain_hint)
        end

        -- Generate the step-back question
        local step_back_question = alc.llm(
            string.format(
                "Original question: %s%s\n\n"
                    .. "Instead of answering directly, step back and ask a more general question "
                    .. "about the underlying principle, concept, or mechanism. "
                    .. "What higher-level question should we answer first to solve this?\n\n"
                    .. "Reply with ONLY the step-back question.",
                target, domain_context
            ),
            {
                system = "You are an expert at abstraction. Identify the fundamental principle "
                    .. "behind a specific question. The step-back question should be broader "
                    .. "and get at the root concept.",
                max_tokens = 150,
            }
        )

        -- Answer the step-back question
        local principle = alc.llm(
            string.format(
                "Question: %s\n\n"
                    .. "Provide a thorough, factual answer to this question. "
                    .. "Focus on principles, mechanisms, and general rules.",
                step_back_question
            ),
            {
                system = "You are a domain expert. Provide accurate, comprehensive knowledge "
                    .. "about the underlying principle. Be precise and factual.",
                max_tokens = 400,
            }
        )

        abstractions[#abstractions + 1] = {
            level = i,
            question = step_back_question,
            principle = principle,
        }

        alc.log("info", string.format(
            "step_back: level %d — abstracted", i
        ))
    end

    -- Phase 2: Solve with principles as context
    local principles_text = ""
    for i = #abstractions, 1, -1 do
        local a = abstractions[i]
        principles_text = principles_text .. string.format(
            "Principle (level %d):\n  Q: %s\n  A: %s\n\n",
            a.level, a.question, a.principle
        )
    end

    local solution = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Before answering, review these underlying principles:\n\n"
                .. "%s"
                .. "Now, apply these principles to solve the original task. "
                .. "Ground your reasoning in the principles above.",
            task, principles_text
        ),
        {
            system = "You are an expert problem solver. Use the provided principles "
                .. "as your foundation. Connect abstract knowledge to the specific problem.",
            max_tokens = 600,
        }
    )

    -- Phase 3: Verify alignment between principles and solution
    local verification = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Principles:\n%s"
                .. "Proposed solution:\n%s\n\n"
                .. "Verify: Does the solution correctly apply the principles? "
                .. "Are there any gaps or misapplications? "
                .. "If the solution is correct, output VERIFIED. "
                .. "If not, explain what needs correction.",
            task, principles_text, solution
        ),
        {
            system = "You are a rigorous verifier. Check logical consistency between "
                .. "principles and their application.",
            max_tokens = 300,
        }
    )

    -- If verification found issues, revise once
    local final_answer = solution
    local revised = false
    if not verification:match("VERIFIED") then
        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Principles:\n%s"
                    .. "Previous solution:\n%s\n\n"
                    .. "Verification feedback:\n%s\n\n"
                    .. "Revise the solution to address the verification feedback. "
                    .. "Maintain alignment with the principles.",
                task, principles_text, solution, verification
            ),
            {
                system = "You are an expert reviser. Fix the identified issues while "
                    .. "staying grounded in the principles.",
                max_tokens = 600,
            }
        )
        revised = true
    end

    ctx.result = {
        answer = final_answer,
        abstractions = abstractions,
        verification = verification,
        verified = verification:match("VERIFIED") ~= nil,
        revised = revised,
    }
    return ctx
end

return M
