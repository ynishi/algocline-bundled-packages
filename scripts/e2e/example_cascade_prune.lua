--- E2E: flow/doc/examples/cascade_prune.lua
---
--- Run: agent-block -s scripts/e2e/example_cascade_prune.lua -p .
---
--- Transport: alc_run + dofile (the example is not a registered pkg).
---
--- Flow: 1 perspective via cascade (Level 1 only, high threshold to avoid
--- escalation) + final gate-pick via orch_gatephase. Sized small for smoke:
--- cascade.run with max_level=1 makes ~1-2 LLM calls; orch_gatephase
--- final_pick adds task_classify + phase + gate ≈ 3 calls. Total ~5-7.
---
--- Graders:
---   * agent_ok       — agent block terminated normally
---   * status_done    — example returned status="done"
---   * picked_persp   — pick=persp_N surfaced

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Use alc_run to drive the flow/doc/examples/cascade_prune.lua reference
example. It runs cascade per perspective + an orch_gatephase final-pick.

Call alc_run with this exact Lua source (single VM):

    local ex = dofile("flow/doc/examples/cascade_prune.lua")
    return ex.run({
        task         = "What is 17 + 25? Answer with just the number.",
        task_id      = "smoke_ex_cascade_prune_2026_06",
        perspectives = { "direct" },
        threshold    = 0.9,
        max_level    = 1,
    })

You will be queried by alc.llm several times. You ARE the LLM. Respond:
- cascade Level 1 prompt (asks for an answer): reply with "42" and append
    CONFIDENCE: 0.95
  on a new line. The high confidence prevents escalation.
- task classification prompts: reply "feature"
- final_pick phase prompt: reply "pick=persp_1"
- gate evaluation prompts ("Evaluate: <out>\n\n^pick=persp_%d+$"): reply YES

When the run completes, report the alc_run final return value verbatim.
Report:
1. status — should be "done"
2. picked — should contain "pick=persp_1"
3. scores.persp_1.answer — should be "42"

Keep replies concise. Do NOT call alc_status / alc_log_view.
]]

common.run({
    name              = "example_cascade_prune",
    prompt            = prompt,
    max_iterations    = 30,
    max_tokens_budget = 400000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(400000),
        common.grader_max_turns(25),
        common.grader_status_done(),
        {
            name = "picked_persp",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("pick=persp_%d+") then return true, nil end
                if c:lower():find("picked", 1, true) and c:find("persp_%d+") then
                    return true, "persp_N near 'picked'"
                end
                return false, "pick=persp_N not surfaced"
            end,
        },
    },
})
