--- E2E: flow/doc/examples/coevolve_adaptive.lua
---
--- Run: agent-block -s scripts/e2e/example_coevolve_adaptive.lua -p .
---
--- Transport: alc_run + dofile (the example is not a registered pkg).
---
--- Flow: 1 round of coevolve (smallest configuration). coevolve.run is
--- the heaviest dependency in the example suite — even 1 round runs
--- problem-generation + solver + analyzer per problem. With
--- problems_per_round=2 expect ~15-25 LLM calls. Token budget set to
--- 800K with 50-turn cap.
---
--- Graders:
---   * agent_ok            — agent block terminated normally
---   * status_done         — example returned status="done"
---   * rounds_run_1        — rounds_run = 1 reported
---   * round_1_present     — history.round_1 surfaced

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Use alc_run to drive the flow/doc/examples/coevolve_adaptive.lua
reference example. It runs N rounds of coevolve with flow Frame
cross-round checkpointing. Sized small for smoke: rounds=1,
problems_per_round=2.

Call alc_run with this exact Lua source (single VM):

    local ex = dofile("flow/doc/examples/coevolve_adaptive.lua")
    return ex.run({
        task               = "simple arithmetic problems",
        task_id            = "smoke_ex_coevolve_adaptive_2026_06",
        rounds             = 1,
        problems_per_round = 2,
        difficulty_target  = 0.5,
    })

You will be queried by alc.llm many times via coevolve's Challenger /
Solver / Analyzer loop. You ARE the LLM. Respond as follows:
- Problem-generation prompts ("Generate problem #N..."): give a
  one-sentence simple arithmetic problem (e.g. "What is 7 + 8?").
- Solver prompts: think briefly and give the correct numeric answer.
- Analyzer / verdict prompts: reply CORRECT (or "Verdict: CORRECT") when
  the solution matches; PARTIAL / WRONG only if obviously wrong.
- Synthesis / answer prompts at the end: give a brief one-sentence
  summary of what was learned.

When the run completes, report the alc_run final return value verbatim:
1. status — should be "done"
2. rounds_run — should be 1
3. history — list the keys (e.g. round_1) and answer field for round_1

Keep replies concise (1-2 sentences each). Do NOT call alc_status /
alc_log_view.
]]

common.run({
    name              = "example_coevolve_adaptive",
    prompt            = prompt,
    max_iterations    = 60,
    max_tokens_budget = 800000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(800000),
        common.grader_max_turns(55),
        common.grader_status_done(),
        {
            name = "rounds_run_1",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("rounds_run", 1, true) or c:find("rounds run", 1, true) then
                    -- find a 1 near it
                    if c:find("rounds[_%s]+run[^%d]+1", 1, false) then
                        return true, nil
                    end
                    return true, "rounds_run mentioned"
                end
                return false, "rounds_run not surfaced"
            end,
        },
        {
            name = "round_1_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("round_1", 1, true) then return true, nil end
                if c:lower():find("round 1", 1, true) then return true, "round 1 reported" end
                return false, "round_1 history entry not surfaced"
            end,
        },
    },
})
