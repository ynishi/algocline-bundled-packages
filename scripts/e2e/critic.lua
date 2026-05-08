--- E2E: critic (LLM-as-a-Judge, Zheng et al. arXiv:2306.05685, 2023).
---
--- Run: agent-block -s scripts/e2e/critic.lua -p .
---
--- Flow: rubric-based structured evaluation — generate initial answer, score
---   each rubric dimension independently, revise weak areas, re-score.
---
--- Graders:
---   * agent_ok           — agent block terminated normally
---   * max_tokens(200000) — cumulative budget guard (multi-dim evaluation calls)
---   * output_present     — final output non-empty
---   * avg_score_reported — avg_score surfaced in report
---   * score_in_range     — avg_score value in valid range [1,10]

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task          = "Explain briefly why the sky is blue.",
    threshold     = 6,
    max_revisions = 1,
    gen_tokens    = 300,
    eval_tokens   = 150,
    revise_tokens = 300,
}

local prompt = string.format([[
Use algocline to run the critic package on a short evaluation task.

Call alc_advice with:
- package: "critic"
- entry: "run"
- task: %q
- opts: {
    threshold     = %d,
    max_revisions = %d,
    gen_tokens    = %d,
    eval_tokens   = %d,
    revise_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Step 1 (generate): provide a concise answer to the task.
Step 2 (evaluate each rubric dimension): for each dimension respond with:
  SCORE: N/10
  FEEDBACK: one sentence
Step 3 (revise, if triggered): provide an improved answer addressing weak areas.

When the run completes, report DIRECTLY from the alc_advice payload:
1. avg_score — the average final score across all rubric dimensions
2. revisions — the number of revision rounds performed
3. answer — the final (possibly revised) answer

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.threshold,
    params.max_revisions,
    params.gen_tokens,
    params.eval_tokens,
    params.revise_tokens
)

common.run({
    name           = "critic",
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
                    return false, "agent content too short — critic output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "avg_score_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("avg_score", 1, true)
                    or c:find("avg score", 1, true)
                    or c:find("average score", 1, true)
                then
                    return true, nil
                end
                return false, "avg_score not surfaced in report"
            end,
        },
        {
            name = "score_in_range",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Look for a numeric value in [1,10] using find-based loop.
                local pos = 1
                while pos <= #c do
                    local s, e, cap = c:find("(%d+%.?%d*)", pos)
                    if not s then break end
                    local v = tonumber(cap)
                    if v and v >= 1 and v <= 10 then
                        return true, nil
                    end
                    pos = e + 1
                end
                return false, "no score value in [1,10] found in report"
            end,
        },
    },
})
