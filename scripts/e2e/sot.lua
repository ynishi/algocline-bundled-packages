--- E2E: sot (Skeleton-of-Thought, Ning et al. 2023, arXiv:2307.15337).
---
--- Run: agent-block -s scripts/e2e/sot.lua -p .
---
--- Flow: short long-form-output task routed through Skeleton-of-Thought.
---   Phase 1 — 1 LLM call to generate a numbered skeleton outline
---     (max 3 sections to keep the smoke fast).
---   Phase 2 — N section fills dispatched in parallel via alc.parallel
---     (single alc.llm_batch round-trip, paper §3.1.1 reports up to
---     2.39x latency speedup vs sequential).
---   Phase 3 — assembly into "## heading\n\n<fill>\n\n" form.
---
--- Transport: alc_advice (sot has no closure inputs, opts are JSON-safe).
---
--- Graders (smoke-level acceptance):
---   * agent_ok                        — agent block terminated normally
---   * max_tokens(150000)              — cumulative budget guard
---   * output_present                  — final output string is non-empty
---   * section_count_reported          — section_count surfaced in report
---   * heading_marker_present          — ## heading present in output
---     (paper-faithful assembly format)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task             = "Explain Lua coroutines briefly: what they are, how to create them, and one common use-case.",
    max_sections     = 3,
    section_tokens   = 200,
    skeleton_tokens  = 150,
}

local prompt = string.format([[
Use algocline to run the sot (Skeleton-of-Thought) package on a short
long-form-output task. Paper: Ning et al. 2023 "Skeleton-of-Thought:
Prompting LLMs for Efficient Parallel Generation" (arXiv:2307.15337).

Call alc_advice with:
- package: "sot"
- entry: "run"
- task: %q
- opts: {
    max_sections    = %d,
    section_tokens  = %d,
    skeleton_tokens = %d,
  }

Each alc.llm call inside `sot.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (skeleton): the prompt asks for a numbered list of section
titles (1..%d). Reply with concise titles, one per line, in the
"1. Title\n2. Title\n..." format.

Phase 2 (fills): the package dispatches all N section fills in a
SINGLE alc.llm_batch round-trip via alc.parallel (this is the
post-migration behavior — see commit b19d0f5). You will see a
single batch of N prompts; respond to each with a concise paragraph
covering only the assigned section.

When the run completes, report DIRECTLY from the alc_advice payload:
1. section_count (should be ≤ %d)
2. skeleton: the parsed section titles array
3. output: the final assembled string (## headings + fills)
4. Whether the assembled output contains all skeleton section titles
   as ## headings

IMPORTANT:
- Do NOT modify max_sections / section_tokens / skeleton_tokens from
  the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.max_sections,
    params.section_tokens,
    params.skeleton_tokens,
    params.max_sections,
    params.max_sections
)

common.run({
    name           = "sot",
    prompt         = prompt,
    params         = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(150000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — sot output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "section_count_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("section_count", 1, true)
                    or c:find("section count", 1, true)
                    or c:find("sections:", 1, true)
                then
                    return true, nil
                end
                return false, "section_count / section count not surfaced in report"
            end,
        },
        {
            name = "heading_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Paper-faithful assembly: "## heading\n\n<fill>\n\n".
                -- Accept either the raw `##` marker in the agent's
                -- echoed output, or an explicit mention that the
                -- output uses ## heading format.
                if c:find("## ", 1, true) then return true, nil end
                local lc = c:lower()
                if lc:find("## heading", 1, true)
                    or lc:find("heading marker", 1, true)
                    or lc:find("markdown heading", 1, true)
                then
                    return true, nil
                end
                return false, "## heading marker not present in agent output"
            end,
        },
    },
})
