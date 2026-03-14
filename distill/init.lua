--- Distill — MapReduce summarization and extraction
---
--- Splits large text into chunks, processes each in parallel,
--- then reduces into a unified result.
---
--- Based on: LLM×MapReduce (2024, arXiv:2410.09342)
---
--- Usage:
---   local distill = require("distill")
---   return distill.run(ctx)
---
--- ctx.text (required): Source text to process
--- ctx.goal: What to extract/summarize (default: "Summarize the key points")
--- ctx.chunk_size: Lines per chunk (default: 100)
--- ctx.chunk_overlap: Overlap lines between chunks (default: 5)
--- ctx.map_tokens: Max tokens per map call (default: 300)
--- ctx.reduce_tokens: Max tokens for final reduce (default: 600)

local M = {}

M.meta = {
    name = "distill",
    version = "0.1.0",
    description = "MapReduce summarization — parallel chunk processing with unified reduction",
    category = "extraction",
}

function M.run(ctx)
    local text = ctx.text or error("ctx.text is required")
    local goal = ctx.goal or "Summarize the key points"
    local chunk_size = ctx.chunk_size or 100
    local chunk_overlap = ctx.chunk_overlap or 5
    local map_tokens = ctx.map_tokens or 300
    local reduce_tokens = ctx.reduce_tokens or 600

    -- Split into chunks
    local chunks = alc.chunk(text, {
        mode = "lines",
        size = chunk_size,
        overlap = chunk_overlap,
    })

    alc.log("info", string.format("distill: %d chunks, goal=%q", #chunks, goal))

    if #chunks == 0 then
        ctx.result = { summary = "", chunks_processed = 0 }
        return ctx
    end

    -- Map phase: process each chunk in parallel
    local extractions = alc.map(chunks, function(chunk, i)
        return alc.llm(
            string.format(
                "Goal: %s\n\n"
                    .. "Text (section %d of %d):\n```\n%s\n```\n\n"
                    .. "Extract relevant information for the goal above. "
                    .. "Be specific — include names, numbers, and key details. "
                    .. "If this section contains nothing relevant, output: NONE",
                goal, i, #chunks, chunk
            ),
            {
                system = "You are a precise information extractor. "
                    .. "Focus only on content relevant to the stated goal. "
                    .. "Preserve factual details, omit filler.",
                max_tokens = map_tokens,
            }
        )
    end)

    -- Filter out NONE responses
    local relevant = {}
    for i, ext in ipairs(extractions) do
        if not (ext:match("^%s*NONE%s*$") or (ext:match("NONE") and #ext < 20)) then
            relevant[#relevant + 1] = string.format("[Section %d] %s", i, ext)
        end
    end

    if #relevant == 0 then
        ctx.result = {
            summary = "No relevant information found for the stated goal.",
            chunks_processed = #chunks,
            relevant_chunks = 0,
        }
        return ctx
    end

    -- Reduce phase: synthesize all extractions
    local combined = table.concat(relevant, "\n\n")
    local summary = alc.llm(
        string.format(
            "Goal: %s\n\n"
                .. "Extracted information from %d relevant sections:\n\n%s\n\n"
                .. "Synthesize into a unified, well-structured response. "
                .. "Resolve any contradictions between sections. "
                .. "Maintain specific details (names, numbers, references).",
            goal, #relevant, combined
        ),
        {
            system = "You are an expert synthesizer. "
                .. "Merge multiple extractions into one coherent, comprehensive result. "
                .. "Eliminate redundancy while preserving all unique information.",
            max_tokens = reduce_tokens,
        }
    )

    ctx.result = {
        summary = summary,
        chunks_processed = #chunks,
        relevant_chunks = #relevant,
        extractions = extractions,
    }
    return ctx
end

return M
