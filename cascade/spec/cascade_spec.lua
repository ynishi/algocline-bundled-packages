--- Tests for cascade (multi-level difficulty routing).
---
--- Coverage (4 cases):
---   1. Happy path — Level 1 passes threshold (escalated=false)
---   2. Input validation — ctx.task missing → error
---   3. Escalation to Level 2 — low confidence at Level 1
---   4. Edge case — max_level=1 cap (never escalates beyond L1)

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

for _, name in ipairs({ "cascade", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["cascade"] = nil
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
        return fixtures[call_idx] or "default answer"
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
-- Case 1: Happy path — Level 1 sufficient (confidence >= threshold)
-- ═══════════════════════════════════════════════════════════════════

describe("cascade.run happy path", function()
    lust.after(reset)

    it("stops at Level 1 when confidence >= threshold", function()
        reset()
        -- Level 1 returns a response with CONFIDENCE: 0.9 (above default 0.8)
        local stub, counter = make_alc_stub({
            fixtures = { "The answer is 42.\nCONFIDENCE: 0.9" },
        })
        _G.alc = stub
        local m = require("cascade")
        local ctx = m.run({ task = "What is 6 times 7?" })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.level_used).to.equal(1)
        expect(ctx.result.escalated).to.equal(false)
        expect(ctx.result.confidence >= 0.8).to.equal(true)
        -- Only 1 LLM call at Level 1
        expect(counter.llm_calls).to.equal(1)
        expect(#ctx.result.history).to.equal(1)
        expect(ctx.result.history[1].name).to.equal("fast")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("cascade.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("cascade")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Escalation — Level 1 low confidence triggers Level 2
-- ═══════════════════════════════════════════════════════════════════

describe("cascade.run escalation to Level 2", function()
    lust.after(reset)

    it("escalates to Level 2 when Level 1 confidence is below threshold", function()
        reset()
        -- Level 1: low confidence (0.3 < default 0.8)
        -- Level 2: cot call + verification with high confidence (0.9)
        local stub, counter = make_alc_stub({
            fixtures = {
                "Maybe 42.\nCONFIDENCE: 0.3",     -- Level 1 fast
                "Step by step: 6*7=42.",            -- Level 2 CoT
                "Confirmed. CONFIDENCE: 0.9",       -- Level 2 verification
            },
        })
        _G.alc = stub
        local m = require("cascade")
        local ctx = m.run({ task = "What is 6 times 7?" })
        expect(ctx.result.level_used).to.equal(2)
        expect(ctx.result.escalated).to.equal(true)
        expect(#ctx.result.history).to.equal(2)
        expect(ctx.result.history[1].name).to.equal("fast")
        expect(ctx.result.history[2].name).to.equal("cot_verify")
        -- 3 LLM calls: 1 (L1) + 2 (L2: cot + verify)
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Edge case — max_level=1 caps at Level 1 regardless of confidence
-- ═══════════════════════════════════════════════════════════════════

describe("cascade.run max_level cap", function()
    lust.after(reset)

    it("stops at Level 1 when max_level=1 even with low confidence", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = { "Uncertain answer.\nCONFIDENCE: 0.2" },
        })
        _G.alc = stub
        local m = require("cascade")
        local ctx = m.run({ task = "Hard question", max_level = 1 })
        expect(ctx.result.level_used).to.equal(1)
        expect(ctx.result.max_level).to.equal(1)
        expect(ctx.result.escalated).to.equal(false)
        expect(counter.llm_calls).to.equal(1)
    end)
end)

