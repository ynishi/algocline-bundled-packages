--- flow/doc/examples/ensemble_vote.lua
---
--- Example — N perspectives via bare `alc.llm` (through `flow.llm`) +
--- pure-calculation pkg chain (`ensemble_div.decompose` + `condorcet
--- .prob_majority` / `is_anti_jury`) for diversity / majority-vote
--- health checks.
---
--- Why this example exists:
---   * design-full.md Recipe 03 — the use-case for `flow.llm` helper
---     (bare LLM call with ReqToken contract). Demonstrates that pure
---     compute pkg need not pass through the Token boundary.
---   * Not bundled — `recipe_quick_vote` (SPRT) and `recipe_safe_panel`
---     (fixed-n Condorcet) already fill the "majority vote" recipe
---     slots; this example focuses on the diversity-decomposition axis.

local flow      = require("flow")
local ed        = require("ensemble_div")
local condorcet = require("condorcet")

local M = {}

local function parse_number(s)
    if type(s) == "number" then return s end
    if type(s) ~= "string" then return nil end
    return tonumber(s:match("[-+]?%d*%.?%d+"))
end

--- Generate predictions across perspectives + check ensemble health.
---
--- @param ctx { task, task_id, perspectives, ground_truth?, voter_accuracy?, weights?, resume? }
--- @return { status, aggregated?, decomp?, vote_health, preds }
function M.run(ctx)
    assert(type(ctx) == "table", "ctx required")
    local task         = assert(ctx.task,    "ctx.task required")
    local task_id      = assert(ctx.task_id, "ctx.task_id required")
    local perspectives = ctx.perspectives or { "analytical", "pragmatic", "contrarian" }

    local state = flow.state_new({
        key_prefix = "example_ensemble_vote",
        id         = task_id,
        identity   = { task = task, n = #perspectives },
        resume     = ctx.resume or false,
    })
    local token = flow.token_issue(state)

    -- 1. Bare LLM per perspective (flow.llm wraps the boundary).
    local preds = flow.state_get(state, "preds") or {}
    for i, persp in ipairs(perspectives) do
        local pkey = "persp_" .. tostring(i)
        if preds[pkey] == nil then
            local prompt = "[" .. persp .. " perspective]\n" .. task
                .. "\nAnswer as a single number."
            local out = flow.llm({ token = token, slot = pkey, prompt = prompt })
            local n = parse_number(out)
            preds[pkey] = n or 0
            flow.state_set(state, "preds", preds)
            flow.state_save(state)
        end
    end

    local preds_array = {}
    for i = 1, #perspectives do
        preds_array[i] = preds["persp_" .. tostring(i)]
    end

    -- 2. Pure calc: diversity decomposition (only when ground_truth supplied).
    local decomp
    if ctx.ground_truth then
        decomp = ed.decompose(preds_array, ctx.ground_truth)
        flow.state_set(state, "decomp", decomp)
    end

    -- 3. Pure calc: Condorcet majority-vote health.
    local p_hat = ctx.voter_accuracy or 0.65
    local vote_health = {
        p_hat      = p_hat,
        p_majority = condorcet.prob_majority(#perspectives, p_hat),
        anti_jury  = condorcet.is_anti_jury(p_hat),
    }
    flow.state_set(state, "vote_health", vote_health)
    flow.state_save(state)

    -- 4. Aggregate iff health passes.
    if vote_health.anti_jury or (decomp and decomp.A_bar < 1e-6) then
        return {
            status = "regen_required",
            preds  = preds,
            decomp = decomp,
            vote_health = vote_health,
        }
    end

    local weights = ctx.weights
    local sum, wsum = 0, 0
    for i, v in ipairs(preds_array) do
        local w = (weights and weights[i]) or (1 / #preds_array)
        sum  = sum  + w * v
        wsum = wsum + w
    end
    local aggregated = wsum > 0 and (sum / wsum) or 0
    flow.state_set(state, "aggregated", aggregated)
    flow.state_save(state)

    return {
        status      = "done",
        aggregated  = aggregated,
        decomp      = decomp,
        vote_health = vote_health,
        preds       = preds,
    }
end

return M
