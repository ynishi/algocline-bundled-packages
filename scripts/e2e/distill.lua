--- E2E: distill (LLM×MapReduce, arXiv:2410.09342, 2024).
---
--- Run: agent-block -s scripts/e2e/distill.lua -p .
---
--- Flow: MapReduce summarization — split text into chunks, process each in
---   parallel, reduce into unified result.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(200000)      — cumulative budget guard (parallel map calls)
---   * output_present          — final output non-empty
---   * chunks_processed_reported — chunks_processed field surfaced in report
---   * summary_present         — summary / reduce result present in output

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

-- Multi-line text that will split into at least 2 chunks at chunk_size=5 lines.
local source_text = table.concat({
    "The Python programming language was created by Guido van Rossum.",
    "It was first released in 1991.",
    "Python emphasizes code readability and simplicity.",
    "It supports multiple programming paradigms including procedural, object-oriented, and functional.",
    "Python is widely used in data science and machine learning.",
    "The language has a large standard library.",
    "Python uses indentation to define code blocks instead of braces.",
    "It has dynamic typing and automatic memory management.",
    "Popular frameworks include Django for web development.",
    "NumPy and Pandas are essential for data analysis.",
    "Python runs on major platforms including Windows, macOS, and Linux.",
    "The Python Package Index (PyPI) hosts hundreds of thousands of packages.",
}, "\n")

local params = {
    text          = source_text,
    goal          = "Summarize the key facts about Python.",
    chunk_size    = 5,
    chunk_overlap = 1,
    map_tokens    = 150,
    reduce_tokens = 250,
}

local prompt = string.format([[
Use algocline to run the distill package on a multi-chunk summarization task.

Call alc_advice with:
- package: "distill"
- entry: "run"
- text: %q
- opts: {
    goal          = %q,
    chunk_size    = %d,
    chunk_overlap = %d,
    map_tokens    = %d,
    reduce_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Map phase: for each chunk, extract relevant facts about Python as a short list.
  If a chunk has no relevant info, respond with: NONE

Reduce phase: synthesize all extractions into a cohesive summary paragraph.

When the run completes, report DIRECTLY from the alc_advice payload:
1. chunks_processed — number of chunks created from the text
2. relevant_chunks  — chunks with non-NONE map output
3. summary          — the final synthesized summary text

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.text,
    params.goal,
    params.chunk_size,
    params.chunk_overlap,
    params.map_tokens,
    params.reduce_tokens
)

common.run({
    name           = "distill",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — distill output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "chunks_processed_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("chunks_processed", 1, true)
                    or c:find("chunks processed", 1, true)
                    or c:find("chunk", 1, true)
                then
                    return true, nil
                end
                return false, "chunks_processed not surfaced in report"
            end,
        },
        {
            name = "summary_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("summary", 1, true)
                    or c:find("python", 1, true)
                then
                    return true, nil
                end
                return false, "summary / reduce output not surfaced in report"
            end,
        },
    },
})
