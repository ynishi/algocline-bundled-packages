--- E2E: p_tts (Plan-Test-Then-Solve, Zhang et al. arXiv:2303.05510 + TDD reasoning, 2023).
---
--- Run: agent-block -s scripts/e2e/p_tts.lua -p .
---
--- Flow: constraint-first reasoning — plan requirements, generate verifiable
---   constraints before solving, solve while aware of them, verify solution,
---   repair violations if any.
---
--- Graders:
---   * agent_ok                  — agent block terminated normally
---   * max_tokens(200000)        — cumulative budget guard (plan+verify+repair calls)
---   * output_present            — final output non-empty
---   * pass_count_reported       — pass_count / fail_count surfaced in report
---   * final_answer_present      — final answer field reported

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task            = "Write a short paragraph explaining what a prime number is, suitable for a 10-year-old.",
    max_constraints = 4,
    max_repairs     = 1,
    plan_tokens     = 200,
    gen_tokens      = 300,
    verify_tokens   = 100,
}

local prompt = string.format([[
Use algocline to run the p_tts (Plan-Test-Then-Solve) package on a
constrained writing task.

Call alc_advice with:
- package: "p_tts"
- entry: "run"
- task: %q
- opts: {
    max_constraints = %d,
    max_repairs     = %d,
    plan_tokens     = %d,
    gen_tokens      = %d,
    verify_tokens   = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Step 1 (plan): identify key requirements and approach for the task.
Step 2 (generate constraints): list verifiable constraints the answer must meet
  as a numbered list, e.g.:
  1. Must not use technical jargon
  2. Must include a concrete example
  3. Explanation should be one paragraph
  4. Suitable language for a 10-year-old
Step 3 (solve): write the explanation while keeping the constraints in mind.
Step 4 (verify each constraint): for each constraint reply with:
  VERDICT: pass | fail
  REASON: one-sentence justification

When the run completes, report DIRECTLY from the alc_advice payload:
1. pass_count — number of constraints passing
2. fail_count — number of constraints failing
3. all_passed — whether all constraints passed
4. answer — the final answer

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_constraints,
    params.max_repairs,
    params.plan_tokens,
    params.gen_tokens,
    params.verify_tokens
)

common.run({
    name           = "p_tts",
    prompt         = prompt,
    params         = params,
    max_iterations = 30,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — p_tts output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "pass_count_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("pass_count", 1, true)
                    or c:find("pass count", 1, true)
                    or c:find("all_passed", 1, true)
                    or c:find("constraints", 1, true)
                then
                    return true, nil
                end
                return false, "pass_count / constraints not surfaced in report"
            end,
        },
        {
            name = "final_answer_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("answer", 1, true)
                    or c:find("prime", 1, true)
                    or c:find("number", 1, true)
                then
                    return true, nil
                end
                return false, "final answer not found in report"
            end,
        },
    },
})
