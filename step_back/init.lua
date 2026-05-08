--- step_back(StepBack) — abstraction-first reasoning
---
--- Instead of solving directly, first "step back" to identify the underlying
--- principle or concept, then apply that principle to solve the original
--- problem. Implements the Step-Back Prompting method (Zheng et al. 2023),
--- extended with a verification pass and optional revision round.
---
--- ## Usage
---
--- ```lua
--- local step_back = require("step_back")
--- return step_back.run({ task = "Why does ice float on water?" })
--- ```
---
--- ## Algorithm
---
--- Given a problem `task`, the pkg performs five phases:
---
--- 1. **Step-back question generation** — for each abstraction level, produce
---    a higher-level question about the underlying principle (via `alc.llm`).
--- 2. **Principle answering** — answer each step-back question to extract
---    the domain principle.
--- 3. **Principle-grounded solving** — solve `task` using the extracted
---    principles as context.
--- 4. **Verification** — check that the solution correctly applies the
---    principles; output `VERIFIED` if consistent.
--- 5. **Revision** (conditional) — if verification finds gaps, revise once.
---
--- ## Theoretical foundations
---
--- Step-Back Prompting (Zheng et al. 2023) shows that eliciting abstract
--- principles before answering specific questions improves factual accuracy
--- and reduces hallucination across multiple reasoning benchmarks. The
--- abstraction step forces the model to retrieve broader, more reliable
--- knowledge before grounding it to the specific query.
---
--- ## References
---
--- - Zheng, H., Cai, S., Huang, L., Liu, Y., Han, X., Liu, Z. (2023).
---   "Take a Step Back: Evoking Reasoning via Abstraction in Large Language
---   Models". arXiv:2310.06117.
---   https://arxiv.org/abs/2310.06117

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "step_back",
    version = "0.1.0",
    description = "Step-Back prompting — abstract the principle first, then solve from principles",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task               = T.string:describe("The problem to solve"),
                abstraction_levels = T.number:is_optional():describe("Number of abstraction rounds (default: 1)"),
                domain_hint        = T.string:is_optional():describe("Optional domain hint to guide abstraction"),
            }),
            result = T.shape({
                answer       = T.string:describe("Final answer (post-verification / post-revision)"),
                abstractions = T.array_of(T.shape({
                    level     = T.number:describe("Abstraction level index (1-based)"),
                    question  = T.string:describe("Step-back question generated for this level"),
                    principle = T.string:describe("Principle or concept answer for the step-back question"),
                })):describe("Ordered step-back Q/A per abstraction level"),
                verification = T.string:describe("Verifier output"),
                verified     = T.boolean:describe("Whether verification returned VERIFIED"),
                revised      = T.boolean:describe("Whether a revision pass was triggered"),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
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

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
