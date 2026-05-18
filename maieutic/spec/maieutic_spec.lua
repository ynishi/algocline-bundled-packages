--- Tests for maieutic (recursive explanation tree with logical consistency).
---
--- Coverage (4 cases):
---   1. Happy path — proposition, depth=1, both consistent → evidence collected
---   2. Input validation — ctx.proposition missing → error
---   3. Support stronger — both consistent, support evidence collected
---   4. result structure — verdict / synthesis / tree / evidence / consistency fields present

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

for _, name in ipairs({ "maieutic", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["maieutic"] = nil
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
        return fixtures[call_idx] or "CONSISTENT"
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
-- Case 1: Happy path — depth=1, both children consistent
-- ═══════════════════════════════════════════════════════════════════

describe("maieutic.run happy path", function()
    lust.after(reset)

    it("builds tree and returns result with evidence", function()
        reset()
        -- depth=1: build_tree at depth=0:
        --   parallel({support, oppose}) → 2 llm calls  [idx 1,2]
        --   check_consistency support  → 1 llm call    [idx 3] → "CONSISTENT"
        --   check_consistency oppose   → 1 llm call    [idx 4] → "CONSISTENT"
        --   no recursion (depth+1 = 1 = max_depth)
        -- synthesis → 1 llm call [idx 5]
        local stub, counter = make_alc_stub({
            fixtures = {
                "Supporting explanation text.",      -- support child
                "Opposing explanation text.",        -- oppose child
                "CONSISTENT",                        -- support consistency check
                "CONSISTENT",                        -- oppose consistency check
                "VERDICT: likely true\nREASONING: Based on evidence.",  -- synthesis
            },
        })
        _G.alc = stub
        local m = require("maieutic")
        local ctx = m.run({ proposition = "The earth is round.", max_depth = 1 })
        expect(ctx.result).to_not.equal(nil)
        expect(type(ctx.result.verdict)).to.equal("string")
        expect(type(ctx.result.synthesis)).to.equal("string")
        expect(type(ctx.result.tree)).to.equal("table")
        expect(type(ctx.result.evidence)).to.equal("table")
        expect(type(ctx.result.consistency)).to.equal("table")
        -- 5 total llm calls
        expect(counter.llm_calls).to.equal(5)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 2: Input validation — ctx.proposition missing → error
-- ═══════════════════════════════════════════════════════════════════

describe("maieutic.run input validation", function()
    lust.after(reset)

    it("errors when ctx.proposition is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("maieutic")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:find("proposition") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 3: Support evidence collected when consistent
-- ═══════════════════════════════════════════════════════════════════

describe("maieutic.run support evidence", function()
    lust.after(reset)

    it("includes support in evidence when child is consistent", function()
        reset()
        local stub, _ = make_alc_stub({
            fixtures = {
                "Clear supporting fact.",            -- support
                "Weak opposing argument.",           -- oppose
                "CONSISTENT",                        -- support consistency → consistent
                "CONTRADICTORY",                     -- oppose consistency → not collected
                "VERDICT: likely true\nREASONING: x",  -- synthesis
            },
        })
        _G.alc = stub
        local m = require("maieutic")
        local ctx = m.run({ proposition = "X is true.", max_depth = 1 })
        -- support was consistent → collected in evidence.support
        expect(#ctx.result.evidence.support).to.equal(1)
        -- oppose was contradictory → not in evidence.oppose
        expect(#ctx.result.evidence.oppose).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Case 4: result structure — consistency counts
-- ═══════════════════════════════════════════════════════════════════

describe("maieutic.run consistency counts", function()
    lust.after(reset)

    it("consistency histogram has correct counts", function()
        reset()
        -- both consistent → consistent=2, contradictory=0
        local stub, _ = make_alc_stub({
            fixtures = {
                "Support explanation.",
                "Oppose explanation.",
                "CONSISTENT",
                "CONSISTENT",
                "VERDICT: likely true\nREASONING: ok",
            },
        })
        _G.alc = stub
        local m = require("maieutic")
        local ctx = m.run({ proposition = "Proposition X", max_depth = 1 })
        expect(type(ctx.result.consistency.consistent)).to.equal("number")
        expect(ctx.result.consistency.consistent).to.equal(2)
        expect(ctx.result.consistency.contradictory).to.equal(0)
    end)
end)
