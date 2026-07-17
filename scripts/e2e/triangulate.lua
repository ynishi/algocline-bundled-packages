--- E2E: triangulate (agreement-checked verification across N independent paths).
---
--- Run: agent-block -s scripts/e2e/triangulate.lua -p .
---
--- Flow: n=2 route-independent paths solve the same deterministic task in one
---   alc.llm_batch round-trip, each ending with an ANSWER: marker line. The
---   answers agree after normalization → confirmed at round 1 with zero
---   verifier cost (the package's cheap-agreement happy path).
---
--- Graders:
---   * agent_ok            — agent block terminated normally
---   * max_tokens(120000)  — budget guard
---   * output_present      — final report non-empty
---   * agreed_surfaced     — agreed flag / agreement outcome in report
---   * answer_correct      — the confirmed answer (24) in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task       = "How many hours are there in a day? Answer with the number only.",
    n          = 2,
    max_rounds = 1,
}

local prompt = string.format([[
Use algocline to run the triangulate package on a task.

Call alc_advice with:
- package: "triangulate"
- entry: "run"
- task: %q
- opts: { n = %d, max_rounds = %d }

Each alc.llm_batch call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (parallel solve, %d prompts): each prompt assigns you a distinct
  solution method. Follow the assigned method briefly, then end your response
  with a single line of the exact form:
    ANSWER: 24
  Both paths should genuinely derive the answer (24) via their own method, so
  the paths agree and the run confirms at round 1.

When the run completes, report DIRECTLY from the alc_advice payload:
1. The final answer
2. agreed (true/false)
3. rounds_used

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.n,
    params.max_rounds,
    params.n
)

common.run({
    name           = "triangulate",
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
                    return false, "agent content too short — triangulate output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "agreed_surfaced",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = common.strip_md(result.content)
                if c:find("agreed", 1, true) or c:find("agree", 1, true) then
                    return true, nil
                end
                return false, "agreed flag not surfaced in report"
            end,
        },
        {
            name = "answer_correct",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("24", 1, true) then
                    return true, nil
                end
                return false, "confirmed answer (24) not surfaced in report"
            end,
        },
    },
})
