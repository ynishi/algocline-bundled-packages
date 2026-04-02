--- CoD — Chain-of-Density iterative compression
---
--- Iteratively rewrites text to increase information density while
--- maintaining length. Each round adds missing entities/details and
--- removes filler, producing progressively denser output.
---
--- Based on: Adams et al., "From Sparse to Dense: GPT-4 Summarization
--- with Chain of Density Prompting" (2023, arXiv:2309.04269)
---
--- Usage:
---   local cod = require("cod")
---   return cod.run(ctx)
---
--- ctx.text (required): Source text to compress
--- ctx.rounds: Number of densification rounds (default: 3)
--- ctx.target_length: Approximate target length in words (default: auto ~1/3 of input)
--- ctx.gen_tokens: Max tokens per round (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "cod",
    version = "0.1.0",
    description = "Chain-of-Density — iterative information densification with fidelity preservation",
    category = "optimization",
}

--- Rough word count.
local function word_count(text)
    local count = 0
    for _ in text:gmatch("%S+") do
        count = count + 1
    end
    return count
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local text = ctx.text or error("ctx.text is required")
    local rounds = ctx.rounds or 3
    local gen_tokens = ctx.gen_tokens or 400

    local input_words = word_count(text)
    local target_length = ctx.target_length or math.max(50, math.floor(input_words / 3))

    -- Phase 1: Initial sparse summary
    local summary = alc.llm(
        string.format(
            "Source text:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Write a summary of approximately %d words. "
                .. "Cover the main topic and 1-2 key entities. "
                .. "Keep it general — details will be added in subsequent rounds.",
            text, target_length
        ),
        {
            system = "You are a summarizer. Write a concise but readable summary. "
                .. "This is the sparse (initial) version — err on the side of being "
                .. "general rather than cramming in details.",
            max_tokens = gen_tokens,
        }
    )

    local history = {
        { round = 0, summary = summary, word_count = word_count(summary) },
    }

    -- Phase 2: Densification rounds
    for r = 1, rounds do
        summary = alc.llm(
            string.format(
                "Source text:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Current summary (round %d of %d):\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Rewrite this summary to be DENSER:\n"
                    .. "1. Identify 1-3 important entities/details MISSING from the summary\n"
                    .. "2. Add them by replacing filler phrases and less informative content\n"
                    .. "3. Keep the length approximately the same (~%d words)\n"
                    .. "4. Every word should carry information — remove vague language\n\n"
                    .. "The summary should be self-contained and readable.\n"
                    .. "Do NOT simply append — rewrite to integrate new information smoothly.",
                text, r, rounds, summary, target_length
            ),
            {
                system = "You are performing Chain-of-Density summarization. "
                    .. "Each round makes the summary denser by adding missing salient "
                    .. "entities while removing filler. Maintain readability. "
                    .. "The length should stay approximately constant.",
                max_tokens = gen_tokens,
            }
        )

        history[#history + 1] = {
            round = r,
            summary = summary,
            word_count = word_count(summary),
        }

        alc.log("info", string.format(
            "cod: round %d/%d, %d words", r, rounds, word_count(summary)
        ))
    end

    ctx.result = {
        output = summary,
        history = history,
        total_rounds = rounds,
        input_words = input_words,
        output_words = word_count(summary),
        compression_ratio = input_words > 0 and (word_count(summary) / input_words) or 0,
    }
    return ctx
end

return M
