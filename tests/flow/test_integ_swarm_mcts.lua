--- Integration example: Swarm / MCTS / Gate.
---
--- Topology:
---     root_gate ─┬── ab_mcts(top-down)   ──┐
---                ├── ab_mcts(bottom-up)  ──┼─→ consensus_gate ─→ commit_gate
---                └── ab_mcts(analogical) ─┘
---               (fan-out)                  (fan-in)            (final verify)
---
--- Demonstrates the four flow primitives in a parallel + join + verify shape
--- that a single-phase chain orchestrator cannot express cleanly. The
--- driver loop (phase gating, fan-out, join) stays in user code — the
--- Light-Frame principle.
---
--- Runtime cost in production (ab_mcts + orch_gatephase un-mocked):
---   root_gate       ~2 LLM calls (generate + gate check)
---   3 × ab_mcts     3 × (2*budget+1) ≈ 3 × 17 = 51 LLM calls at budget=8
---   consensus_gate  ~2 LLM calls
---   commit_gate     ~2 LLM calls
---                   -----------
---                   ~57 calls per run. Resume-on-failure is mandatory.
---
--- The test below mocks ab_mcts and orch_gatephase so every assertion runs
--- without a real LLM. The flow wiring itself is what is under test.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local DEFAULT_APPROACHES = { "top-down", "bottom-up", "analogical" }

local function parse_pick(final_output)
    if type(final_output) ~= "string" then return nil end
    return final_output:match("pick=(branch_%d+)")
end

-- ---------------------------------------------------------------------
-- The flow-driven integration: one Flow run spanning 5 sub-phases.
-- This is what a caller would write above flow. It is intentionally
-- ~60 visible lines of driver logic; hiding it behind a helper would
-- lose the "save-on-success" explicitness at each gate.
-- ---------------------------------------------------------------------
local function run_swarm(ctx)
    local flow      = require("flow")
    local ab_mcts   = require("ab_mcts")
    local gatephase = require("orch_gatephase")

    local task    = ctx.task    or error("ctx.task required")
    local task_id = ctx.task_id or error("ctx.task_id required")
    local resume  = ctx.resume  or false

    -- One State + one ReqToken per Flow run.
    local st = flow.state_new({
        key_prefix = "swarm_mcts_gate",
        id         = task_id,
        identity   = { task = task },
        resume     = resume,
    })
    local tok = flow.token_issue(st)

    -- root_gate — validate task.
    if not flow.state_get(st, "root_ok") then
        local req = flow.token_wrap(tok, {
            slot = "root_gate",
            payload = {
                task   = task,
                phases = { {
                    name   = "root",
                    prompt = "Validate task and confirm 3 independent approaches.",
                    gate   = "^OK$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        assert(flow.token_verify(tok, out, req), "root_gate: token/slot mismatch")
        if out.status ~= "completed" then
            flow.state_set(st, "failed_at", "root_gate")
            flow.state_save(st)
            return { status = "failed", stage = "root_gate" }
        end
        flow.state_set(st, "root_ok", true)
        flow.state_set(st, "approaches", ctx.approaches or DEFAULT_APPROACHES)
        flow.state_save(st)
    end

    -- Swarm fan-out — each approach runs ab_mcts independently. The loop
    -- stays in user code by design (Light Frame: driver outside).
    local approaches = flow.state_get(st, "approaches")
    local branches   = flow.state_get(st, "branches") or {}
    for i, approach in ipairs(approaches) do
        local bkey = "branch_" .. i
        if not branches[bkey] then
            local req = flow.token_wrap(tok, {
                slot = bkey,
                payload = {
                    task      = task .. " / approach=" .. approach,
                    budget    = 8,
                    max_depth = 3,
                },
            })
            local out = ab_mcts.run(req.payload)
            assert(flow.token_verify(tok, out, req),
                "branch " .. bkey .. ": token/slot mismatch")
            branches[bkey] = {
                approach   = approach,
                answer     = out.answer,
                best_score = out.best_score,
            }
            flow.state_set(st, "branches", branches)
            flow.state_save(st)
        end
    end

    -- consensus_gate — pick the best branch.
    if not flow.state_get(st, "consensus") then
        local summary = {}
        for _, k in ipairs({ "branch_1", "branch_2", "branch_3" }) do
            local b = branches[k]
            if b then
                summary[#summary + 1] = k .. ": " .. (b.approach or "")
                    .. " → " .. tostring(b.answer)
                    .. " (score=" .. tostring(b.best_score) .. ")"
            end
        end
        local req = flow.token_wrap(tok, {
            slot = "consensus_gate",
            payload = {
                task   = "pick the best branch",
                phases = { {
                    name   = "consensus",
                    prompt = "Branches:\n" .. table.concat(summary, "\n")
                        .. "\nReturn pick=branch_N with one-line rationale.",
                    gate   = "^pick=branch_%d+$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        assert(flow.token_verify(tok, out, req), "consensus_gate: token/slot mismatch")
        flow.state_set(st, "consensus", out.final_output)
        flow.state_save(st)
    end

    -- commit_gate — final verify before returning.
    if not flow.state_get(st, "committed") then
        local req = flow.token_wrap(tok, {
            slot = "commit_gate",
            payload = {
                task   = "final commit",
                phases = { {
                    name   = "commit",
                    prompt = "Confirm the picked branch: "
                        .. tostring(flow.state_get(st, "consensus")),
                    gate   = "^COMMIT$",
                } },
            },
        })
        local out = gatephase.run(req.payload)
        assert(flow.token_verify(tok, out, req), "commit_gate: token/slot mismatch")
        flow.state_set(st, "committed", true)
        flow.state_save(st)
    end

    return {
        status   = "done",
        picked   = parse_pick(flow.state_get(st, "consensus")),
        branches = flow.state_get(st, "branches"),
    }
end

-- ---------------------------------------------------------------------
-- Test scaffolding: minimal alc + stubbed ab_mcts / orch_gatephase.
-- ---------------------------------------------------------------------
local function fresh_store() return {} end

local function install_stubs(store, options)
    options = options or {}
    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
    }
    package.loaded["ab_mcts"] = {
        run = function(payload)
            return {
                status      = "done",
                answer      = "ans-" .. payload._flow_slot,
                best_score  = 0.8 + (#payload._flow_slot / 100),
                _flow_token = payload._flow_token,
                _flow_slot  = payload._flow_slot,
            }
        end,
    }
    package.loaded["orch_gatephase"] = {
        run = function(payload)
            local slot = payload._flow_slot
            local out = {
                status       = options.gate_status or "completed",
                final_output = "OK",
                _flow_token  = payload._flow_token,
                _flow_slot   = slot,
            }
            if slot == "consensus_gate" then
                out.final_output = "pick=branch_2"
            elseif slot == "commit_gate" then
                out.final_output = "COMMIT"
            end
            if options.tamper_token_on_slot == slot then
                out._flow_token = "tampered-" .. out._flow_token
            end
            return out
        end,
    }
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

local function reset()
    _G.alc = nil
    package.loaded["ab_mcts"] = nil
    package.loaded["orch_gatephase"] = nil
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

-- ---------------------------------------------------------------------
describe("flow integ (swarm_mcts): happy path", function()
    lust.after(reset)

    it("runs all four phases end-to-end and returns the picked branch", function()
        local store = fresh_store()
        install_stubs(store)
        local out = run_swarm({ task = "demo", task_id = "r1" })
        expect(out.status).to.equal("done")
        expect(out.picked).to.equal("branch_2")
        expect(type(out.branches)).to.equal("table")
        expect(out.branches.branch_1.approach).to.equal("top-down")
        expect(out.branches.branch_2.approach).to.equal("bottom-up")
        expect(out.branches.branch_3.approach).to.equal("analogical")
    end)

    it("persists the completion flags to alc.state", function()
        local store = fresh_store()
        install_stubs(store)
        run_swarm({ task = "demo", task_id = "r2" })
        local rec = store["swarm_mcts_gate:r2"]
        expect(rec.data.root_ok).to.equal(true)
        expect(rec.data.committed).to.equal(true)
        expect(rec.data.branches.branch_1.answer).to.equal("ans-branch_1")
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (swarm_mcts): resume", function()
    lust.after(reset)

    it("skips already-completed phases on resume", function()
        local store = fresh_store()
        install_stubs(store)
        run_swarm({ task = "demo", task_id = "r3" })

        -- Re-install with a gate that would FAIL if called again. Resume
        -- must NOT re-invoke any phase because all flags are set.
        install_stubs(store, { gate_status = "refused" })
        local out = run_swarm({ task = "demo", task_id = "r3", resume = true })
        expect(out.status).to.equal("done")
        expect(out.picked).to.equal("branch_2")
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (swarm_mcts): token tampering", function()
    lust.after(reset)

    it("errors when a gate tampers with the echoed token", function()
        local store = fresh_store()
        install_stubs(store, { tamper_token_on_slot = "consensus_gate" })
        local ok, err = pcall(run_swarm, { task = "demo", task_id = "r4" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("consensus_gate", 1, true)).to_not.equal(nil)
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (swarm_mcts): root gate refusal", function()
    lust.after(reset)

    it("returns failed status when root_gate does not complete", function()
        local store = fresh_store()
        install_stubs(store, { gate_status = "refused" })
        local out = run_swarm({ task = "demo", task_id = "r5" })
        expect(out.status).to.equal("failed")
        expect(out.stage).to.equal("root_gate")
    end)
end)
