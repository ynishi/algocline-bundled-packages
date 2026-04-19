--- E2E: recipe_quick_vote via alc_eval (multi-case pass_rate)
---
--- Run: agent-block -s scripts/e2e/recipe_quick_vote_eval.lua -p .
---
--- Budget (caps enforced by the recipe itself):
---   p0=0.5, p1=0.80, alpha=0.05, beta=0.10, min_n=3, max_n=8
---   Wald SPRT at these parameters crosses A ≈ +2.89 after 7
---   agreements (log_lr ≈ +3.29) → confirmed at n=8 on unanimous
---   easy tasks. That's 16 LLM calls per confirmed case.
---   Disagreements that push log_lr ≤ B ≈ -2.25 stop earlier:
---   3 disagreements ⇒ n=4 (8 calls).
---
---   math_basic has 7 cases.
---   Upper bound (all confirmed at n=8): 7 × 16 = 112 alc.llm calls.
---   Lower bound (all rejected at n=4):  7 ×  8 =  56 alc.llm calls.
---
---   Agent-block ReAct ループは 1 alc.llm/turn → 最大 112 turns。
---   max_iterations を 150 に確保し、累積 context は ~3M tokens
---   想定 (POC 単発で 326K / ~16 turns → 7 倍で 2.3M + buffer)。

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Run an alc_eval evaluation end-to-end.

Call alc_eval with these exact arguments:
  strategy = "recipe_quick_vote"
  scenario_name = "math_basic"
  strategy_opts = {
      p0 = 0.5,
      p1 = 0.80,
      alpha = 0.05,
      beta = 0.10,
      min_n = 3,
      max_n = 8,
      gen_tokens = 200
  }
  auto_card = true

alc_eval internally runs the strategy on every case in math_basic.
Each case draws samples through recipe_quick_vote, where each sample
is two alc.llm() calls (reasoning + extraction). The Wald SPRT gate
decides accept_h1 (confirmed), accept_h0 (rejected), or continue up
to max_n. Every alc.llm() returns status "needs_response" — reply
through alc_continue(session_id, query_id, response) with a correct,
concise answer.

IMPORTANT:
- You ARE the LLM. Answer math questions correctly.
  - "What is 2+2? Reply with just the number." → "4"
  - "Is 17 a prime number? Reply Yes or No." → "Yes"
- Reasoning prompts: think carefully then state the final answer.
- Extraction prompts: return ONLY the extracted value (one token if
  possible). No explanation.
- Be consistent across samples of the same case — the whole point of
  the recipe is that independent reasoning paths agree on the correct
  answer.

When alc_eval returns its final report, include in the final message:
  1. pass_rate (overall score)
  2. per-case pass/fail list
  3. per-case outcome (confirmed / rejected / truncated)
  4. per-case n_samples and total LLM calls
  5. total LLM calls across all cases
  6. card_id (from auto_card)
  7. any needs_investigation triggers
]]

common.run({
    name = "recipe_quick_vote_eval",
    prompt = prompt,
    max_iterations = 150,
    -- 1024/4096 でも最終レポート (per-case 表 + card_id + 診断) が途中切れ
    -- する (2026-04-19 実測: 4096 でも content 末尾 "1. **Wald" で truncate,
    -- card_id が emit できず reports_card_id grader FAIL)。8192 まで拡張。
    max_tokens = 8192,
    -- Cumulative ReAct history が O(N²) で膨らむ件の保険 (ランナー側の
    -- 早期 abort)。7 cases × ~16 calls × ~50K tokens/turn の実測 ~7M を
    -- 超えたら止める。
    max_tokens_budget = 8000000,
    params = {
        strategy = "recipe_quick_vote",
        scenario = "math_basic",
        strategy_opts = {
            p0 = 0.5,
            p1 = 0.80,
            alpha = 0.05,
            beta = 0.10,
            min_n = 3,
            max_n = 8,
            gen_tokens = 200,
        },
    },
    graders = {
        common.grader_agent_ok(),
        common.grader_max_turns(150),
        -- 7 cases × ~16 calls × ~50K tokens/turn (cumulative ReAct)
        -- = up to ~7M tokens 実測。Buffer to 8M.
        common.grader_max_tokens(8000000),
        {
            name = "reports_pass_rate",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("pass_rate") or c:find("pass rate") then
                    return true, nil
                end
                return false, "pass_rate not reported"
            end,
        },
        {
            name = "reports_card_id",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("card_id") or c:find("card id") then
                    return true, nil
                end
                return false, "card_id not reported"
            end,
        },
        {
            -- All 7 math_basic cases should reach a terminal verdict
            -- (confirmed / rejected / truncated). Smoke check that the
            -- verdict vocabulary appears in the report.
            name = "reports_outcomes",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("confirmed", 1, true)
                    or c:find("truncated", 1, true)
                    or c:find("rejected", 1, true)
                then
                    return true, nil
                end
                return false, "no SPRT outcome label in report"
            end,
        },
    },
})
