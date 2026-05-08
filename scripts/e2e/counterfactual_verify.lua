--- E2E: counterfactual_verify (Counterfactual faithfulness, Hase et al. 2026,
---       arXiv:2602.20710).
---
--- Run: agent-block -s scripts/e2e/counterfactual_verify.lua -p .
---
--- Flow: Step 1 solves the original task with CoT. Step 2 generates N
---   counterfactual variants (change one condition each). Step 3 predicts
---   answers under each variant from original CoT. Step 4 solves variants
---   independently (parallel). Step 5 judges match/mismatch per variant.
---   Step 6 re-solves with explicit grounding if unfaithful.
---
--- Graders:
---   * agent_ok                       — agent block terminated normally
---   * max_tokens(250000)             — cumulative budget guard (3 phases)
---   * output_present                 — final output non-empty
---   * predictions_phase_complete     — counterfactual_results[].predicted surfaced
---   * actuals_phase_complete         — counterfactual_results[].actual surfaced
---   * judgments_phase_complete       — match_count / faithful reported
---     (judgments closure refs predictions+actuals complete invariant)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task              = "A store sells apples for $2 each. If someone buys 4 apples, how much do they spend?",
    n_counterfactuals = 2,
    gen_tokens        = 200,
    cf_tokens         = 150,
}

local prompt = string.format([[
Use algocline to run the counterfactual_verify (causal faithfulness verification)
package. Paper: Hase et al. 2026 "Counterfactual Simulation Training for
Chain-of-Thought Faithfulness" (arXiv:2602.20710).

Call alc_advice with:
- package: "counterfactual_verify"
- entry: "run"
- task: %q
- opts: {
    n_counterfactuals = %d,
    gen_tokens        = %d,
    cf_tokens         = %d,
  }

Each alc.llm call inside `counterfactual_verify.run` returns status "needs_response"
— reply through alc_continue with a genuine response.

Step 1 (solve original with CoT):
  Reply with reasoning:
  "Step 1: price per apple = $2. Step 2: quantity = 4.
  Step 3: total = 2 × 4 = $8.
  Final Answer: $8."

Step 2 (generate %d counterfactuals):
  Generate two variants by changing one condition each. Reply:
  "CHANGE: Price per apple changed to $3
  MODIFIED PROBLEM: A store sells apples for $3 each. If someone buys 4 apples, how much do they spend?

  CHANGE: Quantity changed to 6 apples
  MODIFIED PROBLEM: A store sells apples for $2 each. If someone buys 6 apples, how much do they spend?"

Step 3 (predict under each counterfactual from original CoT):
  For CF1 (price $3): "Tracing original CoT: 4 × $3 = $12. Predicted: $12."
  For CF2 (quantity 6): "Tracing original CoT: $2 × 6 = $12. Predicted: $12."

Step 4 (solve each counterfactual independently, parallel):
  CF1 ($3 each, 4 apples): "3 × 4 = $12. Answer: $12."
  CF2 ($2 each, 6 apples): "2 × 6 = $12. Answer: $12."

Step 5 (judge each counterfactual, parallel):
  CF1: "MATCH — both predicted and actual are $12."
  CF2: "MATCH — both predicted and actual are $12."

When the run completes, report DIRECTLY from the alc_advice payload:
1. answer — final answer string
2. faithful — whether reasoning is causally faithful (true/false)
3. match_count — count of CFs where predicted matched actual
4. total_counterfactuals — total CFs evaluated
5. counterfactual_results — the per-CF evaluation array (change, predicted, actual, match)

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.n_counterfactuals,
    params.gen_tokens,
    params.cf_tokens,
    params.n_counterfactuals
)

common.run({
    name           = "counterfactual_verify",
    prompt         = prompt,
    params         = params,
    max_iterations = 35,
    max_tokens_budget = 250000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(250000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — counterfactual_verify output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "predictions_phase_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- predicted field surfaced = Step 3 (predict from original CoT) ran
                if c:find("predicted", 1, true)
                    or c:find("counterfactual_results", 1, true)
                    or c:find("counterfactual results", 1, true)
                then
                    return true, nil
                end
                return false, "predicted / counterfactual_results not surfaced — predictions phase incomplete"
            end,
        },
        {
            name = "actuals_phase_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- actual field surfaced = Step 4 (independent solve) ran
                if c:find("actual", 1, true) then
                    return true, nil
                end
                return false, "actual not surfaced — actuals phase incomplete"
            end,
        },
        {
            name = "judgments_phase_complete",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- match_count or faithful surfaced = Step 5 (judge) ran after
                -- both predictions and actuals were available (closure invariant)
                if c:find("match_count", 1, true)
                    or c:find("match count", 1, true)
                    or c:find("faithful", 1, true)
                    or c:find("total_counterfactuals", 1, true)
                then
                    return true, nil
                end
                return false, "match_count / faithful not surfaced — judgments phase incomplete"
            end,
        },
    },
})
