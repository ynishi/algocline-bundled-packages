--- E2E: recipe_quick_vote
---
--- Run: agent-block -s scripts/e2e/recipe_quick_vote.lua -p .
---
--- Flow (simple arithmetic task, expected confirmed path):
---   Sample 1 (leader):        2 LLM calls (reasoning + extract)
---   Samples 2..k (k ≤ 8):     2 LLM calls each
---   SPRT fires at k=8 once   (log_lr ≈ +3.29 ≥ A ≈ +2.89) → confirmed
---   Expected total:          ~16 LLM calls (easy task, all agree)
---
---   If the model is inconsistent, outcome may be "rejected" or
---   "truncated" — the graders accept any valid outcome and only
---   assert the leader answer "42" and the presence of SPRT fields.

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "What is 17 + 25? Answer with just the number.",
    opts = {
        p0 = 0.5,
        p1 = 0.80,
        alpha = 0.05,
        beta = 0.10,
        min_n = 3,
        max_n = 8,
        gen_tokens = 200,
    },
}

local prompt = string.format([[
Use algocline to run the recipe_quick_vote on a simple arithmetic question.

Call alc_advice with:
- package: "recipe_quick_vote"
- task: %q
- opts: {
    p0 = %s,
    p1 = %s,
    alpha = %s,
    beta = %s,
    min_n = %d,
    max_n = %d,
    gen_tokens = %d
  }

The recipe will draw independent samples one at a time, each consisting of
a reasoning path (one alc.llm call) and an answer extraction (second
alc.llm call). After the first sample commits the leader, each subsequent
sample's agreement with the leader is fed into a Wald SPRT gate at the
declared (alpha, beta) error rates. The loop exits as soon as SPRT
declares accept_h1 (confirmed), accept_h0 (rejected), or reaches max_n
(truncated).

Each alc.llm call returns status "needs_response" — reply through
alc_continue with session_id + your genuine answer.

IMPORTANT: You ARE the LLM being queried.
- Reasoning prompts: think carefully and give your final answer clearly.
- Extraction prompts: return ONLY the extracted answer (a number here).
- Be consistent: 17 + 25 = 42 every time.

When the recipe completes, report:
1. Final answer
2. Outcome (confirmed / rejected / truncated)
3. Verdict (accept_h1 / accept_h0 / continue)
4. n_samples drawn
5. Total LLM calls
6. SPRT log_lr at termination
7. needs_investigation flag
]],
    params.task,
    tostring(params.opts.p0),
    tostring(params.opts.p1),
    tostring(params.opts.alpha),
    tostring(params.opts.beta),
    params.opts.min_n,
    params.opts.max_n,
    params.opts.gen_tokens
)

common.run({
    name = "recipe_quick_vote",
    prompt = prompt,
    params = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("42", "answer_42"),
        common.grader_max_turns(22),
        -- ReAct ループ 18 turns × 累積 context で ~325K tokens/run 実測。
        -- 16 LLM calls を回す recipe_quick_vote では 200K は狭すぎ、
        -- 500K に揃える (recipe_safe_panel は 8 calls/~15 turns で 200K で足りる)。
        common.grader_max_tokens(500000),
        {
            -- Expected path on an easy arithmetic task: confirmed.
            -- Accept rejected / truncated only with a descriptive
            -- failure message — keeps this as a smoke test that
            -- flags regressions without demanding determinism.
            name = "outcome_confirmed",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("confirmed", 1, true) then
                    return true, nil
                end
                if c:find("rejected", 1, true) then
                    return false, "outcome=rejected on an easy task "
                        .. "(suggests sample-level inconsistency)"
                end
                if c:find("truncated", 1, true) then
                    return false, "outcome=truncated on an easy task "
                        .. "(SPRT never crossed a boundary within max_n)"
                end
                return false, "outcome label not reported"
            end,
        },
        {
            name = "verdict_accept_h1",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("accept_h1", 1, true) or c:find("accept h1", 1, true) then
                    return true, nil
                end
                return false, "verdict accept_h1 not reported"
            end,
        },
        {
            -- Confirmed path should take ≤ max_n samples.
            -- With p0=0.5 / p1=0.8 / α=β defaults SPRT fires at k=8
            -- on all-agree (7 agreements cross A ≈ +2.89).
            -- Matches patterns like "Samples Drawn: 8", "n_samples: 8",
            -- "8 samples"; keeps min_n / max_n labels out of the match.
            name = "samples_within_bound",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                local candidates = {}
                -- "Samples Drawn: N" / "samples drawn N"
                for n in c:gmatch("[Ss]amples?%s+[Dd]rawn[^%d]*(%d+)") do
                    candidates[#candidates + 1] = tonumber(n)
                end
                -- "n_samples ... N" (not min_n / max_n)
                for n in c:gmatch("n_samples[^%d]*(%d+)") do
                    candidates[#candidates + 1] = tonumber(n)
                end
                -- "N samples" as a fallback
                for n in c:gmatch("(%d+)%s+samples?[^_A-Za-z]") do
                    candidates[#candidates + 1] = tonumber(n)
                end
                for _, k in ipairs(candidates) do
                    if k >= 3 and k <= 8 then
                        return true, "n_samples = " .. tostring(k)
                    end
                end
                return false, string.format(
                    "n_samples not in [3, 8]; candidates=%s",
                    table.concat(candidates, ",")
                )
            end,
        },
        {
            name = "reports_sprt_fields",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("log[_ ]lr", 1, false) or c:find("log%-lr") then
                    return true, nil
                end
                if c:find("sprt", 1, true) then
                    return true, "mentions sprt block"
                end
                return false, "no SPRT log_lr / sprt block reported"
            end,
        },
    },
})
