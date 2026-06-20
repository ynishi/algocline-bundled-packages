--- Tests for recipe_swarm_gate (parallel ab_mcts swarm + gate aggregation)
--- Mocked alc.llm / alc.state; no real API calls.
---
--- Scenario coverage:
---   * happy  — root + 3 branches + consensus + commit all PASS, result.status = "done".
---   * root_fail   — root_gate emits NO, recipe returns {status="failed", stage="root_gate"}.
---   * consensus_fail — consensus gate emits free-form (gate regex fails), recipe returns failed.
---   * resume — second invocation skips already-completed slots.

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ---------------------------------------------------------------------
-- Mock harness
-- ---------------------------------------------------------------------

--- Patch `_G.alc.llm` and the bundled pkg run fns. We patch the pkgs
--- (ab_mcts.run / orch_gatephase.run) rather than alc.llm directly
--- because both pkgs internally make many LLM calls, and the recipe
--- only cares about their final return shape.
local function mock_env(opts)
    -- alc primitive (state KV + log + llm pass-through).
    local store = {}
    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
        llm = function() return "" end,  -- not consumed by recipe directly
    }

    -- Patch loaded pkgs.
    local ab_mcts   = require("ab_mcts")
    local gatephase = require("orch_gatephase")

    local branch_log = {}
    ab_mcts.run = function(input)
        branch_log[#branch_log + 1] = input
        return opts.ab_mcts(input, #branch_log)
    end

    local gate_log = {}
    gatephase.run = function(input)
        gate_log[#gate_log + 1] = input
        return opts.gatephase(input, #gate_log)
    end

    return { store = store, branch_log = branch_log, gate_log = gate_log }
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({
        "recipe_swarm_gate",
        "flow", "flow.util", "flow.state", "flow.token", "flow.llm", "flow.ir",
        "ab_mcts", "orch_gatephase",
    }) do
        package.loaded[k] = nil
    end
end

local function phase_name(input)
    if input and input.phases and input.phases[1] then
        return input.phases[1].name
    end
    return ""
end

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

describe("recipe_swarm_gate", function()

    it("happy path — root OK, 3 branches, consensus pick, commit OK", function()
        reset()
        local _h = mock_env({
            ab_mcts = function(input, i)
                return {
                    answer     = "answer_" .. tostring(i),
                    best_path  = { "step1", "step2" },
                    best_score = 0.7 + 0.05 * i,
                    tree_stats = {
                        total_nodes = 10, budget = input.budget,
                        wider_decisions = 3, deeper_decisions = 4,
                        max_depth = input.max_depth, branching_ratio = 0.4,
                    },
                }
            end,
            gatephase = function(input, _)
                local pn = phase_name(input)
                local out
                if pn == "root" then
                    out = "OK"
                elseif pn == "consensus" then
                    out = "pick=branch_2"
                else  -- commit
                    out = "COMMIT"
                end
                return {
                    status         = "completed",
                    task_type      = "feature",
                    skipped_phases = {},
                    phases         = { { name = pn, output = out, gate_passed = true, attempts = 1 } },
                    final_output   = out,
                    total_llm_calls = 1,
                }
            end,
        })

        local recipe = require("recipe_swarm_gate")
        local res = recipe.run({
            task    = "Design a rate limiter",
            task_id = "happy_1",
        })

        expect(res.status).to.equal("done")
        expect(res.picked).to.equal("pick=branch_2")
        expect(res.branches.branch_1).to_not.equal(nil)
        expect(res.branches.branch_2).to_not.equal(nil)
        expect(res.branches.branch_3).to_not.equal(nil)
        expect(res.branches.branch_1.approach).to.equal("top-down")
        expect(res.branches.branch_2.approach).to.equal("bottom-up")
        expect(res.branches.branch_3.approach).to.equal("analogical")
    end)

    it("root_gate fail — gatephase status='failed', recipe returns failed/root_gate", function()
        reset()
        mock_env({
            ab_mcts = function() error("ab_mcts must not be called on root_fail") end,
            gatephase = function(input, _)
                return {
                    status         = "failed",
                    task_type      = "feature",
                    skipped_phases = {},
                    phases         = { { name = phase_name(input), output = "NO", gate_passed = false, attempts = 3 } },
                    final_output   = "NO",
                    total_llm_calls = 3,
                }
            end,
        })
        local recipe = require("recipe_swarm_gate")
        local res = recipe.run({ task = "x", task_id = "root_fail_1" })
        expect(res.status).to.equal("failed")
        expect(res.stage).to.equal("root_gate")
    end)

    it("consensus_gate fail — recipe returns failed/consensus_gate with branches", function()
        reset()
        mock_env({
            ab_mcts = function(input, i)
                return {
                    answer     = "a" .. i,
                    best_path  = {},
                    best_score = 0.5,
                    tree_stats = { total_nodes = 1, budget = input.budget, wider_decisions = 0, deeper_decisions = 0, max_depth = input.max_depth, branching_ratio = 0 },
                }
            end,
            gatephase = function(input, _)
                local pn = phase_name(input)
                if pn == "root" then
                    return { status = "completed", task_type = "feature", skipped_phases = {}, phases = { { name = pn, output = "OK", gate_passed = true, attempts = 1 } }, final_output = "OK", total_llm_calls = 1 }
                end
                -- consensus: gate fails
                return { status = "failed", task_type = "feature", skipped_phases = {}, phases = { { name = pn, output = "I cannot decide", gate_passed = false, attempts = 3 } }, final_output = "I cannot decide", total_llm_calls = 3 }
            end,
        })
        local recipe = require("recipe_swarm_gate")
        local res = recipe.run({ task = "x", task_id = "cons_fail_1", approaches = { "a", "b" } })
        expect(res.status).to.equal("failed")
        expect(res.stage).to.equal("consensus_gate")
        expect(res.branches.branch_1).to_not.equal(nil)
        expect(res.branches.branch_2).to_not.equal(nil)
    end)

    it("resume — second invocation reuses persisted state, no fresh pkg calls", function()
        reset()
        local h = mock_env({
            ab_mcts = function(input, i)
                return {
                    answer     = "ans_" .. i,
                    best_path  = {},
                    best_score = 0.8,
                    tree_stats = { total_nodes = 1, budget = input.budget, wider_decisions = 0, deeper_decisions = 0, max_depth = input.max_depth, branching_ratio = 0 },
                }
            end,
            gatephase = function(input, _)
                local pn = phase_name(input)
                local out = pn == "root" and "OK" or (pn == "consensus" and "pick=branch_1" or "COMMIT")
                return { status = "completed", task_type = "feature", skipped_phases = {}, phases = { { name = pn, output = out, gate_passed = true, attempts = 1 } }, final_output = out, total_llm_calls = 1 }
            end,
        })

        local recipe = require("recipe_swarm_gate")
        local r1 = recipe.run({ task = "t", task_id = "resume_1", approaches = { "a" } })
        expect(r1.status).to.equal("done")
        local calls_after_first = #h.branch_log + #h.gate_log

        -- Second invocation with resume=true must short-circuit every slot.
        local r2 = recipe.run({ task = "t", task_id = "resume_1", approaches = { "a" }, resume = true })
        expect(r2.status).to.equal("done")
        expect(r2.picked).to.equal("pick=branch_1")
        expect(#h.branch_log + #h.gate_log).to.equal(calls_after_first)
    end)

end)
