--- E2E: verify_select (generate-then-verify best-of-N selection).
---
--- Run: agent-block -s scripts/e2e/verify_select.lua -p .
---
--- Flow: alc.llm_batch generates n=2 candidates in one round-trip, then a
---   single verifier pass scores both against the rubric and emits the
---   structured Candidate/SELECTED/RATIONALE verdict block.
---
--- Graders:
---   * agent_ok            — agent block terminated normally
---   * max_tokens(120000)  — budget guard
---   * output_present      — final report non-empty
---   * selected_surfaced   — selected candidate / SELECTED marker in report
---   * rationale_surfaced  — verifier rationale in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "Name the primary tradeoff of adding a database index, in one or two sentences.",
    n    = 2,
}

local prompt = string.format([[
Use algocline to run the verify_select package on a task.

Call alc_advice with:
- package: "verify_select"
- entry: "run"
- task: %q
- opts: { n = %d }

Each alc.llm / alc.llm_batch call inside the package returns status
"needs_response" — reply through alc_continue with a genuine response.

Phase 1 (candidate generation, %d prompts): each prompt asks for a candidate
  answer from a distinct persona. Give genuinely different phrasings/angles
  for each candidate.
Phase 2 (verifier): score EACH candidate and follow the requested output
  format EXACTLY, one score line per candidate:
    Candidate <i> score: <0-10> - <one-line verdict>
    SELECTED: <candidate number>
    RATIONALE: <why it wins>

When the run completes, report DIRECTLY from the alc_advice payload:
1. The selected candidate text (first sentence is enough)
2. The per-candidate scores
3. The rationale

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.n,
    params.n
)

common.run({
    name           = "verify_select",
    prompt         = prompt,
    params         = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(120000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — verify_select output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "selected_surfaced",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = common.strip_md(result.content)
                if c:find("selected", 1, true) or c:find("candidate", 1, true) then
                    return true, nil
                end
                return false, "selected candidate not surfaced in report"
            end,
        },
        {
            name = "rationale_surfaced",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = common.strip_md(result.content)
                if c:find("rationale", 1, true) or c:find("score", 1, true) then
                    return true, nil
                end
                return false, "rationale / scores not surfaced in report"
            end,
        },
    },
})
