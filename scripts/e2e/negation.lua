--- E2E: negation (adversarial self-test, Huang et al. arXiv:2310.01798, 2023).
---
--- Run: agent-block -s scripts/e2e/negation.lua -p .
---
--- Flow: adversarial self-test via destruction conditions — generate initial
---   answer, generate destruction conditions that would invalidate it, verify
---   each condition, revise if any hold.
---
--- Graders:
---   * agent_ok               — agent block terminated normally
---   * max_tokens(150000)     — cumulative budget guard
---   * output_present         — final output non-empty
---   * conditions_reported    — verification_count / conditions surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task           = "Is it safe to drink water directly from a mountain stream?",
    max_conditions = 3,
    gen_tokens     = 250,
    verify_tokens  = 150,
    revise_tokens  = 250,
}

local prompt = string.format([[
Use algocline to run the negation package on a question with testable claims.

Call alc_advice with:
- package: "negation"
- entry: "run"
- task: %q
- opts: {
    max_conditions = %d,
    gen_tokens     = %d,
    verify_tokens  = %d,
    revise_tokens  = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Step 1 (generate answer): provide a concise answer to the task.
Step 2 (generate destruction conditions): list conditions that would
  invalidate the answer as a numbered list, e.g.:
  1. If the stream is actually contaminated by upstream sources
  2. If local wildlife carry pathogens
  3. If the region has agricultural runoff
Step 3 (verify each condition): for each condition reply with:
  VERDICT: holds | refuted
  REASONING: one-sentence reason
Step 4 (revise, if triggered): provide a revised answer.

When the run completes, report DIRECTLY from the alc_advice payload:
1. survived — whether all conditions were refuted
2. holding / refuted / total — condition verdict counts
3. answer — the final answer (original or revised)

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_conditions,
    params.gen_tokens,
    params.verify_tokens,
    params.revise_tokens
)

common.run({
    name           = "negation",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(150000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — negation output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "conditions_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("condition", 1, true)
                    or c:find("holding", 1, true)
                    or c:find("refuted", 1, true)
                    or c:find("survived", 1, true)
                then
                    return true, nil
                end
                return false, "destruction condition results not surfaced in report"
            end,
        },
    },
})
