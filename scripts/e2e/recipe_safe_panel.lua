--- E2E: recipe_safe_panel
---
--- Run: agent-block -s scripts/e2e/recipe_safe_panel.lua -p .
---
--- Flow (expected LLM calls):
---   Stage 1 (condorcet)  : 0 (pure compute)
---   Stage 2 (sc, N=3)    : 6 (3 sample + 3 extract)
---   Stage 3 (inverse_u)  : skipped (N < 5)
---   Stage 4 (calibrate)  : 1-2
---   Total                : 7-8

-- scripts/e2e/ is in the Lua package path when agent-block is invoked with `-p .`
-- (agent-block adds blocks/ to package.path; we use the script dir's sibling).
package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "What is the capital of Japan? Answer with just the city name.",
    opts = {
        p_estimate = 0.85,
        target_accuracy = 0.7,
        max_n = 3,
        confidence_threshold = 0.6,
        scaling_check = false,
    },
}

local prompt = string.format([[
Use algocline to run the recipe_safe_panel on a simple factual question.

Call alc_advice with:
- package: "recipe_safe_panel"
- task: %q
- opts: {
    p_estimate = %s,
    target_accuracy = %s,
    max_n = %d,
    confidence_threshold = %s,
    scaling_check = %s
  }

The recipe will make several alc.llm() calls through its internal stages
(condorcet sizing, sc sampling, calibrate). Each call returns status
"needs_response" — call alc_continue with session_id + your answer.

IMPORTANT: You ARE the LLM. For factual questions, answer correctly.
For extraction prompts, extract just the requested value.

When the recipe completes, report:
1. Final answer
2. Panel size chosen
3. Confidence score
4. Total LLM calls
5. Whether any safety gates triggered (anti_jury, needs_investigation)
]],
    params.task,
    tostring(params.opts.p_estimate),
    tostring(params.opts.target_accuracy),
    params.opts.max_n,
    tostring(params.opts.confidence_threshold),
    tostring(params.opts.scaling_check)
)

common.run({
    name = "recipe_safe_panel",
    prompt = prompt,
    params = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("Tokyo", "answer_tokyo"),
        common.grader_max_turns(15),
        common.grader_max_tokens(200000),
        {
            name = "anti_jury_not_triggered",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("anti%-jury") and c:find("true") then
                    return false, "anti_jury flag mentioned as triggered"
                end
                return true, nil
            end,
        },
        {
            name = "reports_panel_size",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("[Pp]anel") and c:find("3") then
                    return true, nil
                end
                return false, "panel size not reported in content"
            end,
        },
    },
})
