--- flow/doc/examples/coding_style.lua
---
--- Example — sequential Phase chain reference (coding_orch style).
--- Demonstrates that a fixed multi-step pipeline can be expressed
--- with just `flow.state` + `flow.token_wrap/verify` + a plain
--- `for` loop, without any "Step / Loop / Phase" Entity inside flow.
---
--- Why this example exists (design-full Recipe 99):
---   * Not bundled as a recipe pkg — fixed-chain orchestrators are
---     application-level concerns (cf. coding_orch in agent-profiles).
---   * The example confirms the design choice in §1 P5 (Light Frame
---     — driver loop stays in user code) by exhibiting an idiomatic
---     pure-Lua chain over the substrate.

local flow      = require("flow")
local gatephase = require("orch_gatephase")

local M = {}

--- Run a fixed Phase chain.
---
--- @param ctx { task, task_id, steps, resume? }
---   steps = { { name, prompt_of(state), gate }, ... }
--- @return { status, results, stage? }
function M.run(ctx)
    assert(type(ctx) == "table", "ctx required")
    local task    = assert(ctx.task,    "ctx.task required")
    local task_id = assert(ctx.task_id, "ctx.task_id required")
    local steps   = assert(ctx.steps,   "ctx.steps required")

    local state = flow.state_new({
        key_prefix = "example_coding_style",
        id         = task_id,
        identity   = { task = task, n_steps = #steps },
        resume     = ctx.resume or false,
    })
    local token = flow.token_issue(state)

    local results = flow.state_get(state, "results") or {}

    for _, step in ipairs(steps) do
        if not flow.state_get(state, "done_" .. step.name) then
            local prompt = step.prompt_of(state, results)
            local req = flow.token_wrap(token, {
                slot = step.name,
                payload = {
                    task = task,
                    phases = { {
                        name   = step.name,
                        prompt = prompt,
                        gate   = step.gate,
                    } },
                },
            })
            local out = gatephase.run(req.payload)
            assert(flow.token_verify(token, out, req),
                "coding_style: " .. step.name .. " token mismatch")
            local out_r = out.result or out
            if out_r.status ~= "completed" then
                flow.state_set(state, "failed_at", step.name)
                flow.state_save(state)
                return { status = "failed", stage = step.name, results = results }
            end
            results[step.name] = out_r.final_output
            flow.state_set(state, "results",            results)
            flow.state_set(state, "done_" .. step.name, true)
            flow.state_save(state)
        end
    end

    return { status = "done", results = results }
end

return M
