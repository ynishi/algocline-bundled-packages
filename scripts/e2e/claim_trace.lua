--- E2E: claim_trace (Attributed QA / ALCE, Bohnet et al. 2022 / Gao et al. 2023).
---
--- Run: agent-block -s scripts/e2e/claim_trace.lua -p .
---
--- Flow: three-step span attribution — extract atomic claims from an answer,
---   attribute each claim to supporting span(s) in the source, compute
---   attribution score.
---
--- Graders:
---   * agent_ok              — agent block terminated normally
---   * max_tokens(150000)    — cumulative budget guard
---   * output_present        — final output non-empty
---   * attribution_score_reported — attribution_score surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task    = "What does photosynthesis produce?",
    sources = "Photosynthesis is the process by which plants use sunlight, water, and carbon dioxide to produce oxygen and energy in the form of glucose. The oxygen is released as a byproduct through the stomata of leaves.",
    extract_tokens = 300,
    trace_tokens   = 200,
}

local prompt = string.format([[
Use algocline to run the claim_trace package on a short attribution task.

Call alc_advice with:
- package: "claim_trace"
- entry: "run"
- task: %q
- opts: {
    sources        = %q,
    extract_tokens = %d,
    trace_tokens   = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Step 1 (answer generation): answer the task concisely using the source.
Step 2 (claim extraction): list atomic claims as a numbered list.
  Example: "1. Plants produce oxygen. 2. Glucose is produced."
Step 3 (attribution): for each claim reply with:
  ATTRIBUTION: SUPPORTED
  SPAN: "quoted text"
  REASONING: brief reasoning

When the run completes, report DIRECTLY from the alc_advice payload:
1. attribution_score — numeric score in [0, 1]
2. total — total number of extracted claims
3. supported — count of supported claims
4. answer — the answer whose claims were traced

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.sources,
    params.extract_tokens,
    params.trace_tokens
)

common.run({
    name           = "claim_trace",
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
                    return false, "agent content too short — claim_trace output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "attribution_score_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("attribution_score", 1, true)
                    or c:find("attribution score", 1, true)
                    or c:find("score:", 1, true)
                then
                    return true, nil
                end
                return false, "attribution_score not surfaced in report"
            end,
        },
    },
})
