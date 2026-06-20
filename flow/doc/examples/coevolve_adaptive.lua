--- flow/doc/examples/coevolve_adaptive.lua
---
--- Example — long-running checkpoint pattern using `coevolve` per
--- round, with `flow` Frame state across rounds. Demonstrates the
--- session-spanning resume use-case for ReqToken (design-full §11.2):
--- Round r verdict cannot leak into Round r+1 slot because each Round
--- is wrapped with a distinct slot ("round_1" / "round_2" / ...) under
--- a Flow-stable token.
---
--- Why this example exists:
---   * design-full.md Recipe 04 imaginary code used
---     `f_race.prune(out.round_stats, out.all_results, ...)` which
---     does not exist — real `f_race.run({task, ...})` is end-to-end
---     and is not composable with externally-supplied per-individual
---     scores. This example therefore drops the f_race step and just
---     demonstrates the cross-round checkpoint pattern + slot-distinct
---     ReqToken protection over coevolve rounds.
---   * Long-running resume is the primary motivation for storing the
---     ReqToken value inside the state (random hex), so /clear + resume
---     re-derive the same token from persisted state.

local flow     = require("flow")
local coevolve = require("coevolve")

local M = {}

--- Run R rounds of coevolve with cross-round checkpointing.
---
--- @param ctx { task, task_id, rounds?, problems_per_round?, difficulty_target?, resume? }
--- @return { status, rounds_run, history }
function M.run(ctx)
    assert(type(ctx) == "table", "ctx required")
    local task    = assert(ctx.task,    "ctx.task required")
    local task_id = assert(ctx.task_id, "ctx.task_id required")
    local rounds  = ctx.rounds or 3
    local problems_per_round = ctx.problems_per_round or 3
    local difficulty_target  = ctx.difficulty_target or 0.5

    local state = flow.state_new({
        key_prefix = "example_coevolve_adaptive",
        id         = task_id,
        identity   = { task = task, target_rounds = rounds },
        resume     = ctx.resume or false,
    })
    local token = flow.token_issue(state)

    local history = flow.state_get(state, "history") or {}
    local start_round = (flow.state_get(state, "round") or 1)

    for r = start_round, rounds do
        local rkey = "round_" .. tostring(r)
        if not history[rkey] then
            local req = flow.token_wrap(token, {
                slot = rkey,
                payload = {
                    task               = task,
                    rounds             = 1,  -- one generation per call
                    problems_per_round = problems_per_round,
                    difficulty_target  = difficulty_target,
                },
            })
            local out = coevolve.run(req.payload)
            assert(flow.token_verify(token, out, req),
                "coevolve_adaptive: " .. rkey .. " token mismatch (cross-round leak?)")
            local out_r = flow.unwrap_result(out)
            history[rkey] = {
                answer         = out_r.answer,
                total_problems = out_r.total_problems,
                total_correct  = out_r.total_correct,
                total_partial  = out_r.total_partial,
                total_wrong    = out_r.total_wrong,
            }
            flow.state_set(state, "history", history)
            flow.state_set(state, "round",   r + 1)
            flow.state_save(state)
        end
    end

    return {
        status     = "done",
        rounds_run = rounds,
        history    = history,
    }
end

return M
