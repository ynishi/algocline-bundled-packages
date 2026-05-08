--- Tests for triad (adversarial 3-role debate with judge arbitration).
---
--- Coverage (4 cases):
---   1. Happy path — task, 0 rounds, proponent wins
---   2. Input validation — ctx.task missing → error
---   3. Proponent wins — WINNER: proponent parsed correctly
---   4. Transcript structure — opening + rounds appended correctly

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

for _, name in ipairs({ "triad", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["triad"] = nil
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
        return fixtures[call_idx] or "A good argument."
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
-- Case 1: Happy path — 0 rounds, only opening + judge
-- ═══════════════════════════════════════════════════════════════════

describe("triad.run happy path", function()
    lust.after(reset)

    it("returns verdict and winner with 0 debate rounds", function()
        reset()
        -- Opening: parallel({pro, opp}) → 2 calls
        -- 0 rounds → no rebuttal calls
        -- Judge: 1 call → total 3 calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Proponent opening argument.",   -- pro opening
                "Opponent opening argument.",    -- opp opening
                "WINNER: proponent\nREASONING: Proponent had stronger evidence.",  -- judge
            },
        })
        _G.alc = stub
        local m = require("triad")
        local ctx = m.run({ task = "Is X better than Y?", rounds = 0 })
        expect(ctx.result).to_not.equal(nil)
        expect(type(ctx.result.verdict)).to.equal("string")
        expect(type(ctx.result.winner)).to.equal("string")
        expect(#ctx.result.transcript).to.equal(1)  -- only opening (round=0)
        expect(ctx.result.total_rounds).to.equal(0)
        expect(counter.llm_calls).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.task missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("triad.run input validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("triad")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Winner parsing — "proponent" extracted from verdict
-- ═══════════════════════════════════════════════════════════════════

describe("triad.run winner parsing", function()
    lust.after(reset)

    it("parses proponent as winner from verdict text", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Pro arg.",
                "Opp arg.",
                "WINNER: proponent\nSynthesis.",
            },
        })
        _G.alc = stub
        local m = require("triad")
        local ctx = m.run({ task = "Debate topic", rounds = 0 })
        expect(ctx.result.winner).to.equal("proponent")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: Transcript structure — 1 round adds entry to transcript
-- ═══════════════════════════════════════════════════════════════════

describe("triad.run transcript structure", function()
    lust.after(reset)

    it("transcript has opening + 1 rebuttal round = 2 entries", function()
        reset()
        -- Opening: 2 parallel calls
        -- Round 1: pro rebuttal (1 call) + opp rebuttal (1 call)
        -- Judge: 1 call → total 5 calls
        local stub, counter = make_alc_stub({
            fixtures = {
                "Pro opening.",
                "Opp opening.",
                "Pro rebuttal round 1.",
                "Opp rebuttal round 1.",
                "WINNER: draw\nBoth sides made valid points.",
            },
        })
        _G.alc = stub
        local m = require("triad")
        local ctx = m.run({ task = "Debate topic", rounds = 1 })
        -- transcript = opening (round=0) + round 1 = 2 entries
        expect(#ctx.result.transcript).to.equal(2)
        expect(ctx.result.transcript[1].round).to.equal(0)
        expect(ctx.result.transcript[2].round).to.equal(1)
        expect(counter.llm_calls).to.equal(5)
    end)
end)
