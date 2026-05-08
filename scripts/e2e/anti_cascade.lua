--- E2E: anti_cascade (Pipeline error cascade detection, Xie et al. AAMAS 2026).
---
--- Run: agent-block -s scripts/e2e/anti_cascade.lua -p .
---
--- Flow: for each pipeline step, independently re-derive from the original task
---   (Phase 1 parallel) then compare pipeline output vs independent derivation
---   to compute a drift score (Phase 2 comparison). Flags steps where drift
---   exceeds threshold. Final summary reports cascade risk.
---
--- Graders:
---   * agent_ok                    — agent block terminated normally
---   * max_tokens(200000)          — cumulative budget guard (multi-step task)
---   * output_present              — final output non-empty
---   * independent_phase_complete  — step_results[] reported (Phase 1 re-derivation ran)
---   * comparison_phase_complete   — flagged_steps / max_drift surfaced (Phase 2 ran)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task            = "Calculate the total price of 3 items costing $12, $8, and $5 including 10% tax.",
    drift_threshold = 0.4,
    rederive_tokens = 200,
    compare_tokens  = 150,
    summary_tokens  = 200,
}

local prompt = string.format([[
Use algocline to run the anti_cascade (pipeline cascade detection) package.
Paper: Xie et al., "From Spark to Fire: Diagnosing and Overcoming the Fragility
of Multi-Agent Systems" (AAMAS 2026).

Call alc_advice with:
- package: "anti_cascade"
- entry: "run"
- task: %q
- opts: {
    steps = {
      { name = "step1_sum", instruction = "Sum the 3 item prices before tax",
        output = "The sum of items is $25." },
      { name = "step2_tax", instruction = "Apply 10%% tax to the sum",
        output = "Tax is $2.50, total is $27.50." },
    },
    drift_threshold = %g,
    rederive_tokens = %d,
    compare_tokens  = %d,
    summary_tokens  = %d,
  }

Each alc.llm call inside `anti_cascade.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (independent re-derivation, parallel for each step):
  For step1_sum: independently compute the sum from the task. Reply: "The
  items cost $12, $8, $5. Sum = $25."
  For step2_tax: independently compute the taxed total. Reply: "Sum $25,
  10%% tax = $2.50, total = $27.50."

Phase 2 (comparison, one call per step):
  For each step, compare the pipeline output vs the independent derivation.
  Reply with the structured format:
    DRIFT_SCORE: 0.0
    DRIFT_TYPE: NONE
    CASCADE_RISK: LOW
    ANALYSIS: Both outputs agree on the value.

Phase 3 (summary):
  Reply with a brief cascade risk summary: "No cascade amplification detected.
  Both steps produced consistent outputs."

When the run completes, report DIRECTLY from the alc_advice payload:
1. step_results — per-step drift analysis array (name, drift_score, flagged)
2. flagged_steps — list of flagged step names
3. max_drift — highest drift score observed
4. summary — the cascade analysis summary text

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.drift_threshold,
    params.rederive_tokens,
    params.compare_tokens,
    params.summary_tokens
)

common.run({
    name           = "anti_cascade",
    prompt         = prompt,
    params         = params,
    max_iterations = 30,
    max_tokens_budget = 200000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — anti_cascade output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "independent_phase_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- step_results array surfaced = Phase 1 re-derivation completed
                if c:find("step_results", 1, true)
                    or c:find("step results", 1, true)
                    or c:find("drift_score", 1, true)
                    or c:find("drift score", 1, true)
                then
                    return true, nil
                end
                return false, "step_results / drift_score not surfaced — Phase 1 incomplete"
            end,
        },
        {
            name = "comparison_phase_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- flagged_steps or max_drift surfaced = Phase 2 comparison ran
                if c:find("flagged_steps", 1, true)
                    or c:find("flagged steps", 1, true)
                    or c:find("max_drift", 1, true)
                    or c:find("max drift", 1, true)
                    or c:find("cascade_risk", 1, true)
                    or c:find("cascade risk", 1, true)
                then
                    return true, nil
                end
                return false, "flagged_steps / max_drift / cascade_risk not surfaced — Phase 2 incomplete"
            end,
        },
    },
})
