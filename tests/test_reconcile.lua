--- Tests for reconcile v0.1.0 (Chen 2023 ReConcile, paper-explicit).
---
--- Coverage:
---   * M.meta / M.spec / M._defaults / M.CONFIDENCE_BUCKETS structural
---   * confidence_to_weight: §B.5 5-bucket verbatim from
---     dinobby/ReConcile/utils.py::trans_confidence
---   * compute_weighted_argmax: §4 confidence-weighted argmax formula
---     + first-occurrence tie-break + tally shape + reject
---   * check_consensus: all-agree predicate
---   * build_discussion_prompt: prefix + others block + override
---   * M._internal helpers: normalize_answer / coerce_confidence /
---     parse_agent_response / format_others_block / resolve_agents
---   * M.run end-to-end: Phase 1 init + Phase 2 discussion + Phase 3 vote
---     + early-stop on consensus + history shape + total_llm_calls

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

for _, name in ipairs({ "reconcile", "alc_shapes", "alc_shapes.t",
                       "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["reconcile"] = nil
    _G.alc = nil
end

local function format_response(answer, confidence, explanation)
    return string.format(
        "Answer: %s\nExplanation: %s\nConfidence: %.2f",
        answer, explanation or "ok", confidence)
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local call_log = {}

    local stub = {}
    stub.llm = function(prompt, llm_opts)
        call_log[#call_log + 1] = { prompt = prompt, opts = llm_opts }
        local idx = #call_log
        if type(fixtures) == "function" then
            return fixtures(idx, prompt, llm_opts)
        end
        return fixtures[idx] or format_response("default-" .. idx, 0.5)
    end
    stub.log = function() end
    return stub, call_log
end

-- ─── M.meta / M.spec / M._defaults ───

describe("reconcile.meta", function()
    lust.after(reset)

    it("declares name / version 0.1.0 / category aggregation", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.meta.name).to.equal("reconcile")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("aggregation")
    end)
end)

describe("reconcile.spec", function()
    lust.after(reset)

    it("exposes 5 entries: 4 pure helpers + run", function()
        _G.alc = {}
        local m = require("reconcile")
        local e = m.spec.entries
        expect(type(e.confidence_to_weight)).to.equal("table")
        expect(type(e.compute_weighted_argmax)).to.equal("table")
        expect(type(e.check_consensus)).to.equal("table")
        expect(type(e.build_discussion_prompt)).to.equal("table")
        expect(type(e.run)).to.equal("table")
    end)

    it("pure entries use args (direct-args), run uses input", function()
        _G.alc = {}
        local m = require("reconcile")
        local e = m.spec.entries
        expect(e.confidence_to_weight.args).to_not.equal(nil)
        expect(e.confidence_to_weight.input).to.equal(nil)
        expect(e.compute_weighted_argmax.args).to_not.equal(nil)
        expect(e.check_consensus.args).to_not.equal(nil)
        expect(e.build_discussion_prompt.args).to_not.equal(nil)
        expect(e.run.input).to_not.equal(nil)
        expect(e.run.args).to.equal(nil)
    end)
end)

describe("reconcile._defaults", function()
    lust.after(reset)

    it("matches Chen 2023 (L): max_rounds=3, convincing_count=4", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._defaults.max_rounds).to.equal(3)
        expect(m._defaults.convincing_count).to.equal(4)
    end)

    it("gen_tokens default 600 (X infrastructure), temperature nil (X)", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._defaults.gen_tokens).to.equal(600)
        expect(m._defaults.temperature).to.equal(nil)
    end)
end)

-- ─── confidence_to_weight: §B.5 5-bucket verbatim ───

describe("reconcile.confidence_to_weight (§B.5 buckets)", function()
    lust.after(reset)

    it("p ≤ 0.6 → 0.1", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.confidence_to_weight({ confidence = 0.0 })).to.equal(0.1)
        expect(m.confidence_to_weight({ confidence = 0.5 })).to.equal(0.1)
        expect(m.confidence_to_weight({ confidence = 0.6 })).to.equal(0.1)
    end)

    it("0.6 < p < 0.8 → 0.3", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.confidence_to_weight({ confidence = 0.61 })).to.equal(0.3)
        expect(m.confidence_to_weight({ confidence = 0.79 })).to.equal(0.3)
    end)

    it("0.8 ≤ p < 0.9 → 0.5", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.confidence_to_weight({ confidence = 0.8 })).to.equal(0.5)
        expect(m.confidence_to_weight({ confidence = 0.89 })).to.equal(0.5)
    end)

    it("0.9 ≤ p < 1.0 → 0.8", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.confidence_to_weight({ confidence = 0.9 })).to.equal(0.8)
        expect(m.confidence_to_weight({ confidence = 0.99 })).to.equal(0.8)
    end)

    it("p == 1.0 → 1.0", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.confidence_to_weight({ confidence = 1.0 })).to.equal(1.0)
    end)

    it("rejects out-of-range confidence", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(pcall(m.confidence_to_weight, { confidence = -0.1 })).to.equal(false)
        expect(pcall(m.confidence_to_weight, { confidence = 1.5 })).to.equal(false)
    end)
end)

-- ─── compute_weighted_argmax: §4 formula ───

describe("reconcile.compute_weighted_argmax", function()
    lust.after(reset)

    it("returns highest-weight answer", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.compute_weighted_argmax({
            responses = {
                { normalized = "a", weight = 0.1 },
                { normalized = "b", weight = 0.8 },
                { normalized = "a", weight = 0.3 },
            },
        })
        expect(r.answer).to.equal("b")
        expect(r.weight).to.equal(0.8)
        expect(r.count).to.equal(1)
    end)

    it("sums weights for same answer", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.compute_weighted_argmax({
            responses = {
                { normalized = "a", weight = 0.3 },
                { normalized = "a", weight = 0.5 },
                { normalized = "b", weight = 0.5 },
            },
        })
        expect(r.answer).to.equal("a")
        expect(r.weight).to.equal(0.8)
        expect(r.count).to.equal(2)
    end)

    it("breaks ties by first-occurrence", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.compute_weighted_argmax({
            responses = {
                { normalized = "b", weight = 0.5 },
                { normalized = "a", weight = 0.5 },
            },
        })
        expect(r.answer).to.equal("b")
    end)

    it("tally is sorted by (weight desc, first-occurrence asc)", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.compute_weighted_argmax({
            responses = {
                { normalized = "x", weight = 0.1 },
                { normalized = "y", weight = 0.8 },
                { normalized = "z", weight = 0.3 },
                { normalized = "y", weight = 0.5 },
            },
        })
        expect(r.tally[1].answer).to.equal("y")
        expect(r.tally[1].weight).to.equal(1.3)
        expect(r.tally[2].answer).to.equal("z")
        expect(r.tally[3].answer).to.equal("x")
    end)

    it("rejects empty responses", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(pcall(m.compute_weighted_argmax, { responses = {} })).to.equal(false)
    end)

    it("rejects malformed response (missing weight)", function()
        _G.alc = {}
        local m = require("reconcile")
        local ok = pcall(m.compute_weighted_argmax, {
            responses = { { normalized = "a" } },
        })
        expect(ok).to.equal(false)
    end)
end)

-- ─── check_consensus ───

describe("reconcile.check_consensus", function()
    lust.after(reset)

    it("returns true when all normalized answers agree", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.check_consensus({
            responses = {
                { normalized = "x" },
                { normalized = "x" },
                { normalized = "x" },
            },
        })).to.equal(true)
    end)

    it("returns false when any agent disagrees", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.check_consensus({
            responses = {
                { normalized = "x" },
                { normalized = "y" },
                { normalized = "x" },
            },
        })).to.equal(false)
    end)

    it("returns true for single-agent response (vacuous)", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m.check_consensus({
            responses = { { normalized = "x" } },
        })).to.equal(true)
    end)
end)

-- ─── build_discussion_prompt ───

describe("reconcile.build_discussion_prompt", function()
    lust.after(reset)

    it("includes task and each other-agent block", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.build_discussion_prompt({
            task = "Q",
            other_responses = {
                { agent = 2, answer = "A2", explanation = "E2", confidence = 0.8 },
                { agent = 3, answer = "A3", explanation = "E3", confidence = 0.5 },
            },
        })
        expect(r.prompt:find("Q", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("Agent 2", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("A2", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("Agent 3", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("A3", 1, true)).to_not.equal(nil)
    end)

    it("caps others by convincing_count", function()
        _G.alc = {}
        local m = require("reconcile")
        local others = {}
        for i = 2, 6 do
            others[#others + 1] = {
                agent = i, answer = "A" .. i, explanation = "E", confidence = 0.5
            }
        end
        local r = m.build_discussion_prompt({
            task = "Q", other_responses = others, convincing_count = 2,
        })
        expect(r.prompt:find("A2", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("A3", 1, true)).to_not.equal(nil)
        -- Should NOT include the ones beyond the cap.
        expect(r.prompt:find("A5", 1, true)).to.equal(nil)
        expect(r.prompt:find("A6", 1, true)).to.equal(nil)
    end)

    it("accepts custom discussion_prompt override", function()
        _G.alc = {}
        local m = require("reconcile")
        local r = m.build_discussion_prompt({
            task = "T",
            other_responses = {
                { agent = 2, answer = "A2", explanation = "E", confidence = 0.5 },
            },
            discussion_prompt = "TASK=[%s] OTHERS=[%s]",
        })
        expect(r.prompt:find("TASK=%[T%]", 1)).to_not.equal(nil)
        expect(r.prompt:find("Agent 2", 1, true)).to_not.equal(nil)
    end)

    it("rejects empty other_responses", function()
        _G.alc = {}
        local m = require("reconcile")
        local ok = pcall(m.build_discussion_prompt, {
            task = "T", other_responses = {},
        })
        expect(ok).to.equal(false)
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("reconcile")
        local ok = pcall(m.build_discussion_prompt, {
            other_responses = { { agent = 1, answer = "a", explanation = "e", confidence = 0.5 } }
        })
        expect(ok).to.equal(false)
    end)
end)

-- ─── M._internal helpers ───

describe("reconcile._internal.normalize_answer", function()
    lust.after(reset)

    it("trims and lowercases", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.normalize_answer("  Hello WORLD  ")).to.equal("hello world")
    end)

    it("collapses internal whitespace", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.normalize_answer("a\t\nb")).to.equal("a b")
    end)
end)

describe("reconcile._internal.coerce_confidence", function()
    lust.after(reset)

    it("passes through valid number", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.coerce_confidence(0.7)).to.equal(0.7)
    end)

    it("clamps below 0 to 0", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.coerce_confidence(-0.5)).to.equal(0)
    end)

    it("clamps above 1 to 1", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.coerce_confidence(1.5)).to.equal(1)
    end)

    it("parses numeric string", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.coerce_confidence("0.8")).to.equal(0.8)
    end)

    it("falls back to 0.5 for unparseable input", function()
        _G.alc = {}
        local m = require("reconcile")
        expect(m._internal.coerce_confidence("not a number")).to.equal(0.5)
        expect(m._internal.coerce_confidence(nil)).to.equal(0.5)
    end)
end)

describe("reconcile._internal.parse_agent_response", function()
    lust.after(reset)

    it("parses Answer / Explanation / Confidence from text", function()
        _G.alc = {}
        local m = require("reconcile")
        local p = m._internal.parse_agent_response(
            "Answer: 42\nExplanation: math\nConfidence: 0.9")
        expect(p.answer).to.equal("42")
        expect(p.explanation).to.equal("math")
        expect(p.confidence).to.equal(0.9)
    end)

    it("passes through pre-parsed table", function()
        _G.alc = {}
        local m = require("reconcile")
        local p = m._internal.parse_agent_response({
            answer = "x", explanation = "e", confidence = 0.7,
        })
        expect(p.answer).to.equal("x")
        expect(p.confidence).to.equal(0.7)
    end)

    it("falls back to confidence=0.5 when not parseable", function()
        _G.alc = {}
        local m = require("reconcile")
        local p = m._internal.parse_agent_response("just some text")
        expect(p.confidence).to.equal(0.5)
    end)
end)

describe("reconcile._internal.resolve_agents", function()
    lust.after(reset)

    it("returns agents as-is (paper-faithful path)", function()
        _G.alc = {}
        local m = require("reconcile")
        local specs, path = m._internal.resolve_agents({
            agents = { { model = "m1" }, { model = "m2" } },
        })
        expect(#specs).to.equal(2)
        expect(path).to.equal("agents")
    end)

    it("wraps personas as { system = persona } (alt path)", function()
        _G.alc = {}
        local m = require("reconcile")
        local specs, path = m._internal.resolve_agents({
            personas = { "P1", "P2" },
        })
        expect(#specs).to.equal(2)
        expect(specs[1].system).to.equal("P1")
        expect(path).to.equal("personas")
    end)

    it("rejects when neither agents nor personas given", function()
        _G.alc = {}
        local m = require("reconcile")
        local ok, err = pcall(m._internal.resolve_agents, { task = "T" })
        expect(ok).to.equal(false)
        expect(err:match("REQUIRED")).to_not.equal(nil)
    end)
end)

-- ─── M.run end-to-end ───

describe("reconcile.run", function()
    lust.after(reset)

    it("makes N init calls in Phase 1, terminates on consensus", function()
        local fixtures = {
            format_response("42", 0.9),
            format_response("42", 0.8),
            format_response("42", 0.7),  -- all agree at init → consensus
        }
        local alc_stub, call_log = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("reconcile")
        local ctx = m.run({
            task = "Q",
            personas = { "A", "B", "C" },
        })
        expect(ctx.result.total_llm_calls).to.equal(3)
        expect(#call_log).to.equal(3)
        expect(ctx.result.consensus).to.equal(true)
        expect(ctx.result.rounds_used).to.equal(1)
        expect(ctx.result.answer).to.equal("42")
    end)

    it("runs Phase 2 discussion rounds when no init consensus", function()
        local fixtures = {
            -- round 0: disagreement
            format_response("a", 0.5),
            format_response("b", 0.7),
            -- round 1: still disagreement
            format_response("a", 0.5),
            format_response("a", 0.9),  -- agent 2 switches to "a", now consensus
        }
        local alc_stub, call_log = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("reconcile")
        local ctx = m.run({
            task = "Q",
            personas = { "A", "B" },
            max_rounds = 3,
        })
        expect(#call_log).to.equal(4)  -- 2 init + 2 discussion
        expect(ctx.result.consensus).to.equal(true)
        expect(ctx.result.rounds_used).to.equal(2)
        expect(ctx.result.answer).to.equal("a")
    end)

    it("runs all R rounds when no consensus reached, falls back to weighted vote", function()
        local function fix(idx)
            -- Always disagree: agent 1 says "a", agent 2 says "b"
            if idx % 2 == 1 then
                return format_response("a", 0.5)
            else
                return format_response("b", 0.95)  -- agent 2 high confidence
            end
        end
        local alc_stub = make_alc_stub({ fixtures = fix })
        _G.alc = alc_stub
        local m = require("reconcile")
        local ctx = m.run({
            task = "Q",
            personas = { "A", "B" },
            max_rounds = 2,
        })
        -- 2 init + 2*2 discussion = 6 calls
        expect(ctx.result.total_llm_calls).to.equal(6)
        expect(ctx.result.consensus).to.equal(false)
        expect(ctx.result.rounds_used).to.equal(3)
        -- "b" should win via weighted vote (0.8 > 0.1)
        expect(ctx.result.answer).to.equal("b")
    end)

    it("history records round 0 + each discussion round", function()
        local fixtures = {
            format_response("a", 0.7),
            format_response("b", 0.7),
            format_response("a", 0.9),
            format_response("a", 0.9),
        }
        local alc_stub = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("reconcile")
        local ctx = m.run({
            task = "Q",
            personas = { "A", "B" },
            max_rounds = 3,
        })
        expect(#ctx.result.history).to.equal(2)  -- init + 1 discussion
        expect(#ctx.result.history[1]).to.equal(2)
        expect(ctx.result.history[1][1].round).to.equal(0)
        expect(ctx.result.history[2][1].round).to.equal(1)
    end)

    it("weight is f(confidence) per §B.5 buckets in history", function()
        local fixtures = {
            format_response("a", 1.0),   -- weight 1.0
            format_response("a", 0.8),   -- weight 0.5
            format_response("a", 0.65),  -- weight 0.3
        }
        local alc_stub = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("reconcile")
        local ctx = m.run({
            task = "Q",
            personas = { "A", "B", "C" },
        })
        expect(ctx.result.history[1][1].weight).to.equal(1.0)
        expect(ctx.result.history[1][2].weight).to.equal(0.5)
        expect(ctx.result.history[1][3].weight).to.equal(0.3)
    end)

    it("propagates model id from agents spec", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("reconcile")
        m.run({
            task = "Q",
            agents = { { model = "M1" }, { model = "M2" }, { model = "M3" } },
        })
        expect(call_log[1].opts.model).to.equal("M1")
        expect(call_log[2].opts.model).to.equal("M2")
        expect(call_log[3].opts.model).to.equal("M3")
    end)

    it("rejects when neither agents nor personas given", function()
        _G.alc = make_alc_stub()
        local m = require("reconcile")
        local ok = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
    end)

    it("rejects missing task", function()
        _G.alc = make_alc_stub()
        local m = require("reconcile")
        local ok = pcall(m.run, { personas = { "A" } })
        expect(ok).to.equal(false)
    end)

    it("rejects max_rounds < 1", function()
        _G.alc = make_alc_stub()
        local m = require("reconcile")
        local ok = pcall(m.run, { task = "T", personas = { "A" }, max_rounds = 0 })
        expect(ok).to.equal(false)
    end)

    it("rejects when alc host is unavailable", function()
        _G.alc = nil
        package.loaded["reconcile"] = nil
        local m = require("reconcile")
        local ok, err = pcall(m.run, { task = "T", personas = { "A" } })
        expect(ok).to.equal(false)
        expect(err:match("alc host")).to_not.equal(nil)
    end)
end)
