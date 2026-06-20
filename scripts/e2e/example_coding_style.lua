--- E2E: flow/doc/examples/coding_style.lua
---
--- Run: agent-block -s scripts/e2e/example_coding_style.lua -p .
---
--- Transport: alc_run + dofile (the example is not a registered pkg).
---
--- Flow: 2-step fixed Phase chain (design → review). orch_gatephase
--- runs each step: task_type classify + phase prompt + gate check.
--- ~6-8 LLM calls total.
---
--- Graders:
---   * agent_ok          — agent block terminated normally
---   * status_done       — example returned status="done"
---   * step_design_done  — design step reported
---   * step_review_done  — review step reported

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Use alc_run to drive the flow/doc/examples/coding_style.lua reference
example. It runs a fixed 2-step Phase chain via orch_gatephase, with
flow Frame for ReqToken-bounded boundaries.

Call alc_run with this exact Lua source (single VM):

    local ex = dofile("flow/doc/examples/coding_style.lua")
    return ex.run({
        task    = "Write a one-line bash command that prints today's date.",
        task_id = "smoke_ex_coding_style_2026_06",
        steps = {
            {
                name      = "design",
                gate      = "^OK$",
                prompt_of = function(_state, _results)
                    return "Sketch the approach in one sentence. Reply ending with OK."
                end,
            },
            {
                name      = "review",
                gate      = "^OK$",
                prompt_of = function(_state, results)
                    return "Review the design '" .. (results.design or "") ..
                           "' for correctness. Reply ending with OK."
                end,
            },
        },
    })

You will be queried by alc.llm many times via orch_gatephase. You ARE
the LLM. Respond as follows:
- task classification prompts ("Classify this software task..."): reply "feature"
- design phase prompt: provide a one-sentence sketch then "OK"
- review phase prompt: provide a brief review then "OK"
- gate evaluation prompts ("Evaluate: <output>\n\n^OK$"): reply "YES" (the output ends with OK)

When the run completes, report the alc_run final return value verbatim
(status / results). Report:
1. status — should be "done"
2. results.design — the design step output
3. results.review — the review step output

Keep replies concise. Do NOT call alc_status / alc_log_view.
]]

common.run({
    name              = "example_coding_style",
    prompt            = prompt,
    max_iterations    = 40,
    max_tokens_budget = 600000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(600000),
        common.grader_max_turns(35),
        common.grader_status_done(),
        {
            name = "step_design_done",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("design", 1, true) then return true, nil end
                return false, "design step not surfaced"
            end,
        },
        {
            name = "step_review_done",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("review", 1, true) then return true, nil end
                return false, "review step not surfaced"
            end,
        },
    },
})
