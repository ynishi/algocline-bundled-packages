--- E2E: flow/doc/examples/ensemble_vote.lua
---
--- Run: agent-block -s scripts/e2e/example_ensemble_vote.lua -p .
---
--- Transport: alc_run (NOT alc_advice). The example lives at
--- flow/doc/examples/ensemble_vote.lua — not a registered alc pkg —
--- so we `dofile()` it from inside the alc VM. agent-block / alc start
--- with project_root as CWD; the relative dofile path resolves there.
---
--- Flow: 2 perspectives via bare alc.llm (through flow.llm wrap) +
--- ensemble_div.decompose (pure) + condorcet.prob_majority /
--- is_anti_jury (pure). Tiny: 2 LLM calls total.
---
--- Graders:
---   * agent_ok           — agent block terminated normally
---   * status_done        — example returned status="done"
---   * aggregated_present — aggregated numeric value surfaced
---   * health_reported    — vote_health (p_majority / anti_jury) surfaced

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Use alc_run to drive the flow/doc/examples/ensemble_vote.lua reference
example on a tiny numeric estimation task.

Call alc_run with this exact Lua source string (single VM; the example
uses flow + ensemble_div + condorcet which are all installed pkg):

    local ex = dofile("flow/doc/examples/ensemble_vote.lua")
    return ex.run({
        task           = "Estimate the value of X where X = 17 + 25.",
        task_id        = "smoke_ex_ensemble_vote_2026_06",
        perspectives   = { "analytical", "pragmatic" },
        ground_truth   = 42,
        voter_accuracy = 0.7,
    })

You will be queried by alc.llm twice (one per perspective). You ARE the
LLM. For each prompt, reply with a single number close to 42 (analytical
might say 42, pragmatic 41 or 43 — slight disagreement is fine, but
don't drift far). The example expects numeric output to parse.

When the run completes, report the alc_run final return value verbatim
(the fields aggregated / decomp / vote_health / status). In particular
report:

1. status — should be "done"
2. aggregated — the weighted-mean prediction (a number near 42)
3. vote_health.p_majority — Condorcet probability
4. vote_health.anti_jury — should be false (since p_hat=0.7 > 0.5)

Do NOT call alc_status / alc_log_view. Keep replies concise.
]]

common.run({
    name              = "example_ensemble_vote",
    prompt            = prompt,
    max_iterations    = 15,
    max_tokens_budget = 200000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "status_done",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):gsub("[%*`_~\"]", ""):lower()
                if c:find("status%s*[:=]%s*done", 1, false) then return true, nil end
                if c:find("status%s*[:=]%s*regen", 1, false) then
                    return false, "status=regen_required (anti_jury or zero diversity)"
                end
                return false, "status=done not surfaced"
            end,
        },
        {
            name = "aggregated_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:lower():find("aggregated", 1, true) and c:find("4[0-3]") then
                    return true, nil
                end
                return false, "aggregated near 42 not reported"
            end,
        },
        {
            name = "health_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if (c:find("p_majority", 1, true) or c:find("p majority", 1, true))
                    and c:find("anti_jury", 1, true) then
                    return true, nil
                end
                return false, "vote_health fields not surfaced"
            end,
        },
    },
})
