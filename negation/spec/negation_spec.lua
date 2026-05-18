--- Tests for negation (adversarial self-test via destruction conditions).
---
--- Coverage (4 cases):
---   1. Happy path — answer provided, 1 condition, all refuted → survived=true
---   2. Input validation — ctx.task missing → error
---   3. No conditions parsed → early return with survived=true, total=0
---   4. All conditions hold → survived=false, revised=true

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

for _, name in ipairs({ "negation", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["negation"] = nil
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
-- Case 1: Happy path — answer provided, 1 refuted condition → survived
-- ═══════════════════════════════════════════════════════════════════

describe("negation.run happy path", function()
    lust.after(reset)

    it("returns survived=true when condition is refuted", function()
        reset()
        -- conditions: "1. This condition would be bad."
        -- verification: REFUTED
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. This condition would invalidate it.",  -- destruction conditions
                "VERDICT: REFUTED\nREASONING: Not applicable.",  -- verification
            },
        })
        _G.alc = stub
        local m = require("negation")
        local ctx = m.run({
            task = "Explain photosynthesis",
            answer = "Photosynthesis converts sunlight to energy.",
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.survived).to.equal(true)
        expect(ctx.result.holding).to.equal(0)
        expect(ctx.result.refuted).to.equal(1)
        expect(ctx.result.revised).to.equal(false)
        expect(#ctx.result.conditions).to.equal(1)
        -- 1 conditions call + 1 verify call = 2
        expect(counter.llm_calls).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("negation.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("negation")
        local ok, err = pcall(m.run, { answer = "some answer" })
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: No conditions parsed → early return
-- ═══════════════════════════════════════════════════════════════════

describe("negation.run no conditions parsed", function()
    lust.after(reset)

    it("returns survived=true with total=0 when no conditions parsed", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = { "No numbered conditions here." },  -- no parse-able conditions
        })
        _G.alc = stub
        local m = require("negation")
        local ctx = m.run({
            task = "Simple question",
            answer = "Simple answer.",
        })
        expect(ctx.result.survived).to.equal(true)
        expect(ctx.result.total).to.equal(0)
        expect(#ctx.result.conditions).to.equal(0)
        -- Only 1 call: conditions generation
        expect(counter.llm_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: All conditions hold → survived=false, revised=true
-- ═══════════════════════════════════════════════════════════════════

describe("negation.run all conditions hold", function()
    lust.after(reset)

    it("returns survived=false and revised=true when condition holds", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. This specific fact is wrong and invalidates the answer.",  -- 1 condition
                "VERDICT: HOLDS\nREASONING: The condition is confirmed.",     -- holds
                "Revised and corrected answer.",                               -- revision
            },
        })
        _G.alc = stub
        local m = require("negation")
        local ctx = m.run({
            task = "Describe X",
            answer = "X is Y.",
        })
        expect(ctx.result.survived).to.equal(false)
        expect(ctx.result.holding).to.equal(1)
        expect(ctx.result.revised).to.equal(true)
        -- conditions (1) + verify (1) + revision (1) = 3
        expect(counter.llm_calls).to.equal(3)
    end)
end)
