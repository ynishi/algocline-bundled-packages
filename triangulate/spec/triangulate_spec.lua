--- Tests for triangulate (agreement-checked verification across N independent paths).
---
--- Coverage (pass conditions):
---   1. Parallel solve via alc.llm_batch; agreement on round 1 → no reconsideration
---   2. Disagreement then agreement on round 2 (reconsideration loop converges)
---   3. Persistent split capped by max_rounds (default 1) → agreed = false
---   4. max_rounds = 0 disables reconsideration entirely
---   5. Path count: ctx.methods length wins; ctx.n default 2; explicit ctx.n
---   6. Normalization makes "42 ", "42.", "42" agree
---   7. Reconsideration prompt carries the per-path disagreement summary
---   8. ctx.task missing / empty / whitespace-only → error
---   9. _internal pure helpers (parse_answer marker safety, normalize,
---      answers_agree, majority_answer, build_default_methods)
---
--- Run via the `lua-debugger` MCP server (mlua-lspec), which injects `lust`
--- as a global and prepends search_paths to package.path.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Make sibling packages (triangulate, alc_shapes) resolvable from the repo
-- root regardless of the harness cwd.
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

for _, name in ipairs({
    "triangulate", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["triangulate"] = nil
    _G.alc = nil
end

--- Build a mock _G.alc whose alc.llm_batch replays scripted per-path answers per
--- round and records the batch items / prompts.
---   opts.rounds — list; rounds[r] is the list of raw strings returned for the
---     r-th alc.llm_batch call (one per path). Missing paths / rounds fall back to
---     a per-path-distinct "ANSWER: path-<i>-round-<r>" so paths DISAGREE by
---     default (which drives reconsideration).
local function make_alc_stub(opts)
    opts = opts or {}
    local rec = {
        batch_calls = 0,
        batches = {},
        prompts = {},
    }
    local rounds = opts.rounds or { { "ANSWER: 42", "ANSWER: 42" } }

    local stub = {}
    stub.llm_batch = function(items)
        rec.batch_calls = rec.batch_calls + 1
        rec.batches[rec.batch_calls] = items
        for _, it in ipairs(items) do
            rec.prompts[#rec.prompts + 1] = it.prompt
        end
        local scripted = rounds[rec.batch_calls]
        local out = {}
        for i = 1, #items do
            if scripted and scripted[i] ~= nil then
                out[i] = scripted[i]
            else
                out[i] = "ANSWER: path-" .. i .. "-round-" .. rec.batch_calls
            end
        end
        return out
    end
    stub.log = function(_level, _msg) end

    return stub, rec
end

-- ═══════════════════════════════════════════════════════════════════
-- meta / spec sanity
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.meta", function()
    reset()
    make_alc_stub()
    local m = require("triangulate")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("triangulate")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("validation")
    end)
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 1: parallel solve, agreement on round 1
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run agreement round 1", function()
    lust.after(reset)

    it("confirms on a single parallel round when paths agree", function()
        reset()
        local stub, rec = make_alc_stub({ rounds = { { "ANSWER: 42", "ANSWER: 42" } } })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "Compute X." })

        -- One batch call only; no reconsideration.
        expect(rec.batch_calls).to.equal(1)
        expect(ctx.result.agreed).to.equal(true)
        expect(ctx.result.rounds_used).to.equal(1)
        expect(ctx.result.final).to.equal("42")
        expect(#ctx.result.answers).to.equal(2)
        expect(ctx.result.answers[1]).to.equal("42")
        -- History records the one round with two path records.
        expect(#ctx.result.history).to.equal(1)
        expect(ctx.result.history[1].round).to.equal(1)
        expect(#ctx.result.history[1].results).to.equal(2)
        expect(ctx.result.history[1].results[1].raw).to.equal("ANSWER: 42")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2: disagree then agree on round 2
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run reconsideration converges", function()
    lust.after(reset)

    it("runs a second round on disagreement and confirms when it converges", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = {
                { "ANSWER: 7", "ANSWER: 9" }, -- round 1: split
                { "ANSWER: 8", "ANSWER: 8" }, -- round 2: agree
            },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T" })

        expect(rec.batch_calls).to.equal(2)
        expect(ctx.result.agreed).to.equal(true)
        expect(ctx.result.rounds_used).to.equal(2)
        expect(ctx.result.final).to.equal("8")
        -- answers reflect the FINAL round.
        expect(ctx.result.answers[1]).to.equal("8")
        expect(ctx.result.answers[2]).to.equal("8")
        -- history keeps both rounds.
        expect(#ctx.result.history).to.equal(2)
        expect(ctx.result.history[1].results[2].answer).to.equal("9")
        expect(ctx.result.history[2].results[1].answer).to.equal("8")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 3: persistent split capped by default max_rounds = 1
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run persistent disagreement", function()
    lust.after(reset)

    it("caps at 1 + max_rounds and returns agreed = false with a fallback final", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = {
                { "ANSWER: A", "ANSWER: B" }, -- round 1: split
                { "ANSWER: A", "ANSWER: B" }, -- round 2: still split
            },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T" })

        -- Default max_rounds = 1 → at most 2 batch calls.
        expect(rec.batch_calls).to.equal(2)
        expect(ctx.result.agreed).to.equal(false)
        expect(ctx.result.rounds_used).to.equal(2)
        -- Tie (A,B one each) → path 1 preference → "A".
        expect(ctx.result.final).to.equal("A")
        expect(#ctx.result.history).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 4: max_rounds = 0 disables reconsideration
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run max_rounds = 0", function()
    lust.after(reset)

    it("runs exactly one round and never reconsiders", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = { { "ANSWER: A", "ANSWER: B" } },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T", max_rounds = 0 })

        expect(rec.batch_calls).to.equal(1)
        expect(ctx.result.rounds_used).to.equal(1)
        expect(ctx.result.agreed).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 5: path count resolution
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run path count", function()
    lust.after(reset)

    it("uses ctx.methods length as the path count", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = { { "ANSWER: k", "ANSWER: k", "ANSWER: k" } },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T", methods = { "m1", "m2", "m3" }, n = 99 })

        expect(#rec.batches[1]).to.equal(3)
        expect(#ctx.result.answers).to.equal(3)
        -- Method hints reach the prompts.
        expect(rec.prompts[1]:find("m1", 1, true)).to_not.equal(nil)
        expect(rec.prompts[2]:find("m2", 1, true)).to_not.equal(nil)
        expect(rec.prompts[3]:find("m3", 1, true)).to_not.equal(nil)
        -- history records the method labels verbatim.
        expect(ctx.result.history[1].results[2].method).to.equal("m2")
    end)

    it("defaults to 2 paths when neither methods nor n given", function()
        reset()
        local stub, rec = make_alc_stub({ rounds = { { "ANSWER: z", "ANSWER: z" } } })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T" })

        expect(#rec.batches[1]).to.equal(2)
        expect(#ctx.result.answers).to.equal(2)
    end)

    it("honors an explicit ctx.n", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = { { "ANSWER: z", "ANSWER: z", "ANSWER: z", "ANSWER: z" } },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T", n = 4 })

        expect(#rec.batches[1]).to.equal(4)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 6: normalization makes near-identical answers agree
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run normalization agreement", function()
    lust.after(reset)

    it("treats '42 ', '42.', '42' as agreeing", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = { { "ANSWER:  42 ", "ANSWER: 42.", "ANSWER: 42" } },
        })
        _G.alc = stub
        local m = require("triangulate")
        local ctx = m.run({ task = "T", methods = { "a", "b", "c" } })

        expect(rec.batch_calls).to.equal(1)
        expect(ctx.result.agreed).to.equal(true)
        -- final is a real (un-normalized) representative answer, path-1 first.
        expect(ctx.result.final).to.equal("42")
        -- answers keep each path's extracted (trimmed) answer.
        expect(ctx.result.answers[2]).to.equal("42.")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 7: reconsideration prompt carries the disagreement
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run reconsideration prompt", function()
    lust.after(reset)

    it("feeds the per-path disagreement summary into the second round", function()
        reset()
        local stub, rec = make_alc_stub({
            rounds = {
                { "ANSWER: SEVEN", "ANSWER: NINE" },
                { "ANSWER: EIGHT", "ANSWER: EIGHT" },
            },
        })
        _G.alc = stub
        local m = require("triangulate")
        m.run({ task = "T" })

        -- Round-2 prompts (items 3 and 4 in the flat prompts log) present both
        -- round-1 answers so the model sees the mismatch points.
        local round2_prompt = rec.prompts[3]
        expect(round2_prompt:find("disagreed", 1, true)).to_not.equal(nil)
        expect(round2_prompt:find("SEVEN", 1, true)).to_not.equal(nil)
        expect(round2_prompt:find("NINE", 1, true)).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 8: ctx.task validation
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate.run task validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("triangulate")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is empty string", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("triangulate")
        local ok, err = pcall(m.run, { task = "" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is whitespace only", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("triangulate")
        local ok, err = pcall(m.run, { task = "   \t  " })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- _internal.parse_answer — standalone-marker safety (byte-safe)
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate._internal.parse_answer", function()
    reset()
    make_alc_stub()
    local m = require("triangulate")
    local parse_answer = m._internal.parse_answer

    it("extracts the answer from a standalone ANSWER: line", function()
        expect(parse_answer("ANSWER: 42")).to.equal("42")
        expect(parse_answer("reasoning here\nANSWER:  73 ")).to.equal("73")
        expect(parse_answer("   ANSWER:   hello world  ")).to.equal("hello world")
    end)

    it("ignores the marker mid-line and only matches a line that owns it", function()
        -- Regression: a plain substring match would capture "not this" from the
        -- first line; the standalone-line match takes the real ANSWER line.
        expect(parse_answer("Some ANSWER: not this\nANSWER: real")).to.equal("real")
    end)

    it("falls back to the trimmed whole response when no marker line exists", function()
        expect(parse_answer("just prose, no marker")).to.equal("just prose, no marker")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- _internal.normalize / answers_agree / majority_answer / defaults
-- ═══════════════════════════════════════════════════════════════════

describe("triangulate._internal helpers", function()
    reset()
    make_alc_stub()
    local m = require("triangulate")
    local I = m._internal

    it("normalize lowercases, collapses whitespace, strips trailing punctuation", function()
        expect(I.normalize("  Hello   World .")).to.equal("hello world")
        expect(I.normalize("42.")).to.equal("42")
        expect(I.normalize("A\nB")).to.equal("a b")
    end)

    it("answers_agree is true only when all normalized values match", function()
        local ok1, val1 = I.answers_agree({ "x", "x", "x" })
        expect(ok1).to.equal(true)
        expect(val1).to.equal("x")
        expect((I.answers_agree({ "x", "y" }))).to.equal(false)
        expect((I.answers_agree({}))).to.equal(false)
    end)

    it("majority_answer picks the plurality, path-1 preference on ties", function()
        local results = {
            { method = "m", answer = "A", raw = "" },
            { method = "m", answer = "B", raw = "" },
            { method = "m", answer = "A2", raw = "" },
        }
        -- normalized a,b,a → plurality "a", earliest occurrence is index 1 → "A".
        expect(I.majority_answer({ "a", "b", "a" }, results)).to.equal("A")
        -- tie a,b → earliest (path 1) → "A".
        expect(I.majority_answer({ "a", "b" }, { results[1], results[2] })).to.equal("A")
    end)

    it("build_default_methods returns N distinct hints (cycles beyond the pool)", function()
        local two = I.build_default_methods(2)
        expect(#two).to.equal(2)
        expect(two[1]).to_not.equal(two[2])
        local seven = I.build_default_methods(7)
        expect(#seven).to.equal(7)
        -- cycled entry carries a distinguishing suffix.
        expect(seven[6]:find("independent instance", 1, true)).to_not.equal(nil)
    end)

    it("normalize_methods returns nil for absent / empty, list otherwise", function()
        expect(I.normalize_methods(nil)).to.equal(nil)
        expect(I.normalize_methods({})).to.equal(nil)
        local list = I.normalize_methods({ "a", "b" })
        expect(#list).to.equal(2)
        expect(list[1]).to.equal("a")
    end)
end)

reset()
