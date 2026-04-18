--- CoT — iterative chain-of-thought reasoning
---
--- Builds a reasoning chain step by step, then synthesizes the chain
--- into a single coherent conclusion.
---
--- ## Usage
---
--- ```lua
--- local cot = require("cot")
--- return cot.run({ task = "Why is the sky blue?", depth = 3 })
--- ```
---
--- ## Behavior
---
--- For each step `i` in `1..depth`, the LLM is asked for the next key
--- insight conditional on all prior insights. After the last step, a
--- final synthesis prompt collapses the chain into `result.conclusion`.
---
--- Each `alc.llm` call is capped at 200 tokens for the chain steps and
--- 500 tokens for the synthesis.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name        = "cot",
    version     = "0.1.0",
    description = "Iterative chain-of-thought — cumulative reasoning steps, then synthesis",
    category    = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task  = T.string:describe("The question or task to reason about"),
                depth = T.number:is_optional():describe("Number of reasoning steps (default: 3)"),
            }),
            result = T.shape({
                chain      = T.array_of(T.string):describe("Ordered insights, one per reasoning step"),
                conclusion = T.string:describe("Synthesized final answer"),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local depth = ctx.depth or 3

    local chain = {}

    for i = 1, depth do
        local prompt
        if i == 1 then
            prompt = string.format(
                "Task: %s\n\nThink step by step. What is the first key insight? 1-2 sentences.",
                task
            )
        else
            local prev = ""
            for j, t in ipairs(chain) do
                prev = prev .. string.format("Step %d: %s\n", j, t)
            end
            prompt = string.format(
                "Task: %s\n\nReasoning so far:\n%s\n\nWhat is the next key insight? Build on previous reasoning. 1-2 sentences.",
                task, prev
            )
        end

        chain[#chain + 1] = alc.llm(prompt, {
            system = "You are a deep thinker. Each step should reveal a new insight.",
            max_tokens = 200,
        })
    end

    -- Final synthesis
    local all = ""
    for i, t in ipairs(chain) do
        all = all .. string.format("Step %d: %s\n", i, t)
    end

    local conclusion = alc.llm(
        string.format(
            "Task: %s\n\nReasoning chain:\n%s\n\nSynthesize into a clear, comprehensive answer.",
            task, all
        ),
        { system = "You are an expert synthesizer. Be thorough but concise.", max_tokens = 500 }
    )

    ctx.result = {
        chain = chain,
        conclusion = conclusion,
    }
    return ctx
end

return M
