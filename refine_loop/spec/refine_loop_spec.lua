--- Tests for refine_loop (reflective draft-reflect-revise loop).
---
--- Coverage (pass conditions):
---   1. draft -> reflection -> revise loop flow runs under a stub
---   2. reflection stub returning ACCEPT triggers early-stop and is reflected
---      in iterations_used / accepted
---   3. max_iterations default = 2 caps the loop even when ACCEPT never fires
---   4. ctx.rubric and ctx.feedback are injected into the reflection prompt
---      (feedback into the FIRST reflection only)
---   5. ctx.task missing / empty / whitespace-only → error
---
--- Run via the `lua-debugger` MCP server (mlua-lspec), which injects `lust`
--- as a global and prepends search_paths to package.path.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Make sibling packages (refine_loop, alc_shapes) resolvable from the repo
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
    "refine_loop", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["refine_loop"] = nil
    _G.alc = nil
end

--- Build a mock _G.alc that classifies each alc.llm call by prompt content
--- (draft / reflection / revise) and records prompts + call counts.
---   opts.reflections — list of reflection outputs returned in order. Any
---     reflection call past the list length gets a generic "needs work" reply
---     (so ACCEPT never fires unless scripted).
local function make_alc_stub(opts)
    opts = opts or {}
    local rec = {
        llm_calls = 0,
        draft_calls = 0,
        reflection_calls = 0,
        revise_calls = 0,
        prompts = {},
        reflection_prompts = {},
    }
    local reflection_seq = opts.reflections or {}

    local stub = {}
    stub.llm = function(prompt, _o)
        rec.llm_calls = rec.llm_calls + 1
        rec.prompts[#rec.prompts + 1] = prompt
        if prompt:find("Revise the draft", 1, true) then
            rec.revise_calls = rec.revise_calls + 1
            return "revised draft v" .. rec.revise_calls
        elseif prompt:find("respond with the single word ACCEPT", 1, true) then
            rec.reflection_calls = rec.reflection_calls + 1
            rec.reflection_prompts[#rec.reflection_prompts + 1] = prompt
            local out = reflection_seq[rec.reflection_calls]
            if out == nil then
                out = "Issues remain: tighten the argument and add sources."
            end
            return out
        else
            rec.draft_calls = rec.draft_calls + 1
            return "initial draft text"
        end
    end
    stub.log = function(_level, _msg) end

    return stub, rec
end

-- ═══════════════════════════════════════════════════════════════════
-- meta / spec sanity
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.meta", function()
    reset()
    make_alc_stub()
    local m = require("refine_loop")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("refine_loop")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("refinement")
    end)
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 1: draft -> reflection -> revise loop flow
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.run loop flow", function()
    lust.after(reset)

    it("runs draft, then reflection+revise for each capped round", function()
        reset()
        -- No ACCEPT scripted → both rounds reflect then revise.
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ctx = m.run({ task = "Explain the CAP theorem." })

        expect(rec.draft_calls).to.equal(1)
        expect(rec.reflection_calls).to.equal(2)
        expect(rec.revise_calls).to.equal(2)

        expect(ctx.result.iterations_used).to.equal(2)
        expect(ctx.result.accepted).to.equal(false)
        expect(ctx.result.final).to.equal("revised draft v2")
        -- History records the original draft and both rounds.
        expect(ctx.result.history.draft).to.equal("initial draft text")
        expect(#ctx.result.history.iterations).to.equal(2)
        expect(ctx.result.history.iterations[1].revision).to.equal("revised draft v1")
        expect(ctx.result.history.iterations[2].revision).to.equal("revised draft v2")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2: ACCEPT triggers early-stop
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.run early-stop on ACCEPT", function()
    lust.after(reset)

    it("stops after the first reflection when it returns ACCEPT", function()
        reset()
        local stub, rec = make_alc_stub({ reflections = { "ACCEPT" } })
        _G.alc = stub
        local m = require("refine_loop")
        local ctx = m.run({ task = "T", max_iterations = 5 })

        expect(rec.draft_calls).to.equal(1)
        expect(rec.reflection_calls).to.equal(1)
        expect(rec.revise_calls).to.equal(0)

        expect(ctx.result.iterations_used).to.equal(1)
        expect(ctx.result.accepted).to.equal(true)
        -- Never revised → final is the initial draft.
        expect(ctx.result.final).to.equal("initial draft text")
        expect(#ctx.result.history.iterations).to.equal(1)
        expect(ctx.result.history.iterations[1].accepted).to.equal(true)
        expect(ctx.result.history.iterations[1].revision).to.equal(nil)
    end)

    it("stops on ACCEPT at a later round", function()
        reset()
        -- Round 1 needs work (revise), round 2 accepts (standalone marker).
        local stub, rec = make_alc_stub({ reflections = { "needs work", "ACCEPT" } })
        _G.alc = stub
        local m = require("refine_loop")
        local ctx = m.run({ task = "T", max_iterations = 5 })

        expect(rec.reflection_calls).to.equal(2)
        expect(rec.revise_calls).to.equal(1)
        expect(ctx.result.iterations_used).to.equal(2)
        expect(ctx.result.accepted).to.equal(true)
        -- Revised once in round 1, then accepted in round 2.
        expect(ctx.result.final).to.equal("revised draft v1")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 3: max_iterations cap (default 2 and explicit)
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.run max_iterations cap", function()
    lust.after(reset)

    it("caps at 2 by default when ACCEPT never fires", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ctx = m.run({ task = "T" })

        expect(rec.reflection_calls).to.equal(2)
        expect(ctx.result.iterations_used).to.equal(2)
        expect(ctx.result.accepted).to.equal(false)
    end)

    it("honors an explicit max_iterations = 1", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ctx = m.run({ task = "T", max_iterations = 1 })

        expect(rec.reflection_calls).to.equal(1)
        expect(rec.revise_calls).to.equal(1)
        expect(ctx.result.iterations_used).to.equal(1)
        expect(ctx.result.final).to.equal("revised draft v1")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 4: rubric + feedback injection
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.run rubric + feedback injection", function()
    lust.after(reset)

    it("injects ctx.rubric and ctx.feedback into the first reflection prompt", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        m.run({
            task = "T",
            rubric = "MUST cite a primary source XYZ123",
            feedback = "EVAL_FEEDBACK_ABC failing case #7",
        })

        local first = rec.reflection_prompts[1]
        expect(first:find("MUST cite a primary source XYZ123", 1, true)).to_not.equal(nil)
        expect(first:find("EVAL_FEEDBACK_ABC failing case #7", 1, true)).to_not.equal(nil)
    end)

    it("injects feedback into the FIRST reflection only, rubric into all", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        -- Two rounds (no ACCEPT) so we get two reflection prompts.
        m.run({
            task = "T",
            rubric = "RUBRIC_MARKER_R",
            feedback = "FEEDBACK_MARKER_F",
        })

        local first = rec.reflection_prompts[1]
        local second = rec.reflection_prompts[2]
        -- First carries both rubric and feedback.
        expect(first:find("RUBRIC_MARKER_R", 1, true)).to_not.equal(nil)
        expect(first:find("FEEDBACK_MARKER_F", 1, true)).to_not.equal(nil)
        -- Second carries rubric but NOT feedback.
        expect(second:find("RUBRIC_MARKER_R", 1, true)).to_not.equal(nil)
        expect(second:find("FEEDBACK_MARKER_F", 1, true)).to.equal(nil)
    end)

    it("falls back to the default rubric when ctx.rubric omitted", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local default_rubric = m._internal.DEFAULT_RUBRIC
        m.run({ task = "T" })

        expect(rec.reflection_prompts[1]:find(default_rubric, 1, true)).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 5: ctx.task validation
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop.run task validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is empty string", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ok, err = pcall(m.run, { task = "" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is whitespace only", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("refine_loop")
        local ok, err = pcall(m.run, { task = "   \t  " })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- _internal.is_accepted marker detection (ASCII-only, byte-safe)
-- ═══════════════════════════════════════════════════════════════════

describe("refine_loop._internal.is_accepted", function()
    reset()
    make_alc_stub()
    local m = require("refine_loop")
    local is_accepted = m._internal.is_accepted

    it("accepts only the standalone marker (whitespace / trailing period tolerated)", function()
        expect(is_accepted("ACCEPT")).to.equal(true)
        expect(is_accepted("  ACCEPT\n")).to.equal(true)
        expect(is_accepted("ACCEPT.")).to.equal(true)
    end)

    it("rejects critiques that merely contain the marker", function()
        -- Regression: substring matching misread negative critiques as
        -- acceptance and silently disabled the revision loop
        -- (Boost Bench 2026-07-18, 4 reproduced sessions).
        expect(is_accepted("Not ACCEPT — the Korec exponent is imprecise")).to.equal(false)
        expect(is_accepted("I cannot ACCEPT this draft because...")).to.equal(false)
        expect(is_accepted("Looks good. ACCEPT")).to.equal(false)
    end)

    it("returns false when the marker is absent", function()
        expect(is_accepted("needs more work")).to.equal(false)
    end)
end)

reset()
