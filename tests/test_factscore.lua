--- Tests for factscore (atomic claim decomposition and per-claim verification).
---
--- Coverage (4 cases):
---   1. Happy path — 2 claims, both supported → score=1.0
---   2. Input validation — ctx.text missing → error
---   3. All claims false — score=0.0
---   4. Precision score calculation — 1 supported + 1 unsupported → score=0.5

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

for _, name in ipairs({ "factscore", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["factscore"] = nil
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
        return fixtures[call_idx] or "SUPPORTED\nLooks correct."
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
-- Case 1: Happy path — 2 claims, both SUPPORTED → score=1.0
-- ═══════════════════════════════════════════════════════════════════

describe("factscore.run happy path", function()
    lust.after(reset)

    it("returns score=1.0 when all claims are supported", function()
        reset()
        local stub, counter = make_alc_stub({
            fixtures = {
                "1. Water is H2O.\n2. The sky is blue.",  -- extraction
                "SUPPORTED\nCorrect.",                    -- claim 1 verdict
                "SUPPORTED\nCorrect.",                    -- claim 2 verdict
            },
        })
        _G.alc = stub
        local m = require("factscore")
        local ctx = m.run({ text = "Water is H2O. The sky is blue." })
        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.score).to.equal(1.0)
        expect(ctx.result.supported).to.equal(2)
        expect(ctx.result.unsupported).to.equal(0)
        expect(ctx.result.total).to.equal(2)
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.text missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("factscore.run input validation", function()
    lust.after(reset)

    it("errors when ctx.text is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("factscore")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("text") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: All false — all UNSUPPORTED → score=0.0
-- ═══════════════════════════════════════════════════════════════════

describe("factscore.run all unsupported", function()
    lust.after(reset)

    it("returns score=0.0 when all claims are unsupported", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "1. False claim A.\n2. False claim B.",
                "UNSUPPORTED\nThis is wrong.",
                "UNSUPPORTED\nThis is also wrong.",
            },
        })
        _G.alc = stub
        local m = require("factscore")
        local ctx = m.run({ text = "False claim A. False claim B." })
        expect(ctx.result.score).to.equal(0.0)
        expect(ctx.result.unsupported).to.equal(2)
        expect(ctx.result.supported).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Precision calculation — 1 supported + 1 unsupported → score=0.5
-- ═══════════════════════════════════════════════════════════════════

describe("factscore.run precision calculation", function()
    lust.after(reset)

    it("calculates score=0.5 for 1 supported + 1 unsupported", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "1. True claim.\n2. False claim.",
                "SUPPORTED\nCorrect.",
                "UNSUPPORTED\nIncorrect.",
            },
        })
        _G.alc = stub
        local m = require("factscore")
        local ctx = m.run({ text = "True claim. False claim." })
        local diff = math.abs(ctx.result.score - 0.5)
        expect(diff < 1e-9).to.equal(true)
        expect(ctx.result.supported).to.equal(1)
        expect(ctx.result.unsupported).to.equal(1)
    end)
end)
