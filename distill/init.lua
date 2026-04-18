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

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "distill",
    version = "0.1.0",
    description = "MapReduce summarization — parallel chunk processing with unified reduction",
    category = "extraction",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                text          = T.string:describe("Source text to process (required)"),
                goal          = T.string:is_optional():describe("What to extract/summarize (default 'Summarize the key points')"),
                chunk_size    = T.number:is_optional():describe("Lines per chunk passed to alc.chunk (default 100)"),
                chunk_overlap = T.number:is_optional():describe("Overlap lines between chunks (default 5)"),
                map_tokens    = T.number:is_optional():describe("Max tokens per map call (default 300)"),
                reduce_tokens = T.number:is_optional():describe("Max tokens for the final reduce call (default 600)"),
            }),
            result = T.shape({
                summary          = T.string:describe(
                    "Final synthesized output. Empty string on the no-chunks early-return path, "
                    .. "a canned 'No relevant information' message when every chunk was filtered out, "
                    .. "and the reduce-phase LLM output on the normal path."),
                chunks_processed = T.number:describe("Number of chunks produced by alc.chunk (0 when the input did not split)"),
                relevant_chunks  = T.number:is_optional():describe(
                    "Count of chunks whose map output was not 'NONE'. "
                    .. "Absent on the no-chunks early-return path; present on both the all-filtered and normal paths."),
                extractions      = T.array_of(T.string):is_optional():describe(
                    "Per-chunk raw map outputs in chunk order. "
                    .. "Present only on the normal path — absent on both early-return paths."),
            }),
        },
    },
}

---@param ctx AlcCtx
---@return AlcCtx
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

M.run = S.instrument(M, "run")

return M
