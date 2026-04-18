--- Contrastive — learn from correct AND incorrect reasoning
--- Generates both a correct reasoning path and a plausible-but-wrong path,
--- then contrasts them to strengthen the final answer. The only strategy
--- that explicitly models failure modes.
---
--- Based on: Chia et al., "Contrastive Chain-of-Thought Prompting"
--- (2023, arXiv:2311.09277)
---
--- Usage:
---   local contrastive = require("contrastive")
---   return contrastive.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n_contrasts: Number of contrast pairs (default: 2)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "contrastive",
    version = "0.1.0",
    description = "Contrastive CoT — generate correct and incorrect reasoning, learn from contrast",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task        = T.string:describe("The problem to solve"),
                n_contrasts = T.number:is_optional():describe("Number of contrast pairs (default: 2)"),
            }),
            result = T.shape({
                answer          = T.string:describe("Final answer informed by contrast analysis"),
                contrasts       = T.array_of(T.shape({
                    wrong_reasoning = T.string:describe("Plausible-but-incorrect reasoning path"),
                    error_analysis  = T.string:describe("Analysis of the error and its correct replacement"),
                })):describe("Per-iteration wrong-reasoning + error-analysis pairs"),
                total_contrasts = T.number:describe("= #contrasts"),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_contrasts = ctx.n_contrasts or 2

    local contrasts = {}

    for i = 1, n_contrasts do
        -- Generate a plausible but INCORRECT reasoning path
        local wrong_reasoning = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Generate a plausible-sounding but INCORRECT reasoning path for this task. "
                    .. "The reasoning should contain a subtle logical error, wrong assumption, "
                    .. "or overlooked factor that leads to a wrong conclusion.\n"
                    .. "Make it convincing — the kind of mistake an expert might initially make.\n\n"
                    .. "Incorrect reasoning attempt #%d:",
                task, i
            ),
            {
                system = "You are generating intentionally flawed reasoning for educational purposes. "
                    .. "The flaw should be subtle and instructive, not obvious.",
                max_tokens = 300,
            }
        )

        -- Identify what went wrong
        local error_analysis = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "The following reasoning contains an error:\n%s\n\n"
                    .. "Identify:\n"
                    .. "1. The specific error or wrong assumption\n"
                    .. "2. Why it seems plausible (the trap)\n"
                    .. "3. What the correct reasoning should be instead",
                task, wrong_reasoning
            ),
            {
                system = "You are a rigorous analyst. Pinpoint the exact flaw and explain "
                    .. "why it's a common trap. Then provide the correct reasoning.",
                max_tokens = 300,
            }
        )

        contrasts[#contrasts + 1] = {
            wrong_reasoning = wrong_reasoning,
            error_analysis = error_analysis,
        }
    end

    -- Build contrast summary
    local contrast_text = ""
    for i, c in ipairs(contrasts) do
        contrast_text = contrast_text .. string.format(
            "Contrast %d:\n"
                .. "  WRONG path: %s\n"
                .. "  ERROR analysis: %s\n\n",
            i, c.wrong_reasoning, c.error_analysis
        )
    end

    -- Generate final answer informed by all contrasts
    local answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Before answering, review these reasoning pitfalls and their corrections:\n\n"
                .. "%s"
                .. "Now provide the CORRECT answer. Explicitly avoid the identified pitfalls. "
                .. "Show your reasoning step by step, noting where you avoid each trap.",
            task, contrast_text
        ),
        {
            system = "You are an expert who learns from mistakes. Your answer must explicitly "
                .. "navigate around the identified pitfalls. Show awareness of each trap.",
            max_tokens = 600,
        }
    )

    ctx.result = {
        answer = answer,
        contrasts = contrasts,
        total_contrasts = #contrasts,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
