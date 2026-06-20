--- Tests for flow/doc/examples/{cascade_prune,ensemble_vote,
--- coevolve_adaptive,coding_style}.lua — mock alc.llm + patched pkg
--- runs; walks each example end-to-end and confirms ReqToken slot
--- isolation across rounds / perspectives / phases.

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
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;"
    .. REPO .. "/flow/doc/?.lua;" .. REPO .. "/flow/doc/?/init.lua;"
    .. package.path

local function mock_alc(llm_fn)
    local store = {}
    local log = {}
    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
        llm = function(prompt, opts)
            log[#log + 1] = { prompt = prompt, opts = opts }
            if llm_fn then return llm_fn(prompt, opts, #log) end
            return ""
        end,
    }
    return { store = store, log = log }
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({
        "examples.cascade_prune", "examples.ensemble_vote",
        "examples.coevolve_adaptive", "examples.coding_style",
        "flow", "flow.util", "flow.state", "flow.token", "flow.llm", "flow.ir",
        "cascade", "orch_gatephase", "ensemble_div", "condorcet", "coevolve",
    }) do
        package.loaded[k] = nil
    end
end

-- ---------------------------------------------------------------------
-- cascade_prune
-- ---------------------------------------------------------------------

describe("flow/doc/examples/cascade_prune", function()
    it("happy path — 3 perspectives + gate pick", function()
        reset()
        mock_alc()
        local cascade   = require("cascade")
        local gatephase = require("orch_gatephase")
        cascade.run = function(input)
            return {
                answer     = "ans for " .. input.task:sub(1, 16),
                confidence = 0.9,
                level_used = 1,
                max_level  = input.max_level,
                threshold  = input.threshold,
                escalated  = false,
                history    = {},
            }
        end
        gatephase.run = function(_)
            return {
                status = "completed", task_type = "feature",
                skipped_phases = {},
                phases = { { name = "pick", output = "pick=persp_2", gate_passed = true, attempts = 1 } },
                final_output = "pick=persp_2",
                total_llm_calls = 1,
            }
        end
        local ex = require("examples.cascade_prune")
        local r = ex.run({ task = "x", task_id = "cp_1" })
        expect(r.status).to.equal("done")
        expect(r.picked).to.equal("pick=persp_2")
        expect(r.scores.persp_1.perspective).to.equal("analytical")
        expect(r.scores.persp_3.perspective).to.equal("contrarian")
    end)
end)

-- ---------------------------------------------------------------------
-- ensemble_vote
-- ---------------------------------------------------------------------

describe("flow/doc/examples/ensemble_vote", function()
    it("happy path — 3 bare LLM perspectives + decomp + aggregate", function()
        reset()
        -- LLM mock returns a number per call; ground_truth = 10
        mock_alc(function(prompt, _, idx)
            local mapping = { 9, 10, 11 }
            local val = mapping[idx] or 10
            -- echo flow_token/slot tags so verify path is exercised
            local tok = prompt:match("%[flow_token=([^%]]+)%]") or "tok"
            local slot = prompt:match("%[flow_slot=([^%]]+)%]") or "slot"
            return tostring(val) .. "\n[flow_token=" .. tok .. "][flow_slot=" .. slot .. "]"
        end)
        local ex = require("examples.ensemble_vote")
        local r = ex.run({
            task = "Estimate X", task_id = "ev_1",
            ground_truth = 10, voter_accuracy = 0.7,
        })
        expect(r.status).to.equal("done")
        expect(r.aggregated).to.equal(10)  -- (9+10+11)/3
        expect(r.decomp.identity_holds).to.equal(true)
        expect(r.vote_health.anti_jury).to.equal(false)
    end)

    it("regen_required — anti_jury (p<0.5) short-circuits", function()
        reset()
        mock_alc(function(_, _, idx)
            return tostring(idx)
        end)
        local ex = require("examples.ensemble_vote")
        local r = ex.run({
            task = "x", task_id = "ev_2",
            voter_accuracy = 0.4,  -- anti-jury
        })
        expect(r.status).to.equal("regen_required")
        expect(r.vote_health.anti_jury).to.equal(true)
    end)
end)

-- ---------------------------------------------------------------------
-- coevolve_adaptive
-- ---------------------------------------------------------------------

describe("flow/doc/examples/coevolve_adaptive", function()
    it("happy path — R rounds checkpointed, slot-distinct per round", function()
        reset()
        mock_alc()
        local coevolve = require("coevolve")
        local seen_slots = {}
        coevolve.run = function(input)
            -- The recipe embeds _flow_slot in payload (via flow.token_wrap).
            seen_slots[#seen_slots + 1] = input._flow_slot
            return {
                answer        = "ans_" .. input._flow_slot,
                round_stats   = {},
                total_problems = 3,
                total_correct  = 2,
                total_partial  = 0,
                total_wrong    = 1,
                all_results    = {},
            }
        end
        local ex = require("examples.coevolve_adaptive")
        local r = ex.run({ task = "domain X", task_id = "ce_1", rounds = 3 })
        expect(r.status).to.equal("done")
        expect(r.rounds_run).to.equal(3)
        expect(seen_slots[1]).to.equal("round_1")
        expect(seen_slots[2]).to.equal("round_2")
        expect(seen_slots[3]).to.equal("round_3")
        expect(r.history.round_1.answer).to.equal("ans_round_1")
    end)
end)

-- ---------------------------------------------------------------------
-- coding_style
-- ---------------------------------------------------------------------

describe("flow/doc/examples/coding_style", function()
    it("happy path — 3-step Phase chain", function()
        reset()
        mock_alc()
        local gatephase = require("orch_gatephase")
        gatephase.run = function(input)
            local pn = input.phases[1].name
            return {
                status = "completed", task_type = "feature",
                skipped_phases = {},
                phases = { { name = pn, output = "OUT_" .. pn, gate_passed = true, attempts = 1 } },
                final_output = "OUT_" .. pn,
                total_llm_calls = 1,
            }
        end
        local ex = require("examples.coding_style")
        local r = ex.run({
            task = "T", task_id = "cs_1",
            steps = {
                { name = "design",  prompt_of = function() return "design prompt" end, gate = "^OK$" },
                { name = "implement", prompt_of = function() return "impl prompt"   end, gate = "^OK$" },
                { name = "review",  prompt_of = function() return "review prompt" end, gate = "^OK$" },
            },
        })
        expect(r.status).to.equal("done")
        expect(r.results.design).to.equal("OUT_design")
        expect(r.results.implement).to.equal("OUT_implement")
        expect(r.results.review).to.equal("OUT_review")
    end)

    it("fail at step — returns failed/stage with partial results", function()
        reset()
        mock_alc()
        local gatephase = require("orch_gatephase")
        gatephase.run = function(input)
            local pn = input.phases[1].name
            if pn == "design" then
                return { status = "completed", task_type = "feature", skipped_phases = {}, phases = { { name = pn, output = "OK", gate_passed = true, attempts = 1 } }, final_output = "OK", total_llm_calls = 1 }
            end
            return { status = "failed", task_type = "feature", skipped_phases = {}, phases = { { name = pn, output = "NO", gate_passed = false, attempts = 3 } }, final_output = "NO", total_llm_calls = 3 }
        end
        local ex = require("examples.coding_style")
        local r = ex.run({
            task = "T", task_id = "cs_2",
            steps = {
                { name = "design",  prompt_of = function() return "" end, gate = "^OK$" },
                { name = "implement", prompt_of = function() return "" end, gate = "^OK$" },
            },
        })
        expect(r.status).to.equal("failed")
        expect(r.stage).to.equal("implement")
        expect(r.results.design).to.equal("OK")
    end)
end)
