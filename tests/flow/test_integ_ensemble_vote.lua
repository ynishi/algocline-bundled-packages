--- Integration example: Ensemble vote (bare LLM × N + pure-compute chain).
---
--- N perspectives make independent numeric predictions via flow.llm, then
--- pure-compute pkg (ensemble_div, condorcet) measure diversity and
--- majority-vote trustworthiness. Demonstrates:
---
---   - flow.llm as an "AuthedClient.post" style call: token + slot per hit
---   - pure-compute pkg called directly — they sit OUTSIDE the token contract
---   - loop-back via a state flag (no Frame-level loop primitive)
---
--- Runtime cost (un-mocked): N perspectives × 1 LLM call each. Resume
--- persists already-answered slots so a retry only re-hits the missing
--- perspectives, not the whole panel.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local DEFAULT_PERSPECTIVES = { "analytical", "pragmatic", "contrarian" }

-- Extract the first signed number in a string. Returns nil when absent.
local function parse_number(s)
    if type(s) ~= "string" then return nil end
    local m = s:match("(-?%d+%.?%d*)")
    return m and tonumber(m)
end

local function predictions_as_array(preds, perspectives)
    local out = {}
    for i = 1, #perspectives do
        local v = preds["persp_" .. i]
        if v ~= nil then out[#out + 1] = v end
    end
    return out
end

local function weighted_mean(values, weights)
    if #values == 0 then return nil end
    local w, total_w = weights, 0
    if w == nil then
        w = {}
        for i = 1, #values do w[i] = 1 end
    end
    for _, x in ipairs(w) do total_w = total_w + x end
    local s = 0
    for i, v in ipairs(values) do
        s = s + v * (w[i] / total_w)
    end
    return s
end

-- ---------------------------------------------------------------------
-- The integration: bare alc.llm × N + direct pure-compute calls.
-- ---------------------------------------------------------------------
local function run_vote(ctx)
    local flow         = require("flow")
    local ensemble_div = require("ensemble_div")
    local condorcet    = require("condorcet")

    local task         = ctx.task    or error("ctx.task required")
    local task_id      = ctx.task_id or error("ctx.task_id required")
    local perspectives = ctx.perspectives or DEFAULT_PERSPECTIVES
    local resume       = ctx.resume or false

    local st  = flow.state_new({
        key_prefix = "ensemble_vote",
        id         = task_id,
        identity   = { task = task, n = #perspectives },
        resume     = resume,
    })
    local tok = flow.token_issue(st)

    -- flow.llm is the sugar: wrap token into prompt tags, call alc.llm,
    -- verify the echoed token/slot. Exactly like an AuthedClient.post.
    local preds = flow.state_get(st, "preds") or {}
    for i, persp in ipairs(perspectives) do
        local pkey = "persp_" .. i
        if preds[pkey] == nil then
            local prompt = "[" .. persp .. " perspective]\n"
                .. task
                .. "\n\nReturn only a single number on the final line."
            local out = flow.llm({
                token  = tok,
                slot   = pkey,
                prompt = prompt,
            })
            local n = parse_number(out)
            assert(n ~= nil, "flow.llm (" .. pkey .. "): could not parse number from: "
                .. tostring(out))
            preds[pkey] = n
            flow.state_set(st, "preds", preds)
            flow.state_save(st)
        end
    end

    -- Pure-compute chain: these pkg live OUTSIDE the token contract. We
    -- call them as plain Lua functions; no wrap/verify needed.
    local values = predictions_as_array(preds, perspectives)
    local decomp
    if type(ctx.ground_truth) == "number" then
        decomp = ensemble_div.decompose(values, ctx.ground_truth)
        flow.state_set(st, "decomp", {
            E              = decomp.E,
            E_bar          = decomp.E_bar,
            A_bar          = decomp.A_bar,
            identity_holds = decomp.identity_holds,
        })
    end

    local p_hat = ctx.voter_accuracy or 0.65
    local vote_health = {
        p_hat      = p_hat,
        p_majority = condorcet.prob_majority(#perspectives, p_hat),
        anti_jury  = condorcet.is_anti_jury(p_hat),
    }
    flow.state_set(st, "vote_health", vote_health)
    flow.state_save(st)

    -- Loop-back: if diversity is too low or voters are anti-jury, surface
    -- a regen flag. The caller decides whether to invalidate preds and
    -- re-enter. The Frame provides no loop primitive.
    if vote_health.anti_jury or (decomp and decomp.A_bar < 0.05) then
        flow.state_set(st, "regen_required", true)
        flow.state_save(st)
        return {
            status      = "regen_required",
            decomp      = flow.state_get(st, "decomp"),
            vote_health = vote_health,
        }
    end

    local aggregated = weighted_mean(values, ctx.weights)
    flow.state_set(st, "aggregated", aggregated)
    flow.state_save(st)

    return {
        status      = "done",
        aggregated  = aggregated,
        preds       = preds,
        decomp      = flow.state_get(st, "decomp"),
        vote_health = vote_health,
    }
end

-- ---------------------------------------------------------------------
-- Test scaffolding: minimal alc + answer-map-driven alc.llm.
-- ---------------------------------------------------------------------
local function fresh_store() return {} end

-- `answers` maps slot → numeric value the mock LLM should return for that
-- perspective. The mock also echoes the flow tags so flow.llm's verify
-- stays happy.
local function install_stubs(store, answers, opts)
    opts = opts or {}
    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
        llm = function(prompt, _)
            local tok  = prompt:match("%[flow_token=([%w_%-]+)%]")
            local slot = prompt:match("%[flow_slot=([%w_%-]+)%]")
            assert(tok, "mock alc.llm: expected a flow_token tag in the prompt")
            assert(slot, "mock alc.llm: expected a flow_slot tag in the prompt")
            local n = assert(answers[slot], "mock alc.llm: no answer registered for slot " .. slot)
            local echoed_tok = opts.tamper_token_on_slot == slot
                and (tok .. "-xx") or tok
            return tostring(n) .. "\n[flow_token=" .. echoed_tok
                .. "][flow_slot=" .. slot .. "]"
        end,
    }
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

-- ---------------------------------------------------------------------
describe("flow integ (ensemble_vote): happy path", function()
    lust.after(reset)

    it("aggregates three numeric predictions and returns done", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 10, persp_2 = 12, persp_3 = 14 })
        local out = run_vote({
            task = "pick a number", task_id = "r3a",
            voter_accuracy = 0.7,
        })
        expect(out.status).to.equal("done")
        expect(out.aggregated).to.equal(12)
        expect(out.preds.persp_1).to.equal(10)
        expect(out.preds.persp_3).to.equal(14)
    end)

    it("computes decomp when ground_truth is provided", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 8, persp_2 = 10, persp_3 = 12 })
        local out = run_vote({
            task = "pick a number", task_id = "r3b",
            ground_truth = 10, voter_accuracy = 0.7,
        })
        expect(out.status).to.equal("done")
        expect(out.decomp.identity_holds).to.equal(true)
        expect(out.decomp.A_bar > 0).to.equal(true)
    end)

    it("reports Condorcet vote health", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 1, persp_2 = 1, persp_3 = 1 })
        local out = run_vote({
            task = "t", task_id = "r3c", voter_accuracy = 0.7,
        })
        expect(out.vote_health.p_hat).to.equal(0.7)
        expect(out.vote_health.anti_jury).to.equal(false)
        expect(type(out.vote_health.p_majority)).to.equal("number")
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (ensemble_vote): regen loop-back", function()
    lust.after(reset)

    it("returns regen_required when voters are anti-jury", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 5, persp_2 = 5, persp_3 = 5 })
        local out = run_vote({
            task = "t", task_id = "r3d", voter_accuracy = 0.3,
        })
        expect(out.status).to.equal("regen_required")
        expect(out.vote_health.anti_jury).to.equal(true)
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (ensemble_vote): token contract", function()
    lust.after(reset)

    it("errors when the LLM echoes a tampered token on any slot", function()
        local store = fresh_store()
        install_stubs(store,
            { persp_1 = 1, persp_2 = 2, persp_3 = 3 },
            { tamper_token_on_slot = "persp_2" })
        local ok, err = pcall(run_vote, {
            task = "t", task_id = "r3e", voter_accuracy = 0.7,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("token mismatch", 1, true)).to_not.equal(nil)
    end)

    it("records each slot's token in the LLM prompt exactly once", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 1, persp_2 = 2, persp_3 = 3 })
        local captured = {}
        local real_llm = _G.alc.llm
        _G.alc.llm = function(prompt, opts)
            captured[#captured + 1] = prompt
            return real_llm(prompt, opts)
        end
        run_vote({ task = "t", task_id = "r3f", voter_accuracy = 0.7 })
        expect(#captured).to.equal(3)
        for i = 1, 3 do
            expect(captured[i]:find("[flow_slot=persp_" .. i .. "]", 1, true)).to_not.equal(nil)
        end
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (ensemble_vote): resume", function()
    lust.after(reset)

    it("does not re-invoke flow.llm for already-persisted perspectives", function()
        local store = fresh_store()
        install_stubs(store, { persp_1 = 10, persp_2 = 12, persp_3 = 14 })
        run_vote({ task = "t", task_id = "r3g", voter_accuracy = 0.7 })

        -- Second run: install stubs that WOULD return different numbers.
        -- Because preds is persisted, flow.llm must not be called.
        install_stubs(store, { persp_1 = 99, persp_2 = 99, persp_3 = 99 })
        local calls = 0
        local real_llm = _G.alc.llm
        _G.alc.llm = function(p, o) calls = calls + 1; return real_llm(p, o) end

        local out = run_vote({
            task = "t", task_id = "r3g", voter_accuracy = 0.7, resume = true,
        })
        expect(calls).to.equal(0)
        expect(out.aggregated).to.equal(12)
    end)
end)
