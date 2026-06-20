--- flow/doc/examples/cascade_prune.lua
---
--- Example — combine `cascade` (per-perspective LLM-internal cascade)
--- with a final `orch_gatephase` pick, using `flow` substrate for
--- checkpointed state + ReqToken-bounded boundaries.
---
--- Why this example exists:
---   * design-full.md Recipe 02 imaginary code paired `cascade` with a
---     non-existent `cs_pruner.prune(scores, rubric)` API; the real
---     `cs_pruner` is an end-to-end LLM-coupled pkg with `task` input
---     and is not composable with externally-supplied scores. This
---     example sticks to APIs that actually exist as of bundled v
---     consistent with `cascade` v0.x and `orch_gatephase` v0.x.
---   * Demonstrates the "mixed" pattern: LLM-internal pkg (`cascade`)
---     per item + structured Phase gate for final pick.
---
--- Not bundled — reference impl for doc.

local flow      = require("flow")
local cascade   = require("cascade")
local gatephase = require("orch_gatephase")

local M = {}

--- Run cascade per perspective + gate-pick the best.
---
--- @param ctx { task, task_id, perspectives, threshold?, max_level?, resume? }
--- @return { status, picked?, scores, stage? }
function M.run(ctx)
    assert(type(ctx) == "table", "ctx required")
    local task         = assert(ctx.task,    "ctx.task required")
    local task_id      = assert(ctx.task_id, "ctx.task_id required")
    local perspectives = ctx.perspectives or { "analytical", "pragmatic", "contrarian" }
    local threshold    = ctx.threshold or 0.8
    local max_level    = ctx.max_level or 3

    local state = flow.state_new({
        key_prefix = "example_cascade_prune",
        id         = task_id,
        identity   = { task = task, n = #perspectives },
        resume     = ctx.resume or false,
    })
    local token = flow.token_issue(state)

    local scores = flow.state_get(state, "scores") or {}
    for i, persp in ipairs(perspectives) do
        local pkey = "persp_" .. tostring(i)
        if not scores[pkey] then
            local req = flow.token_wrap(token, {
                slot = pkey,
                payload = {
                    task      = "[" .. persp .. " perspective] " .. task,
                    threshold = threshold,
                    max_level = max_level,
                },
            })
            local out = cascade.run(req.payload)
            assert(flow.token_verify(token, out, req),
                "cascade_prune: " .. pkey .. " token mismatch")
            local out_r = flow.unwrap_result(out)
            scores[pkey] = {
                perspective = persp,
                answer      = out_r.answer,
                confidence  = out_r.confidence,
                level_used  = out_r.level_used,
            }
            flow.state_set(state, "scores", scores)
            flow.state_save(state)
        end
    end

    if not flow.state_get(state, "picked") then
        local summary = {}
        for i = 1, #perspectives do
            local s = scores["persp_" .. tostring(i)]
            summary[#summary + 1] = string.format(
                "persp_%d (%s, conf=%.2f, lvl=%d): %s",
                i, s.perspective, s.confidence, s.level_used, s.answer)
        end
        local req = flow.token_wrap(token, {
            slot = "final_pick",
            payload = {
                task = "Pick best perspective",
                phases = { {
                    name   = "pick",
                    prompt = "Pick the most reliable perspective. Reply "
                          .. "`pick=persp_N`.\n\n" .. table.concat(summary, "\n"),
                    gate   = "^pick=persp_%d+$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        assert(flow.token_verify(token, out, req),
            "cascade_prune: final_pick token mismatch")
        local out_r = flow.unwrap_result(out)
        if out_r.status ~= "completed" then
            flow.state_set(state, "stage", "final_pick")
            flow.state_save(state)
            return { status = "failed", stage = "final_pick", scores = scores }
        end
        flow.state_set(state, "picked", out_r.final_output)
        flow.state_save(state)
    end

    return {
        status = "done",
        picked = flow.state_get(state, "picked"),
        scores = scores,
    }
end

return M
