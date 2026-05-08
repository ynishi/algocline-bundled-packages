--- E2E: cascade (FrugalGPT / Routing-to-the-Expert inspired).
---
--- Run: agent-block -s scripts/e2e/cascade.lua -p .
---
--- Flow: multi-level difficulty routing — Level 1 fast zero-shot → Level 2
---   chain-of-thought with verification → Level 3 multi-perspective ensemble.
---   Escalates when self-assessed confidence falls below threshold.
---
--- Graders:
---   * agent_ok           — agent block terminated normally
---   * max_tokens(150000) — cumulative budget guard
---   * output_present     — final output non-empty
---   * level_used_reported — level_used surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task      = "What is the capital of France, and why is it considered a global city?",
    threshold = 0.5,   -- low threshold to encourage escalation to Level 2+
    max_level = 3,
    gen_tokens    = 200,
    verify_tokens = 150,
}

local prompt = string.format([[
Use algocline to run the cascade package on a reasoning task.

Call alc_advice with:
- package: "cascade"
- entry: "run"
- task: %q
- opts: {
    threshold     = %g,
    max_level     = %d,
    gen_tokens    = %d,
    verify_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Level 1 (fast): answer the task directly, then append:
  CONFIDENCE: 0.4

Level 2 (cot+verify): provide a step-by-step answer, then append:
  CONFIDENCE: 0.9

When the run completes, report DIRECTLY from the alc_advice payload:
1. answer — the final answer string
2. level_used — the cascade level at which the run stopped
3. confidence — the final confidence value
4. escalated — whether escalation occurred (level_used > 1)

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise — this smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.threshold,
    params.max_level,
    params.gen_tokens,
    params.verify_tokens
)

common.run({
    name           = "cascade",
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
                    return false, "agent content too short — cascade output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "level_used_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("level_used", 1, true)
                    or c:find("level used", 1, true)
                    or c:find("level:", 1, true)
                then
                    return true, nil
                end
                return false, "level_used / level: not surfaced in report"
            end,
        },
    },
})
