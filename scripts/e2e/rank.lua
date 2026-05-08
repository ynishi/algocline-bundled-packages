--- E2E: rank (Best-of-N / LLM-as-Judge tournament, Zheng et al. 2023).
---
--- Run: agent-block -s scripts/e2e/rank.lua -p .
---
--- Flow: generate N candidates in parallel, tournament pairwise comparison via
---   LLM-as-Judge, select winner with reasoning.
---
--- Graders:
---   * agent_ok           — agent block terminated normally
---   * max_tokens(200000) — cumulative budget guard (N candidates + comparisons)
---   * output_present     — final output non-empty
---   * winner_reported    — winner / ranked result surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task       = "Suggest a name for a new open-source library that helps developers write cleaner Lua code.",
    candidates = 3,
    criteria   = "memorability, relevance to Lua, ease of spelling",
    gen_tokens = 150,
}

local prompt = string.format([[
Use algocline to run the rank package on a candidate generation and selection task.

Call alc_advice with:
- package: "rank"
- entry: "run"
- task: %q
- opts: {
    candidates = %d,
    criteria   = %q,
    gen_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (candidate generation): each expert generates a library name suggestion.
  Provide a creative, concise name with a one-sentence rationale.

Phase 2 (tournament comparisons): for each pairwise comparison reply with
  exactly "A" or "B" followed by a brief reason.

When the run completes, report DIRECTLY from the alc_advice payload:
1. winner — the winning candidate response
2. The total number of candidates that were generated and compared

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.candidates,
    params.criteria,
    params.gen_tokens
)

common.run({
    name           = "rank",
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
                    return false, "agent content too short — rank output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "winner_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("winner", 1, true)
                    or c:find("best", 1, true)
                    or c:find("ranked", 1, true)
                    or c:find("selected", 1, true)
                then
                    return true, nil
                end
                return false, "winner / ranking result not surfaced in report"
            end,
        },
    },
})
