--- Tests for card_analysis (Card failure analyzer).
---
--- Coverage (5 cases):
---   1. Happy path — failures detected, LLM returns valid JSON, result populated
---   2. Input validation — ctx.card missing → error
---   3. Empty samples early return — total=0 → no-samples sentinel, no LLM call
---   4. No-signal fallback — failures detected via heuristic OR (admission/status/passed/score)
---   5. LLM unparseable output — json_extract fails → fallback result with raw preserved

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

for _, name in ipairs({ "card_analysis", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["card_analysis"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local llm_response = opts.llm_response
    local json_extract_result = opts.json_extract_result  -- explicit override (e.g. nil for unparseable)
    local counter = { llm_calls = 0, json_extract_calls = 0 }

    local stub = {}
    stub.llm = function(_prompt, _llm_opts)
        counter.llm_calls = counter.llm_calls + 1
        return llm_response or '{"pattern":"default","suggested_change":"default","confidence":0.5}'
    end

    stub.json_extract = function(raw)
        counter.json_extract_calls = counter.json_extract_calls + 1
        if opts.json_extract_returns_nil then
            return nil
        end
        if json_extract_result ~= nil then
            return json_extract_result
        end
        -- Default: parse the canned LLM response
        return {
            pattern = "default",
            suggested_change = "default",
            confidence = 0.5,
        }
    end

    stub.json_encode = function(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            parts[#parts + 1] = string.format("%s=%s", tostring(k), tostring(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    stub.log = function(_level, _msg) end

    return stub, counter
end

local function make_card()
    return {
        pkg      = { name = "test_pkg" },
        scenario = { name = "test_scenario" },
        model    = { id   = "test_model" },
    }
end

-- ═══════════════════════════════════════════════════════════════════
-- Case 1: Happy path — failures detected, LLM returns valid JSON
-- ═══════════════════════════════════════════════════════════════════

describe("card_analysis.run happy path", function()
    lust.after(reset)

    it("detects failures and returns parsed result", function()
        reset()
        local stub, counter = make_alc_stub({
            json_extract_result = {
                pattern = "Off-by-one in chunk boundary",
                suggested_change = "Add explicit boundary check before slicing.",
                confidence = 0.85,
            },
        })
        _G.alc = stub
        local m = require("card_analysis")
        local ctx = m.run({
            card_id = "card-1",
            card    = make_card(),
            samples = {
                { admission = "fail", input = "x", response = "wrong" },
                { admission = "pass", input = "y", response = "right" },
                { admission = "fail", input = "z", response = "wrong2" },
            },
        })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.pattern).to.equal("Off-by-one in chunk boundary")
        expect(ctx.result.suggested_change).to.equal("Add explicit boundary check before slicing.")
        expect(ctx.result.confidence).to.equal(0.85)
        expect(ctx.result.failure_count).to.equal(2)
        expect(ctx.result.sample_count).to.equal(3)
        expect(counter.llm_calls).to.equal(1)
        expect(counter.json_extract_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.card missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("card_analysis.run input validation", function()
    lust.after(reset)

    it("errors when ctx.card is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("card_analysis")
        local ok, err = pcall(m.run, { card_id = "card-1", samples = {} })
        expect(ok).to.equal(false)
        expect(err:find("card") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Empty samples early return — no LLM call
-- ═══════════════════════════════════════════════════════════════════

describe("card_analysis.run empty samples", function()
    lust.after(reset)

    it("returns no-samples sentinel when samples is empty", function()
        reset()
        local stub, counter = make_alc_stub()
        _G.alc = stub
        local m = require("card_analysis")
        local ctx = m.run({
            card_id = "card-1",
            card    = make_card(),
            samples = {},
        })
        expect(ctx.result.pattern).to.equal("no samples")
        expect(ctx.result.failure_count).to.equal(0)
        expect(ctx.result.sample_count).to.equal(0)
        expect(ctx.result.confidence).to.equal(1.0)
        -- No LLM call on the early-return path
        expect(counter.llm_calls).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Failure detection 4 paths (admission/status/passed/score)
-- ═══════════════════════════════════════════════════════════════════

describe("card_analysis.run failure heuristics", function()
    lust.after(reset)

    it("detects failures across all 4 heuristic paths", function()
        reset()
        local stub, counter = make_alc_stub({
            json_extract_result = {
                pattern = "mixed", suggested_change = "ok", confidence = 0.7,
            },
        })
        _G.alc = stub
        local m = require("card_analysis")
        local ctx = m.run({
            card_id = "card-1",
            card    = make_card(),
            samples = {
                { admission = "fail" },        -- path 1: admission
                { status    = "fail" },        -- path 2a: status fail
                { status    = "error" },       -- path 2b: status error
                { passed    = false },         -- path 3: passed=false
                { score     = 0.3 },           -- path 4: score < 0.5
                { admission = "pass" },        -- not a failure
                { score     = 0.8 },           -- not a failure (score >= 0.5)
            },
        })
        expect(ctx.result.failure_count).to.equal(5)
        expect(ctx.result.sample_count).to.equal(7)
        expect(counter.llm_calls).to.equal(1)
    end)

    it("falls back to all samples when no failure detected", function()
        reset()
        local stub, counter = make_alc_stub({
            json_extract_result = {
                pattern = "no clear failure", suggested_change = "review", confidence = 0.3,
            },
        })
        _G.alc = stub
        local m = require("card_analysis")
        local ctx = m.run({
            card_id = "card-1",
            card    = make_card(),
            samples = {
                { admission = "pass", response = "ok1" },
                { admission = "pass", response = "ok2" },
            },
        })
        -- failure_count = 0 but LLM still invoked on full sample pool
        expect(ctx.result.failure_count).to.equal(0)
        expect(ctx.result.sample_count).to.equal(2)
        expect(counter.llm_calls).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 5: LLM unparseable → fallback result with raw preserved
-- ═══════════════════════════════════════════════════════════════════

describe("card_analysis.run LLM unparseable output", function()
    lust.after(reset)

    it("returns fallback result and preserves raw LLM output", function()
        reset()
        local stub, counter = make_alc_stub({
            llm_response = "garbage non-json output from LLM",
            json_extract_returns_nil = true,
        })
        _G.alc = stub
        local m = require("card_analysis")
        local ctx = m.run({
            card_id = "card-1",
            card    = make_card(),
            samples = { { admission = "fail" } },
        })
        expect(ctx.result.pattern).to.equal("llm output unparseable")
        expect(ctx.result.confidence).to.equal(0.0)
        expect(ctx.result.failure_count).to.equal(1)
        expect(ctx.result.sample_count).to.equal(1)
        expect(ctx.result._raw_llm:find("garbage") ~= nil).to.equal(true)
        expect(counter.llm_calls).to.equal(1)
    end)
end)
