--- E2E: refine_loop (reflective draft→reflect→revise loop, GEPA direction).
---
--- Run: agent-block -s scripts/e2e/refine_loop.lua -p .
---
--- Flow: draft → reflection (critique on round 1) → revise → reflection
---   (ACCEPT on round 2) → early-stop. Exercises both the revision path
---   and the ACCEPT early-stop in one run.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(120000)      — budget guard
---   * output_present          — final report non-empty
---   * accepted_surfaced       — accepted flag / ACCEPT outcome in report
---   * iterations_surfaced     — iterations_used count in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task           = "Explain in 2-3 sentences why binary search requires a sorted array.",
    max_iterations = 2,
}

local prompt = string.format([[
Use algocline to run the refine_loop package on a task.

Call alc_advice with:
- package: "refine_loop"
- entry: "run"
- task: %q
- opts: { max_iterations = %d }

Each alc.llm call inside the package returns status "needs_response" — reply
through alc_continue with a genuine response.

Phase 1 (draft): produce a short, decent-but-imperfect explanation.
Phase 2 (first reflection): the prompt asks you to critique the draft against
  a rubric. Give ONE concrete improvement point (do NOT reply ACCEPT yet).
Phase 3 (revise): rewrite the draft addressing your critique.
Phase 4 (second reflection): the revised draft now satisfies the rubric —
  reply with the single word ACCEPT and nothing else.

When the run completes, report DIRECTLY from the alc_advice payload:
1. The final answer text (first sentence is enough)
2. iterations_used
3. accepted (true/false)

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_iterations
)

common.run({
    name           = "refine_loop",
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
                    return false, "agent content too short — refine_loop output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "accepted_surfaced",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = common.strip_md(result.content)
                if c:find("accepted", 1, true) or c:find("accept", 1, true) then
                    return true, nil
                end
                return false, "accepted flag not surfaced in report"
            end,
        },
        {
            name = "iterations_surfaced",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = common.strip_md(result.content)
                if c:find("iteration", 1, true) or c:find("round", 1, true) then
                    return true, nil
                end
                return false, "iterations_used not surfaced in report"
            end,
        },
    },
})
