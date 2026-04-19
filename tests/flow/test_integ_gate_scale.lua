--- Integration example: Gate-Phase scaling across a realistic chain.
---
--- Why this integ exists:
--- A single real-world Flow often has 3–5 gates and, once you include
--- generation + verification + occasional retry, 10–20 LLM calls per
--- run. Splitting this into 5 separate `orch_gatephase.run()` invocations
--- — one per phase — breaks state continuity (each orch_gatephase has
--- its own internal retry loop and returns when the last phase finishes;
--- it does not checkpoint across invocations). This example shows how
--- flow scales gate-phase reasoning horizontally: one Flow State spans
--- the whole chain, each gate persists on success, resume picks up at
--- the first unset flag.
---
--- Chain (Coding-pipeline shaped):
---     modeling → plan → coding → review → commit
---     Each gate:  generate (1 LLM call) + verify (1 LLM call) = 2 calls
---     Per-run budget: 5 gates × 2 = 10 calls, one retry anywhere = 12.
---
--- Scaling properties demonstrated:
---   - State continuity: modeling.output is readable from coding's prompt
---     without re-running modeling.
---   - Resume fidelity: crash after `coding_ok=true`, resume, verify
---     alc.llm is NOT called for modeling/plan/coding again.
---   - Gate retry locality: a single gate failure retries in-place (via
---     the `attempts` counter on that slot) without rolling back earlier
---     completed gates.
---   - Slot verification: each gate's verify call carries a distinct
---     flow_slot so verdict mix-ups across parallel agents are impossible.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ---------------------------------------------------------------------
-- Driver: a 5-gate coding-pipeline Flow.
--
-- Each gate is: `generate + verify` tied together via flow.llm's slot
-- discipline. The gate's `verify` prompt is a constant string; the mock
-- LLM below answers "YES" / "NO" deterministically per slot.
-- ---------------------------------------------------------------------
local GATES = {
    { key = "modeling", prompt = "Model the domain for: {task}" },
    { key = "plan",     prompt = "Plan the implementation steps." },
    { key = "coding",   prompt = "Write the code." },
    { key = "review",   prompt = "Review the code." },
    { key = "commit",   prompt = "Confirm commit readiness." },
}

-- Generate + gate-verify for a single phase. Returns the generated text
-- on success; errors when the verify gate fails beyond max_retries.
local function run_one_gate(flow, tok, st, gate, max_retries, prev_output)
    local ok_key = gate.key .. "_ok"
    if flow.state_get(st, ok_key) then
        -- Already completed in a prior run — reuse the saved output.
        return flow.state_get(st, gate.key .. "_output")
    end

    local attempts_key = gate.key .. "_attempts"
    local attempts     = flow.state_get(st, attempts_key) or 0
    local prompt_ctx   = gate.prompt
    if prev_output and prev_output ~= "" then
        prompt_ctx = prompt_ctx .. "\n\nPrevious phase output:\n" .. prev_output
    end

    for attempt = 1, max_retries do
        attempts = attempt
        local gen = flow.llm({
            token    = tok,
            slot     = gate.key .. "_gen",
            prompt   = prompt_ctx,
            llm_opts = { max_tokens = 200 },
        })

        local verdict = flow.llm({
            token    = tok,
            slot     = gate.key .. "_verify",
            prompt   = "Evaluate the following. Answer YES or NO:\n" .. gen,
            llm_opts = { max_tokens = 20 },
        })

        if verdict:upper():find("YES") then
            flow.state_set(st, attempts_key, attempts)
            flow.state_set(st, gate.key .. "_output", gen)
            flow.state_set(st, ok_key, true)
            flow.state_save(st)
            return gen
        end
    end

    flow.state_set(st, attempts_key, attempts)
    flow.state_save(st)
    error(gate.key .. ": gate refused after " .. max_retries .. " attempts")
end

local function run_pipeline(ctx)
    local flow = require("flow")

    local task        = ctx.task    or error("ctx.task required")
    local task_id     = ctx.task_id or error("ctx.task_id required")
    local resume      = ctx.resume  or false
    local max_retries = ctx.max_retries or 2

    local st = flow.state_new({
        key_prefix = "gate_scale",
        id         = task_id,
        identity   = { task = task, n_gates = #GATES },
        resume     = resume,
    })
    local tok = flow.token_issue(st)

    local prev_output = ""
    for _, gate in ipairs(GATES) do
        -- Substitute {task} once per gate so the driver stays side-effect free.
        local expanded = gate.prompt:gsub("{task}", task)
        local g = { key = gate.key, prompt = expanded }
        prev_output = run_one_gate(flow, tok, st, g, max_retries, prev_output)
    end

    return {
        status         = "done",
        gates_passed   = #GATES,
        final_output   = prev_output,
        modeling       = flow.state_get(st, "modeling_output"),
        plan           = flow.state_get(st, "plan_output"),
        coding         = flow.state_get(st, "coding_output"),
        review         = flow.state_get(st, "review_output"),
        commit         = flow.state_get(st, "commit_output"),
    }
end

-- ---------------------------------------------------------------------
-- Test scaffolding.
--
-- The mock LLM reads `behaviour[slot]` to decide what to return. Default:
--   *_gen     → "stub:<slot>"
--   *_verify  → "YES"
-- `behaviour` can override either, enabling the failure-then-pass and
-- permanent-failure scenarios.
-- ---------------------------------------------------------------------
local function fresh_store() return {} end

local function install_stubs(store, behaviour)
    behaviour = behaviour or {}
    local counts = {}
    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
        llm = function(prompt, _)
            -- flow.llm appends "[flow_token=T][flow_slot=S]" at the end
            -- of the prompt. When a gate's verify prompt embeds the prior
            -- gen output (which carries its own echoed tags), the prompt
            -- contains multiple matches — we must read the LAST pair so
            -- we hit the slot flow.llm intended, not a stale one.
            local tok, slot
            for t, s in prompt:gmatch("%[flow_token=([%w_%-]+)%]%[flow_slot=([%w_%-]+)%]") do
                tok, slot = t, s
            end
            assert(tok, "mock alc.llm: missing flow_token tag")
            assert(slot, "mock alc.llm: missing flow_slot tag")
            counts[slot] = (counts[slot] or 0) + 1

            local override = behaviour[slot]
            local body
            if type(override) == "function" then
                body = override(counts[slot])
            elseif type(override) == "string" then
                body = override
            elseif slot:match("_verify$") then
                body = "YES"
            else
                body = "stub:" .. slot
            end
            return body .. "\n[flow_token=" .. tok .. "][flow_slot=" .. slot .. "]"
        end,
    }
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
    return counts
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

-- ---------------------------------------------------------------------
describe("flow integ (gate_scale): 5-gate happy path", function()
    lust.after(reset)

    it("runs all five gates and persists each output", function()
        local store  = fresh_store()
        local counts = install_stubs(store)
        local out    = run_pipeline({ task = "add login flow", task_id = "g1" })
        expect(out.status).to.equal("done")
        expect(out.gates_passed).to.equal(5)

        -- Each gate fires generate + verify exactly once on happy path.
        for _, gate in ipairs({ "modeling", "plan", "coding", "review", "commit" }) do
            expect(counts[gate .. "_gen"]).to.equal(1)
            expect(counts[gate .. "_verify"]).to.equal(1)
        end

        -- Persisted state reflects the full chain. The mock echoes tag
        -- lines back with the body, so we assert substring containment
        -- rather than equality — flow.llm returns alc.llm's raw string
        -- (see flow/llm.lua), which is what the driver persists.
        local rec = store["gate_scale:g1"]
        expect(rec.data.modeling_ok).to.equal(true)
        expect(rec.data.commit_ok).to.equal(true)
        expect(rec.data.coding_output:find("stub:coding_gen", 1, true)).to_not.equal(nil)
    end)

    it("carries previous output into the next gate's prompt", function()
        -- The driver prepends prev_output to each gate's prompt. Verify
        -- the generate call for gate `plan` receives modeling's output.
        local store = fresh_store()
        local seen_prompts = {}
        install_stubs(store, {})
        local real_llm = _G.alc.llm
        _G.alc.llm = function(prompt, opts)
            seen_prompts[#seen_prompts + 1] = prompt
            return real_llm(prompt, opts)
        end
        run_pipeline({ task = "t", task_id = "g2" })

        -- Identify the plan_gen invocation via the LAST flow_slot tag in
        -- each prompt — that is the tag flow.llm appends, i.e. the slot
        -- under which the call was made. Earlier-occurring tags are
        -- leftovers from embedded prev_output and do not indicate the
        -- current slot.
        local function last_slot(prompt)
            local s
            for m in prompt:gmatch("%[flow_slot=([%w_%-]+)%]") do s = m end
            return s
        end

        local plan_gen_prompts = {}
        for _, p in ipairs(seen_prompts) do
            if last_slot(p) == "plan_gen" then
                plan_gen_prompts[#plan_gen_prompts + 1] = p
            end
        end
        expect(#plan_gen_prompts).to.equal(1)
        expect(plan_gen_prompts[1]:find("stub:modeling_gen", 1, true)).to_not.equal(nil)
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (gate_scale): retry + recovery", function()
    lust.after(reset)

    it("retries a failing verify once then passes (coding_verify)", function()
        local store  = fresh_store()
        local counts = install_stubs(store, {
            coding_verify = function(nth)
                return nth == 1 and "NO, missing tests" or "YES"
            end,
        })
        local out = run_pipeline({
            task = "t", task_id = "g3", max_retries = 2,
        })
        expect(out.status).to.equal("done")
        expect(counts.coding_verify).to.equal(2)   -- one NO, one YES
        expect(counts.coding_gen).to.equal(2)      -- regenerated once

        -- The three earlier gates were unaffected.
        expect(counts.modeling_gen).to.equal(1)
        expect(counts.plan_gen).to.equal(1)
    end)

    it("errors when a gate exhausts retries", function()
        local store = fresh_store()
        install_stubs(store, {
            review_verify = "NO, needs rework",
        })
        local ok, err = pcall(run_pipeline, {
            task = "t", task_id = "g4", max_retries = 2,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("review", 1, true)).to_not.equal(nil)
    end)
end)

-- ---------------------------------------------------------------------
describe("flow integ (gate_scale): resume mid-chain", function()
    lust.after(reset)

    it("resumes from coding when modeling/plan/coding already persisted", function()
        -- First run: succeed up to coding, then simulate crash by installing
        -- a stub where review_verify throws.
        local store  = fresh_store()
        install_stubs(store, {
            review_verify = function() error("simulated crash after coding") end,
        })
        local ok = pcall(run_pipeline, { task = "t", task_id = "g5" })
        expect(ok).to.equal(false)

        -- Verify coding was persisted.
        local rec = store["gate_scale:g5"]
        expect(rec.data.coding_ok).to.equal(true)
        expect(rec.data.review_ok).to.equal(nil)

        -- Second run: stubs respond normally. resume must NOT re-invoke
        -- modeling_gen / plan_gen / coding_gen.
        local counts = install_stubs(store)
        local out = run_pipeline({
            task = "t", task_id = "g5", resume = true,
        })
        expect(out.status).to.equal("done")
        expect(out.gates_passed).to.equal(5)

        expect(counts.modeling_gen or 0).to.equal(0)
        expect(counts.plan_gen     or 0).to.equal(0)
        expect(counts.coding_gen   or 0).to.equal(0)
        expect(counts.review_gen).to.equal(1)
        expect(counts.commit_gen).to.equal(1)
    end)
end)
