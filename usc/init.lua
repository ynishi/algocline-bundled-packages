--- USC — Universal Self-Consistency
---
--- Extends standard Self-Consistency (SC) to free-form generation tasks.
--- Instead of majority voting on extracted answers (which requires structured
--- answer formats), USC concatenates all candidate responses and asks the LLM
--- to select the most consistent one.
---
--- Key difference from sc:
---   sc   — extracts short answers, clusters by string similarity, majority vote.
---          Only works when answers have a canonical form (numbers, options, etc.)
---   usc  — presents all full responses to LLM, asks it to judge consistency.
---          Works on ANY task: open-ended QA, summarization, code generation, etc.
---   Mathematically, majority vote is a special case of USC where the consistency
---   function is exact string match.
---
--- Based on: Chen et al., "Universal Self-Consistency for Large Language Model
--- Generation" (ICML 2024, arXiv:2311.17311), Google DeepMind
---
--- Usage:
---   local usc = require("usc")
---   return usc.run(ctx)
---
--- ctx.task (required): The problem/question to solve
--- ctx.n: Number of candidate responses to sample (default: 5)
--- ctx.gen_tokens: Max tokens per candidate (default: 400)
--- ctx.select_tokens: Max tokens for selection response (default: 500)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "usc",
    version = "0.1.0",
    description = "Universal Self-Consistency — LLM-based consistency selection "
        .. "across free-form responses. Extends SC to open-ended tasks where "
        .. "majority vote is inapplicable.",
    category = "aggregation",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task          = T.string:describe("The problem/question to solve"),
                n             = T.number:is_optional():describe("Number of candidate responses to sample (default: 5)"),
                gen_tokens    = T.number:is_optional():describe("Max tokens per candidate (default: 400)"),
                select_tokens = T.number:is_optional():describe("Max tokens for selection response (default: 500)"),
            }),
            result = T.shape({
                selection      = T.string:describe("LLM's consistency-selection response (analysis + chosen answer content)"),
                selected_index = T.number:is_optional():describe("1-based index parsed from the selection (nil if unparseable)"),
                candidates     = T.array_of(T.string):describe("All sampled candidate responses"),
                n_sampled      = T.number:describe("Number of candidates sampled"),
            }),
        },
    },
}

--- Diversity hints to encourage different reasoning paths (shared with sc).
local DIVERSITY_HINTS = {
    "Think step by step carefully.",
    "Approach this from first principles.",
    "Consider an alternative perspective.",
    "Work backwards from the expected outcome.",
    "Break this into smaller sub-problems.",
    "Use an analogy to reason about this.",
    "Consider edge cases and exceptions first.",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n or 5
    local gen_tokens = ctx.gen_tokens or 400
    local select_tokens = ctx.select_tokens or 500

    -- Phase 1: Sample N diverse candidate responses
    local candidates = {}
    for i = 1, n do
        local hint = DIVERSITY_HINTS[((i - 1) % #DIVERSITY_HINTS) + 1]
        candidates[i] = alc.llm(
            string.format(
                "Question: %s\n\n%s Provide a thorough response.",
                task, hint
            ),
            {
                system = "You are a careful, thorough reasoner. Think through "
                    .. "the problem before answering.",
                max_tokens = gen_tokens,
            }
        )
    end

    alc.log("info", string.format("usc: %d candidates sampled", n))

    -- Phase 2: Present ALL candidates and ask LLM to select the most consistent
    local candidates_text = ""
    for i, c in ipairs(candidates) do
        candidates_text = candidates_text .. string.format(
            "=== Response %d ===\n%s\n\n", i, c
        )
    end

    local selection = alc.llm(
        string.format(
            "I asked the following question to %d independent respondents:\n\n"
                .. "Question: %s\n\n"
                .. "Here are their responses:\n\n%s"
                .. "Analyze the responses for consistency. Which response is most "
                .. "consistent with the majority of other responses? Note that "
                .. "consistency means agreement on substance, not surface wording.\n\n"
                .. "First, briefly identify the key points of agreement and "
                .. "disagreement across responses.\n"
                .. "Then, state which response number (1-%d) is most consistent "
                .. "with the overall consensus.\n"
                .. "Finally, provide the selected response's content as the final answer.",
            n, task, candidates_text, n
        ),
        {
            system = "You are an impartial judge evaluating consistency across "
                .. "multiple independent responses. Select the response that best "
                .. "represents the consensus view. Focus on substantive agreement, "
                .. "not surface-level similarity.",
            max_tokens = select_tokens,
        }
    )

    -- Extract selected index if possible
    local selected_idx = nil
    local idx_match = selection:match("Response (%d+)")
        or selection:match("response (%d+)")
        or selection:match("#(%d+)")
    if idx_match then
        selected_idx = tonumber(idx_match)
        if selected_idx and (selected_idx < 1 or selected_idx > n) then
            selected_idx = nil
        end
    end

    ctx.result = {
        selection = selection,
        selected_index = selected_idx,
        candidates = candidates,
        n_sampled = n,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
