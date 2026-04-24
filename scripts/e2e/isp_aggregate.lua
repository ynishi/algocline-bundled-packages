--- E2E: isp_aggregate (meta_prompt_sp INJECT path)
---
--- Run: agent-block -s scripts/e2e/isp_aggregate.lua -p .
---
--- This E2E exercises the **non-paper-faithful** `meta_prompt_sp`
--- INJECT path, which is calibration-free and therefore fits a
--- single-agent-block interactive flow. This is Prelec-Seung-McCoy
--- 2017's Surprisingly Popular linear extension — NOT Zhang 2025's
--- ISP/OW. The paper-faithful default (`method="isp"` + calibration
--- tensor from M.calibrate) is exercised in tests/test_isp_aggregate.lua
--- where kernel correctness can be asserted without a live LLM.
---
--- Here: n=3 agents × 2 calls each (1st-order + 2nd-order meta-prompt)
---       = 6 total LLM calls. Expected winner: Tokyo (trivial geography).

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task    = "Which of the following is the capital of Japan?",
    options = { "A=Tokyo", "B=Kyoto", "C=Osaka" },
    n       = 3,
    method  = "meta_prompt_sp",
}

local prompt = string.format([[
Use algocline to run the isp_aggregate package on a simple geography question.

Call alc_advice with:
- package: "isp_aggregate"
- task: %q
- options: {%q, %q, %q}
- n: %d
- method: %q

The package will (meta_prompt_sp INJECT path, non-paper-faithful):
1. Ask each of the %d agents the 1st-order question (pick ONE option).
2. Ask each agent the 2nd-order question (predict how other agents will vote,
   as probabilities per option in a <probs>...</probs> block).
3. Compute SP 2017-style scores `c1(s) - Σ_i π_i(s)` and select the winner.

IMPORTANT: This path is the SP 2017 aggregator, NOT Zhang 2025 ISP. The
paper-faithful ISP/OW/OW-I methods require a calibration tensor
(M.calibrate), which is covered by unit tests rather than this E2E.

Each alc.llm call returns status "needs_response" — reply through
alc_continue with session_id + your genuine answer.

You ARE the LLM being queried.
- 1st-order prompts: answer with ONLY the option label (e.g. "A=Tokyo").
- 2nd-order prompts: output a <probs> block with probabilities for each option
  summing to 1.
- Be consistent: the capital of Japan is Tokyo = "A=Tokyo" every time.

When the recipe completes, report:
1. Final answer (which option won)
2. scores table (per-option aggregator score)
3. method used
4. Total LLM calls
]],
    params.task,
    params.options[1], params.options[2], params.options[3],
    params.n,
    params.method,
    params.n
)

common.run({
    name           = "isp_aggregate",
    prompt         = prompt,
    params         = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_turns(18),
        common.grader_max_tokens(300000),
        {
            name = "has_answer",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("tokyo", 1, true) then
                    return true, nil
                end
                return false, "answer containing 'tokyo' not found in report"
            end,
        },
        {
            name = "scores_populated",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("score", 1, true) or c:find("meta_prompt_sp", 1, true) then
                    return true, nil
                end
                return false, "no score / method information in report"
            end,
        },
        {
            name = "method_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("meta_prompt_sp", 1, true) or c:find("method", 1, true) then
                    return true, nil
                end
                return false, "method 'meta_prompt_sp' not mentioned in report"
            end,
        },
        {
            name = "total_llm_calls_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("6", 1, true) then
                    return true, nil
                end
                return false, "total_llm_calls=6 not reported"
            end,
        },
    },
})
