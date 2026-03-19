--- s2a — System 2 Attention: context denoising before reasoning
---
--- Strips irrelevant, distracting, or misleading information from the
--- input context, then re-answers using only the cleaned context.
--- Dramatically reduces sycophancy and distraction effects.
---
--- Based on: Weston & Sukhbaatar, "System 2 Attention (is something you
--- might need too)" (2023, Meta, arXiv:2311.11829)
---
--- Pipeline (2 LLM calls):
---   Step 1: Regenerate context — rewrite the input, removing opinions,
---           irrelevant details, and biasing language that could distract
---   Step 2: Answer — solve the task using only the denoised context
---
--- Usage:
---   local s2a = require("s2a")
---   return s2a.run(ctx)
---
--- ctx.task (required): The question or task to answer
--- ctx.context: The full (potentially noisy) context to denoise
--- ctx.gen_tokens: Max tokens per LLM call (default: 500)

local M = {}

M.meta = {
    name = "s2a",
    version = "0.1.0",
    description = "System 2 Attention — strip irrelevant context before reasoning to reduce distraction and sycophancy",
    category = "preprocessing",
}

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local context = ctx.context or ""
    local gen_tokens = ctx.gen_tokens or 500

    -- ─── Step 1: Denoise context ───
    -- Regenerate only the objective, task-relevant information
    alc.log("info", "s2a: Step 1 — denoising context")

    local denoised
    if context ~= "" then
        denoised = alc.llm(
            string.format(
                "Given the following context and question, rewrite the context "
                    .. "to include ONLY the information that is directly relevant "
                    .. "and objectively necessary to answer the question.\n\n"
                    .. "Remove:\n"
                    .. "- Opinions, sentiment, and subjective framing\n"
                    .. "- Irrelevant background details\n"
                    .. "- Biasing language or leading phrasing\n"
                    .. "- Redundant or repeated information\n\n"
                    .. "Keep:\n"
                    .. "- Facts, data, and constraints\n"
                    .. "- Definitions and specifications\n"
                    .. "- Relationships and dependencies\n\n"
                    .. "Question: %s\n\n"
                    .. "Original context:\n\"\"\"\n%s\n\"\"\"",
                task, context
            ),
            {
                system = "You are a precise information filter. Output only the "
                    .. "objectively relevant subset of the context. Do not answer "
                    .. "the question — only rewrite the context.",
                max_tokens = gen_tokens,
            }
        )
    else
        -- No external context: denoise the task itself
        denoised = alc.llm(
            string.format(
                "Rewrite the following question/task to remove any subjective "
                    .. "framing, leading language, or embedded assumptions. "
                    .. "Preserve the core question precisely.\n\n"
                    .. "Original: %s",
                task
            ),
            {
                system = "You are a precise question reformulator. Remove bias "
                    .. "and distraction. Output only the reformulated question.",
                max_tokens = 200,
            }
        )
    end

    alc.log("info", string.format(
        "s2a: context denoised (%d chars → %d chars)",
        #(context ~= "" and context or task), #denoised
    ))

    -- ─── Step 2: Answer using denoised context ───
    alc.log("info", "s2a: Step 2 — answering with denoised context")

    local prompt
    if context ~= "" then
        prompt = string.format(
            "Context:\n%s\n\nQuestion: %s\n\nAnswer based on the context above.",
            denoised, task
        )
    else
        prompt = string.format(
            "%s\n\nProvide a thorough, well-reasoned answer.",
            denoised
        )
    end

    local answer = alc.llm(prompt, {
        system = "You are an expert. Answer accurately based on the provided "
            .. "information. Do not introduce assumptions beyond what is given.",
        max_tokens = gen_tokens,
    })

    alc.log("info", "s2a: complete")

    ctx.result = {
        answer = answer,
        denoised_context = denoised,
        original_context_length = #(context ~= "" and context or task),
        denoised_context_length = #denoised,
    }
    return ctx
end

return M
