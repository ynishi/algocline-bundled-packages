--- Tests for verify_select (generate-then-verify best-of-N selection).
---
--- Coverage:
---   1. Two-stage flow — alc.llm_batch (candidate gen) → alc.llm (verifier)
---   2. Default n = 3 candidates
---   3. ctx.rubric is injected verbatim into the verifier prompt
---      (+ default rubric used when omitted)
---   4. ctx.task missing / empty / whitespace → error
---   5. parse_verdicts helper + SELECTED-marker vs score-fallback selection
---
--- Run via the `lua-debugger` MCP server (mlua-lspec), which injects `lust`
--- as a global and prepends search_paths to package.path.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Make sibling packages (verify_select, alc_shapes) resolvable from the repo
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
    "verify_select", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["verify_select"] = nil
    _G.alc = nil
end

--- Build a mock _G.alc that records the batch items and verifier prompt.
---   opts.verifier_out — string returned by the single alc.llm verifier pass.
---     Default selects candidate 2 with parseable per-candidate scores.
local function make_alc_stub(opts)
    opts = opts or {}
    local rec = {
        batch_calls = 0,
        llm_calls = 0,
        batch_items = nil,
        verifier_prompt = nil,
    }
    local verifier_out = opts.verifier_out
        or ("Candidate 1 score: 6 - decent but incomplete\n"
            .. "Candidate 2 score: 9 - most accurate and complete\n"
            .. "Candidate 3 score: 4 - weak reasoning\n"
            .. "SELECTED: 2\n"
            .. "RATIONALE: candidate 2 best satisfies the rubric.\n")

    local stub = {}
    stub.llm_batch = function(items)
        rec.batch_calls = rec.batch_calls + 1
        rec.batch_items = items
        local out = {}
        for i = 1, #items do
            out[i] = "candidate " .. i .. " text"
        end
        return out
    end
    stub.llm = function(prompt, _o)
        rec.llm_calls = rec.llm_calls + 1
        rec.verifier_prompt = prompt
        return verifier_out
    end
    stub.log = function(_level, _msg) end

    return stub, rec
end

-- ═══════════════════════════════════════════════════════════════════
-- meta / spec sanity
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select.meta", function()
    reset()
    make_alc_stub()
    local m = require("verify_select")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("verify_select")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("selection")
    end)
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 1: two-stage llm_batch → llm flow
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select.run two-stage flow", function()
    lust.after(reset)

    it("runs llm_batch (gen) then llm (verify) exactly once each", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local ctx = m.run({ task = "What is the capital of France?" })

        expect(rec.batch_calls).to.equal(1)
        expect(rec.llm_calls).to.equal(1)
        -- Selected candidate comes from the batch output.
        expect(ctx.result.selected).to.equal("candidate 2 text")
        expect(ctx.result.rationale).to.equal("candidate 2 best satisfies the rubric.")
        -- Verdicts are dense (one per candidate) with parsed scores.
        expect(#ctx.result.verdicts).to.equal(3)
        expect(ctx.result.verdicts[2].score).to.equal(9)
        expect(ctx.result.verdicts[2].index).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2: default n = 3
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select.run default n", function()
    lust.after(reset)

    it("generates 3 candidates when ctx.n omitted", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local ctx = m.run({ task = "T" })

        expect(#rec.batch_items).to.equal(3)
        expect(ctx.result.candidates).to.equal(3)
    end)

    it("honors an explicit ctx.n", function()
        reset()
        local stub, rec = make_alc_stub({
            verifier_out = "Candidate 1 score: 8 - ok\nSELECTED: 1\nRATIONALE: only choice.\n",
        })
        _G.alc = stub
        local m = require("verify_select")
        local ctx = m.run({ task = "T", n = 1 })

        expect(#rec.batch_items).to.equal(1)
        expect(ctx.result.candidates).to.equal(1)
        expect(ctx.result.selected).to.equal("candidate 1 text")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 3: rubric injection into the verifier prompt
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select.run rubric injection", function()
    lust.after(reset)

    it("injects ctx.rubric verbatim into the verifier prompt", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        m.run({ task = "T", rubric = "MUST cite a primary source XYZ123" })

        expect(rec.verifier_prompt:find("MUST cite a primary source XYZ123", 1, true))
            .to_not.equal(nil)
    end)

    it("falls back to the default rubric when ctx.rubric omitted", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local default_rubric = m._internal.DEFAULT_RUBRIC
        m.run({ task = "T" })

        expect(rec.verifier_prompt:find(default_rubric, 1, true)).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 4: ctx.task validation
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select.run task validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is empty string", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local ok, err = pcall(m.run, { task = "" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is whitespace only", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("verify_select")
        local ok, err = pcall(m.run, { task = "   \t  " })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- parse_verdicts + score-fallback selection
-- ═══════════════════════════════════════════════════════════════════

describe("verify_select._internal.parse_verdicts", function()
    reset()
    make_alc_stub()
    local m = require("verify_select")
    local parse = m._internal.parse_verdicts

    it("parses scores, SELECTED, and RATIONALE", function()
        local parsed, sel, rat = parse(
            "Candidate 1 score: 5 - a\nCandidate 2 score: 8 - b\nSELECTED: 2\nRATIONALE: because b.\n")
        expect(parsed[1].score).to.equal(5)
        expect(parsed[2].score).to.equal(8)
        expect(parsed[2].verdict).to.equal("b")
        expect(sel).to.equal(2)
        expect(rat).to.equal("because b.")
    end)
end)

describe("verify_select.run score fallback", function()
    lust.after(reset)

    it("selects highest score when SELECTED marker is absent", function()
        reset()
        -- No SELECTED line — selection falls back to the max score (candidate 3).
        local stub = make_alc_stub({
            verifier_out = "Candidate 1 score: 2 - x\n"
                .. "Candidate 2 score: 4 - y\n"
                .. "Candidate 3 score: 7 - z\n"
                .. "RATIONALE: highest quality wins.\n",
        })
        _G.alc = stub
        local m = require("verify_select")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.selected).to.equal("candidate 3 text")
    end)
end)

reset()
