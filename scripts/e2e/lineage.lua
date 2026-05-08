--- E2E: lineage (Pipeline claim lineage tracking, Xie et al. AAMAS 2026).
---
--- Run: agent-block -s scripts/e2e/lineage.lua -p .
---
--- Flow: Phase 1 extracts atomic claims from each step output (parallel).
---   Phase 2 traces inter-step dependencies (which claim derived from which).
---   Phase 3 detects conflicts and ungrounded claims.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(200000)      — cumulative budget guard
---   * output_present          — final output non-empty
---   * step_claims_reported    — step_claims[] surfaced (Phase 1 claim extraction ran)
---   * trace_results_reported  — traces[] surfaced (Phase 2 ran, refs Phase 1 output)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task           = "Determine whether eating breakfast regularly improves cognitive performance.",
    extract_tokens = 200,
    trace_tokens   = 200,
    summary_tokens = 200,
}

local prompt = string.format([[
Use algocline to run the lineage (claim lineage tracking) package.
Paper: Xie et al. "From Spark to Fire: Diagnosing and Overcoming the Fragility
of Multi-Agent Systems" (AAMAS 2026).

Call alc_advice with:
- package: "lineage"
- entry: "run"
- task: %q
- opts: {
    steps = {
      { name = "research",
        output = "Studies show that children who eat breakfast score 15%% higher on memory tests. Protein intake in the morning stabilizes blood glucose, which supports brain function." },
      { name = "conclusion",
        output = "Regular breakfast consumption improves cognitive performance by stabilizing blood glucose and supporting memory. The effect is strongest in children." },
    },
    extract_tokens = %d,
    trace_tokens   = %d,
    summary_tokens = %d,
  }

Each alc.llm call inside `lineage.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (claim extraction, one call per step, parallel):
  For the "research" step, extract claims in numbered format:
    1. Children who eat breakfast score 15%% higher on memory tests.
    2. Protein intake in the morning stabilizes blood glucose.
    3. Stable blood glucose supports brain function.
  For the "conclusion" step, extract claims:
    1. Regular breakfast consumption improves cognitive performance.
    2. The improvement mechanism is blood glucose stabilization.
    3. The effect is strongest in children.

Phase 2 (trace dependencies, one call per consecutive step pair):
  Trace how "conclusion" claims derive from "research" claims. Reply:
    1. DERIVES_FROM: [1,2,3] TRANSFORMATION: INFERRED
    2. DERIVES_FROM: [2,3] TRANSFORMATION: REFINED
    3. DERIVES_FROM: [1] TRANSFORMATION: PRESERVED

Phase 3 (conflict/integrity analysis):
  Reply: "SCORE: 0.9\nNo conflicts detected. All conclusion claims are
  grounded in the research step. Lineage is intact."

When the run completes, report DIRECTLY from the alc_advice payload:
1. step_claims — the per-step extracted claims array
2. traces — the inter-step dependency trace array
3. integrity_score — the parsed score (if present)
4. analysis — the conflict/integrity analysis text

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.extract_tokens,
    params.trace_tokens,
    params.summary_tokens
)

common.run({
    name           = "lineage",
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
                    return false, "agent content too short — lineage output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "step_claims_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- step_claims array surfaced = Phase 1 claim extraction completed
                if c:find("step_claims", 1, true)
                    or c:find("step claims", 1, true)
                    or c:find("claims", 1, true)
                then
                    return true, nil
                end
                return false, "step_claims / claims not surfaced — Phase 1 incomplete"
            end,
        },
        {
            name = "trace_results_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- traces array surfaced = Phase 2 ran using Phase 1 claims
                if c:find("traces", 1, true)
                    or c:find("trace", 1, true)
                    or c:find("derives_from", 1, true)
                    or c:find("derives from", 1, true)
                    or c:find("lineage_graph", 1, true)
                    or c:find("lineage graph", 1, true)
                then
                    return true, nil
                end
                return false, "traces / derives_from not surfaced — Phase 2 incomplete"
            end,
        },
    },
})
