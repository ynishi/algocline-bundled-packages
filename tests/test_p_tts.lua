--- Tests for p_tts (Plan-Test-Then-Solve).
---
--- Coverage (4 cases):
---   1. Happy path — constraints generated, all pass first attempt
---   2. Input validation — ctx.task missing → error
---   3. No constraints from plan → fallback single constraint, still runs
---   4. Verification flow — pass_count + fail_count structural check

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

for _, name in ipairs({ "p_tts", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["p_tts"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local counter = { llm_calls = 0, parallel_calls = 0, batch_calls = 0 }
    local call_idx = 0

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        call_idx = call_idx + 1
        return fixtures[call_idx] or "default response"
    end

    stub.llm_batch = function(items)
        counter.batch_calls = counter.batch_calls + 1
        local results = {}
        for i, item in ipairs(items) do
            results[i] = stub.llm(item.prompt, {
                system = item.system,
                max_tokens = item.max_tokens,
            })
        end
        return results
    end

    stub.parallel = function(items, prompt_fn, popts)
        counter.parallel_calls = counter.parallel_calls + 1
        popts = popts or {}
        local batch = {}
        for i, item in ipairs(items) do
            local p = prompt_fn(item, i)
            if type(p) == "string" then
                local entry = { prompt = p }
                if popts.system then entry.system = popts.system end
                if popts.max_tokens then entry.max_tokens = popts.max_tokens end
                batch[i] = entry
            else
                batch[i] = p
            end
        end
        local responses = stub.llm_batch(batch)
        if popts.post_fn then
            local res = {}
            for i, resp in ipairs(responses) do
                res[i] = popts.post_fn(resp, items[i], i)
            end
            return res
        end
        return responses
    end

    stub.log = function(_level, _msg) end

    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — 1 constraint, passes on first attempt
-- ═══════════════════════════════════════════════════════════════════

describe("p_tts.run happy path", function()
    lust.after(reset)

    it("returns all_passed=true when constraint passes", function()
        reset()
        -- Plan(1) + constraints(1) + solve(1) + verify-1-constraint(1) = 4 calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "The task requires a number.",           -- plan
                "1. The answer must be a positive integer.",  -- constraints
                "The answer is 42.",                    -- solve
                "VERDICT: PASS\nREASON: It's a positive integer.",  -- verify constraint 1
            },
        })
        _G.alc = stub
        local m = require("p_tts")
        local ctx = m.run({
            task = "What is 6 × 7?",
            max_repairs = 0,
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.all_passed).to.equal(true)
        expect(ctx.result.pass_count).to.equal(1)
        expect(ctx.result.fail_count).to.equal(0)
        expect(ctx.result.total_constraints).to.equal(1)
        expect(ctx.result.repairs).to.equal(0)
        expect(counter.llm_calls).to.equal(4)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("p_tts.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("p_tts")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: No constraints from plan → fallback single constraint
-- ═══════════════════════════════════════════════════════════════════

describe("p_tts.run no constraints fallback", function()
    lust.after(reset)

    it("uses fallback constraint when none parsed", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Some plan analysis.",          -- plan
                "No numbered constraints.",     -- constraints: no parse-able items
                "Solved answer.",               -- solve
                "VERDICT: PASS\nREASON: OK.",   -- fallback constraint verify
            },
        })
        _G.alc = stub
        local m = require("p_tts")
        local ctx = m.run({ task = "Simple task", max_repairs = 0 })
        -- Fallback = 1 constraint: "The answer must be correct and well-reasoned"
        expect(ctx.result.total_constraints).to.equal(1)
        expect(#ctx.result.constraints).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Verification flow structural check — pass_count + fail_count = total
-- ═══════════════════════════════════════════════════════════════════

describe("p_tts.run verification structure", function()
    lust.after(reset)

    it("pass_count + fail_count equals total_constraints", function()
        reset()
        -- 2 constraints: 1 pass + 1 fail, max_repairs=0 so no repair
        local stub, _ = make_alc_stub({
            fixtures = {
                "Good plan.",                             -- plan
                "1. Constraint A.\n2. Constraint B.",     -- 2 constraints
                "Answer here.",                           -- solve
                "VERDICT: PASS\nREASON: OK.",             -- constraint 1 verify
                "VERDICT: FAIL\nREASON: Missing part.",   -- constraint 2 verify
            },
        })
        _G.alc = stub
        local m = require("p_tts")
        local ctx = m.run({ task = "Complex task", max_repairs = 0 })
        expect(ctx.result.total_constraints).to.equal(2)
        expect(ctx.result.pass_count + ctx.result.fail_count).to.equal(ctx.result.total_constraints)
        expect(ctx.result.all_passed).to.equal(false)
    end)
end)
