--- recipe_swarm_gate(RecipeSwarmGate) — parallel ab_mcts swarm + gate aggregation
---
--- Fills the "parallel + fan-in + verify" slot of the recipe family:
--- given a task that admits multiple independent reasoning angles,
--- spawn N `ab_mcts.run` branches with distinct approach hints (the
--- "swarm"), then collapse them through `orch_gatephase` consensus +
--- commit gates. The recipe runs on top of the `flow` Frame so
--- mid-flight checkpoint is preserved across resume; each pkg call is
--- ReqToken-wrapped at the boundary so a stale verdict from a prior
--- session cannot leak into a fresh branch slot.
---
--- ## Usage
---
--- ```lua
--- local recipe = require("recipe_swarm_gate")
--- return recipe.run({
---     task        = "Design a rate limiter for a chat API.",
---     task_id     = "rate_limiter_2026_06",
---     approaches  = { "top-down", "bottom-up", "analogical" },
---     budget      = 8,
---     max_depth   = 3,
---     resume      = false,
--- })
--- ```
---
--- ## Algorithm
---
--- 1. **root_gate** — `orch_gatephase` validates the task and confirms
---    the approach list is plausible. Gate keyword `^OK$`.
--- 2. **fan-out** — for each approach, `ab_mcts.run({task = task ..
---    " / approach=" .. approach, budget, max_depth})` runs
---    independently; results land under `state.data.branches[bkey]`.
---    Each call is `flow.token_wrap`-ed at the boundary.
--- 3. **consensus_gate** — `orch_gatephase` compares the branches'
---    `answer / best_score` triples and emits `pick=branch_N`.
--- 4. **commit_gate** — final `orch_gatephase` review against the
---    picked branch; emits `COMMIT` or fails.
---
--- ## Design rationale
---
--- This is a *recipe* (composition over algorithms), not a faithful
--- implementation of any single paper — `ab_mcts` and `orch_gatephase`
--- are the algorithm-level libs. The composition draws on:
---
---   * **ab_mcts** — implements AB-MCTS (Sakana AI 2025,
---     arXiv:2503.04412 §3 "AB-MCTS" / Algorithm 1) which explores the
---     (width × depth) reasoning tree with Thompson sampling; see the
---     pkg's own docstring for the algorithm citation. The recipe
---     fan-out treats each branch as one ab_mcts run with a distinct
---     approach hint, on the empirical observation that ensembling
---     diverse seeds lifts accuracy.
---   * **orch_gatephase** — implements the Phase-gate discipline
---     (structured verification with retry-on-fail), used here for the
---     root / consensus / commit reviews so the aggregator's verdict is
---     gate-bounded rather than a free-form pick.
---
--- The recipe assumes branch outputs are exchangeable conditional on
--- the approach hint; under that assumption the consensus pick targets
--- the highest `best_score` over the swarm. The "exchangeability +
--- consensus pick" framing is a working assumption of this recipe, not
--- a theorem derived from either paper.
---
--- ## Caveats
---
--- * Branch diversity depends entirely on the approach strings supplied
---   by the caller. With near-duplicate approach strings the swarm
---   collapses to a single mode and the consensus_gate degenerates to a
---   tie-break. The recipe does not inject a diversity penalty; if you
---   need that, route the approach list through `ensemble_div` first.
--- * `flow.token_verify` is currently a pass-through for pkg results
---   that do not echo `_flow_token` / `_flow_slot`. ab_mcts and
---   orch_gatephase do not echo as of flow v0.7.0, so the verify call
---   guards only against future-state echoes. The boundary-wrap is kept
---   so that opt-in echo support lights up automatically.
--- * Total LLM calls scale as roughly `n_approaches * budget + 2 *
---   gate_calls`. For budget=8, n_approaches=3 expect ~32-40 calls in
---   typical runs; size the deployment budget accordingly.

local S         = require("alc_shapes")
local T         = S.T
local flow      = require("flow")
local ab_mcts   = require("ab_mcts")
local gatephase = require("orch_gatephase")

local M = {}

---@type AlcMeta
M.meta = {
    name        = "recipe_swarm_gate",
    version     = "0.1.0",
    description = "Parallel ab_mcts swarm + orch_gatephase consensus + "
        .. "commit gates, composed over the flow Frame. Fills the "
        .. "Swarm slot of the recipe family — a task admitting multiple "
        .. "independent reasoning angles is fanned out to N ab_mcts "
        .. "branches with caller-supplied approach hints, then the "
        .. "branches' best answers are collapsed through structured "
        .. "Phase gates with ReqToken-bounded verification at every "
        .. "pkg boundary.",
    category    = "recipe",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task        = T.string:describe("Problem statement"),
                task_id     = T.string:describe("Stable identity used as the flow state key suffix"),
                approaches  = T.array_of(T.string):is_optional():describe(
                    "Caller-supplied approach hints (default: {\"top-down\", \"bottom-up\", \"analogical\"})"),
                budget      = T.number:is_optional():describe("ab_mcts expansion iterations per branch (default: 8)"),
                max_depth   = T.number:is_optional():describe("ab_mcts tree depth per branch (default: 3)"),
                resume      = T.boolean:is_optional():describe("Resume from prior flow state if present (default: false)"),
            }),
            result = T.shape({
                status    = T.string:describe("\"done\" / \"failed\""),
                stage     = T.string:is_optional():describe("On failure, the gate that rejected (\"root_gate\" / \"consensus_gate\" / \"commit_gate\")"),
                picked    = T.string:is_optional():describe("Consensus gate final_output (the \"pick=branch_N\" verdict text)"),
                branches  = T.map_of(T.string, T.shape({
                    approach   = T.string,
                    answer     = T.string,
                    best_score = T.number,
                    tree_stats = T.any,
                })):is_optional():describe("Per-branch ab_mcts result, keyed by branch_N"),
            }),
        },
    },
}

--- Packages composed by this recipe, in execution order.
M.ingredients = {
    "flow",            -- Frame substrate (state + ReqToken)
    "orch_gatephase",  -- root_gate / consensus_gate / commit_gate
    "ab_mcts",         -- per-approach branch search
}

--- Known failure / interpretation conditions.
M.caveats = {
    "Branch diversity is caller-controlled via the approaches array. "
        .. "Near-duplicate approach strings collapse the swarm to a single "
        .. "mode and the consensus pick degenerates to a tie-break. Route "
        .. "the approach list through ensemble_div if diversity must be "
        .. "structurally guaranteed.",
    "flow.token_verify is a soft check at flow v0.7.0 — ab_mcts and "
        .. "orch_gatephase do not echo _flow_token / _flow_slot in their "
        .. "result tables, so verify() returns true under the "
        .. "missing-echo branch. The wrap is retained so opt-in echo "
        .. "support lights up the verify the moment a pkg declares "
        .. "M.meta.flow_contract = \"v1\".",
    "consensus_gate's gate regex `^pick=branch_%d+$` rejects free-form "
        .. "verdicts. If the gate keeps failing on retry, suspect the "
        .. "approach prompts are inducing the gate model to emit "
        .. "natural-language picks instead of the structured token. Tighten "
        .. "the consensus prompt or relax the regex per task.",
    "Total LLM calls scale as roughly n_approaches * budget + 2 * "
        .. "gate_calls. Defaults give ~30-40 calls. Cost guard at the "
        .. "deployment layer is the caller's responsibility.",
}

local DEFAULT_APPROACHES = { "top-down", "bottom-up", "analogical" }

--- Run the swarm-gate recipe.
---
--- @param ctx table see M.spec.entries.run.input
--- @return table see M.spec.entries.run.result
function M.run(ctx)
    assert(type(ctx) == "table", "recipe_swarm_gate.run: ctx required")
    local task    = ctx.task    or error("recipe_swarm_gate.run: ctx.task required")
    local task_id = ctx.task_id or error("recipe_swarm_gate.run: ctx.task_id required")
    local approaches = ctx.approaches or DEFAULT_APPROACHES
    local budget     = ctx.budget    or 8
    local max_depth  = ctx.max_depth or 3
    local resume     = ctx.resume    or false

    local state = flow.state_new({
        key_prefix = "recipe_swarm_gate",
        id         = task_id,
        identity   = { task = task, n_approaches = #approaches },
        resume     = resume,
    })
    local token = flow.token_issue(state)

    -- 1. root_gate ---------------------------------------------------------
    if not flow.state_get(state, "root_ok") then
        local approach_list = table.concat(approaches, ", ")
        local req = flow.token_wrap(token, {
            slot = "root_gate",
            payload = {
                task = task,
                phases = { {
                    name   = "root",
                    prompt = "Validate task and confirm these approaches are "
                          .. "plausible: " .. approach_list .. ". "
                          .. "Reply OK if all are usable, otherwise NO.",
                    gate   = "^OK$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        if not flow.token_verify(token, out, req) then
            error("recipe_swarm_gate: root_gate token mismatch")
        end
        local out_r = flow.unwrap_result(out)
        if out_r.status ~= "completed" then
            flow.state_set(state, "failed_at", "root_gate")
            flow.state_save(state)
            return { status = "failed", stage = "root_gate" }
        end
        flow.state_set(state, "root_ok", true)
        flow.state_save(state)
    end

    -- 2. fan-out -----------------------------------------------------------
    local branches = flow.state_get(state, "branches") or {}
    for i, approach in ipairs(approaches) do
        local bkey = "branch_" .. tostring(i)
        if not branches[bkey] then
            local req = flow.token_wrap(token, {
                slot = bkey,
                payload = {
                    task      = task .. " / approach=" .. approach,
                    budget    = budget,
                    max_depth = max_depth,
                },
            })
            local out = ab_mcts.run(req.payload)
            if not flow.token_verify(token, out, req) then
                error("recipe_swarm_gate: branch " .. bkey .. " token mismatch")
            end
            local out_r = flow.unwrap_result(out)
            branches[bkey] = {
                approach   = approach,
                answer     = out_r.answer,
                best_score = out_r.best_score,
                tree_stats = out_r.tree_stats,
            }
            flow.state_set(state, "branches", branches)
            flow.state_save(state)
        end
    end

    -- 3. consensus_gate ----------------------------------------------------
    if not flow.state_get(state, "consensus") then
        local summary_lines = {}
        for i = 1, #approaches do
            local b = branches["branch_" .. tostring(i)]
            summary_lines[#summary_lines + 1] = string.format(
                "branch_%d (approach=%s, best_score=%.3f): %s",
                i, b.approach, b.best_score or 0, b.answer or "")
        end
        local req = flow.token_wrap(token, {
            slot = "consensus_gate",
            payload = {
                task = "Pick the best branch.",
                phases = { {
                    name   = "consensus",
                    prompt = "Compare these branches and pick the strongest. "
                          .. "Reply with exactly `pick=branch_N`.\n\n"
                          .. table.concat(summary_lines, "\n"),
                    gate   = "^pick=branch_%d+$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        if not flow.token_verify(token, out, req) then
            error("recipe_swarm_gate: consensus_gate token mismatch")
        end
        local out_r = flow.unwrap_result(out)
        if out_r.status ~= "completed" then
            flow.state_set(state, "failed_at", "consensus_gate")
            flow.state_save(state)
            return { status = "failed", stage = "consensus_gate", branches = branches }
        end
        flow.state_set(state, "consensus", out_r.final_output)
        flow.state_save(state)
    end

    -- 4. commit_gate -------------------------------------------------------
    if not flow.state_get(state, "committed") then
        local req = flow.token_wrap(token, {
            slot = "commit_gate",
            payload = {
                task = "Final commit review.",
                phases = { {
                    name   = "commit",
                    prompt = "Review the picked branch and reply COMMIT if "
                          .. "the answer is acceptable, otherwise NO.\n\n"
                          .. "Pick: " .. tostring(flow.state_get(state, "consensus")),
                    gate   = "^COMMIT$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        if not flow.token_verify(token, out, req) then
            error("recipe_swarm_gate: commit_gate token mismatch")
        end
        local out_r = flow.unwrap_result(out)
        if out_r.status ~= "completed" then
            flow.state_set(state, "failed_at", "commit_gate")
            flow.state_save(state)
            return {
                status   = "failed",
                stage    = "commit_gate",
                picked   = flow.state_get(state, "consensus"),
                branches = branches,
            }
        end
        flow.state_set(state, "committed", true)
        flow.state_save(state)
    end

    return {
        status   = "done",
        picked   = flow.state_get(state, "consensus"),
        branches = branches,
    }
end

if S and S.instrument then
    M.run = S.instrument(M, "run")
end

return M
