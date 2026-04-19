--- E2E: recipe_safe_panel via alc_eval (multi-case pass_rate)
---
--- Run: agent-block -s scripts/e2e/recipe_safe_panel_eval.lua -p .
---
--- Budget (caps enforced by the recipe itself):
---   max_n = 3              -- panel cap → 2n+1=7 LLM calls per case
---   scaling_check = false  -- skips inverse_u stage
---   +1-2 calibrate call per case
---   math_basic = 7 cases
---   → upper bound: 7 * (7 + 2) = 63 alc.llm calls
---
--- The agent ReAct loop handles each alc.llm(...) → alc_continue round-trip.
--- max_iterations is raised to 150 to absorb the full case sweep.

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Run an alc_eval evaluation end-to-end.

Call alc_eval with these exact arguments:
  strategy = "recipe_safe_panel"
  scenario_name = "math_basic"
  strategy_opts = {
      p_estimate = 0.85,
      target_accuracy = 0.7,
      max_n = 3,
      confidence_threshold = 0.6,
      scaling_check = false
  }
  auto_card = true

alc_eval internally runs the strategy on every case in math_basic.
Each case issues multiple alc.llm() calls through the recipe's
stages (condorcet → sc → calibrate). For every call that returns
status "needs_response", call alc_continue(session_id, query_id,
response) with a correct, concise answer to the prompt.

IMPORTANT:
- You ARE the LLM. Answer math questions correctly.
- Return ONLY the requested value for extraction prompts
  (e.g. "4", "120", "Yes").
- For vote-counting prompts, be exact.

When alc_eval returns its final report, include in the final
message:
  1. pass_rate (overall score)
  2. per-case pass/fail list
  3. total LLM calls across all cases
  4. card_id (from auto_card)
  5. any safety gate triggers (anti_jury, needs_investigation)
]]

common.run({
    name = "recipe_safe_panel_eval",
    prompt = prompt,
    max_iterations = 150,
    -- multi-case eval は最終 report に per-case 表 + card_id + 複数診断
    -- (anti_jury / needs_investigation / safety gate) を含めるため 1024
    -- では truncate する実リスクがあり、事前に 4096 に引き上げ。
    -- 実測で truncate したら 8192 まで更に引き上げる (quick_vote 前例)。
    max_tokens = 4096,
    params = {
        strategy = "recipe_safe_panel",
        scenario = "math_basic",
        strategy_opts = {
            p_estimate = 0.85,
            target_accuracy = 0.7,
            max_n = 3,
            confidence_threshold = 0.6,
            scaling_check = false,
        },
    },
    graders = {
        common.grader_agent_ok(),
        common.grader_max_turns(150),
        common.grader_max_tokens(2000000),
        {
            name = "reports_pass_rate",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:lower():find("pass_rate") or c:lower():find("pass rate") then
                    return true, nil
                end
                return false, "pass_rate not reported"
            end,
        },
        {
            name = "reports_card_id",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:lower():find("card_id") or c:lower():find("card id") then
                    return true, nil
                end
                return false, "card_id not reported"
            end,
        },
    },
})
