--- E2E: isp_aggregate
---
--- Run: agent-block -s scripts/e2e/isp_aggregate.lua -p .
---
--- Calls isp_aggregate with a simple geography question (easy vote).
--- Each of n=3 agents answers 1st-order (pick option) and 2nd-order
--- (predict other agents' distribution). ISP scoring selects the winner.
--- Expected total: 6 LLM calls (2 per agent × 3 agents).

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task    = "Which of the following is the capital of Japan?",
    options = { "A=Tokyo", "B=Kyoto", "C=Osaka" },
    n       = 3,
    method  = "isp",
}

local prompt = string.format([[
Use algocline to run the isp_aggregate package on a simple geography question.

Call alc_advice with:
- package: "isp_aggregate"
- task: %q
- options: {%q, %q, %q}
- n: %d
- method: %q

The package will:
1. Ask each of the %d agents the 1st-order question (pick ONE option).
2. Ask each agent the 2nd-order question (predict how other agents will vote,
   as probabilities per option in a <probs>...</probs> block).
3. Compute ISP scores and select the winner.

Each alc.llm call returns status "needs_response" — reply through
alc_continue with session_id + your genuine answer.

IMPORTANT: You ARE the LLM being queried.
- 1st-order prompts: answer with ONLY the option label (e.g. "A=Tokyo").
- 2nd-order prompts: output a <probs> block with probabilities for each option.
- Be consistent: the capital of Japan is Tokyo = "A=Tokyo" every time.

When the recipe completes, report:
1. Final answer (which option won)
2. ISP scores for each option
3. c1 vote counts
4. method used
5. Total LLM calls
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
                -- Expect the agent to report "Tokyo" or "A=Tokyo" as winner
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
                -- Expect ISP scores to be mentioned
                if c:find("score", 1, true) or c:find("isp", 1, true) then
                    return true, nil
                end
                return false, "no ISP score information in report"
            end,
        },
        {
            name = "method_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("isp", 1, true) or c:find("method", 1, true) then
                    return true, nil
                end
                return false, "method 'isp' not mentioned in report"
            end,
        },
        {
            name = "total_llm_calls_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Expect 6 total LLM calls (2 per agent × 3 agents)
                if c:find("6", 1, true) then
                    return true, nil
                end
                return false, "total_llm_calls=6 not reported"
            end,
        },
    },
})
