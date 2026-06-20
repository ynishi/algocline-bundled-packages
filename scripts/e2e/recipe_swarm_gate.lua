--- E2E: recipe_swarm_gate (parallel ab_mcts swarm + orch_gatephase
--- consensus + commit, composed over the flow Frame).
---
--- Run: agent-block -s scripts/e2e/recipe_swarm_gate.lua -p .
---
--- Flow:
---   1. root_gate     — orch_gatephase validates the approach list (^OK$)
---   2. fan-out       — ab_mcts.run × N approaches (each: ~budget+1 calls
---                      for thought generation + a few self-eval calls)
---   3. consensus     — orch_gatephase picks the strongest branch
---                      (^pick=branch_%d+$)
---   4. commit        — orch_gatephase final review (^COMMIT$)
---
--- Sized small for smoke: 2 approaches × budget=4 × max_depth=2 — keeps
--- the ReAct turn count and cumulative tokens bounded. ab_mcts + the 3
--- gates together still drive ~40-60 `needs_response` turns on Haiku, so
--- the budget grader is set to 1.5M to leave headroom for ReAct context.
---
--- Graders:
---   * agent_ok            — agent block terminated normally
---   * max_tokens(1.5M)    — cumulative token guard (ReAct context O(N^2))
---   * max_turns(80)       — turn-count guard
---   * status_done         — final result.status == "done"
---   * picked_branch       — pick=branch_N surfaced
---   * branches_reported   — both branch_1 + branch_2 referenced
---   * answer_42_present   — task is "17 + 25"; final answer must be 42

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task    = "What is 17 + 25? Answer with just the number.",
    task_id = "smoke_recipe_swarm_gate_2026_06",
    opts = {
        approaches = { "direct", "step-by-step" },
        budget     = 4,
        max_depth  = 2,
    },
}

local prompt = string.format([[
Use algocline to run the recipe_swarm_gate recipe on a simple arithmetic
question. This recipe orchestrates a *parallel* swarm of ab_mcts branches
+ orch_gatephase consensus + commit gates, composed over the flow Frame.

Call alc_advice with:
- package: "recipe_swarm_gate"
- entry: "run"
- task: %q
- opts: {
    task_id    = %q,
    approaches = { "direct", "step-by-step" },
    budget     = %d,
    max_depth  = %d,
  }

You will be queried by alc.llm many times. You ARE the LLM. Reply through
alc_continue with status "needs_response":
- Reasoning / thought-generation prompts: think briefly, give the
  arithmetic answer 42 confidently. Be consistent across all branches —
  17 + 25 = 42 every time.
- orch_gatephase root_gate: reply OK (the approaches "direct" and
  "step-by-step" are clearly plausible for arithmetic).
- orch_gatephase consensus_gate: reply with exactly `pick=branch_1`
  (either branch is fine; commit to one).
- orch_gatephase commit_gate: reply COMMIT.
- Score / self-eval prompts: rate the answer 42 highly (~0.9).

When the recipe completes, report DIRECTLY from the alc_advice payload:
1. status         — "done" or "failed"
2. picked         — the consensus gate's final_output (e.g. "pick=branch_1")
3. branches       — list each branch key (branch_1, branch_2) with its
                    approach name and the answer string

IMPORTANT:
- Keep replies concise — this is a smoke test, not a benchmark.
- Do NOT call alc_status / alc_log_view / other diagnostic MCP tools.
- Do NOT modify the opts above.
]],
    params.task,
    params.task_id,
    params.opts.budget,
    params.opts.max_depth
)

common.run({
    name              = "recipe_swarm_gate",
    prompt            = prompt,
    params            = params,
    max_iterations    = 80,
    max_tokens_budget = 1500000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(1500000),
        common.grader_max_turns(75),
        common.grader_status_done(),
        {
            name = "picked_branch",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("pick=branch_%d+") then
                    return true, nil
                end
                if c:lower():find("picked", 1, true) and c:find("branch_%d+") then
                    return true, "branch_N referenced near 'picked'"
                end
                return false, "pick=branch_N not surfaced in report"
            end,
        },
        {
            name = "branches_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                local has_b1 = c:find("branch_1", 1, true) ~= nil
                local has_b2 = c:find("branch_2", 1, true) ~= nil
                if has_b1 and has_b2 then
                    return true, nil
                end
                return false, string.format(
                    "branches missing (branch_1=%s, branch_2=%s)",
                    tostring(has_b1), tostring(has_b2)
                )
            end,
        },
        {
            name = "answer_42_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("%f[%d]42%f[%D]") then
                    return true, nil
                end
                return false, "answer '42' not surfaced — branch consistency suspect"
            end,
        },
    },
})
