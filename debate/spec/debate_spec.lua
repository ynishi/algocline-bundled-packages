--- Tests for debate (adversarial two-debater protocol with judge verdict).
---
--- Coverage:
---   1. meta / spec sanity
---   2. Sequential 2R + 1 flow — each debater sees prior transcript,
---      2 debaters × R rounds + 1 judge = 2R + 1 alc.llm calls
---   3. Default rounds = 3 (Khan 2024 §3 canonical setting)
---   4. ctx.judge_criteria injected verbatim into the judge prompt
---      (+ default criteria used when omitted)
---   5. ctx.question missing / empty / whitespace → error
---   6. Judge output parsing — WINNER extraction + unparsable fallback → "A"
---
--- Run via the `lua-debugger` MCP server (mlua-lspec), which injects `lust`
--- as a global and prepends search_paths to package.path.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Make sibling packages (debate, alc_shapes) resolvable from the repo
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
    "debate", "alc_shapes", "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["debate"] = nil
    _G.alc = nil
end

--- Build a mock _G.alc that records each alc.llm call in order.
---   opts.judge_out — string returned by the final (judge) alc.llm call.
---     Default emits WINNER: A / VERDICT / RATIONALE.
---   opts.debater_reply — function(call_index, prompt) → string. Optional
---     override for debater turn text. Default returns a short synthetic
---     argument derived from the call index.
local function make_alc_stub(opts)
    opts = opts or {}
    local rec = {
        llm_calls = 0,
        prompts = {},   -- ordered prompt list (all alc.llm invocations)
        systems = {},   -- ordered system list
    }
    local judge_out = opts.judge_out
        or ("WINNER: A\n"
            .. "VERDICT: A argued more truthfully.\n"
            .. "RATIONALE: A cited specific evidence while B relied on assertion.\n")
    local debater_reply = opts.debater_reply
        or function(idx, _prompt) return "argument #" .. idx end

    local stub = {}
    -- 2R debater calls followed by 1 judge call. We identify the judge call
    -- by matching the "WINNER:" instruction embedded in build_judge_prompt;
    -- otherwise it's a debater turn.
    stub.llm = function(prompt, o)
        rec.llm_calls = rec.llm_calls + 1
        rec.prompts[#rec.prompts + 1] = prompt
        rec.systems[#rec.systems + 1] = (o and o.system) or ""
        if prompt:find("WINNER:", 1, true)
            and prompt:find("VERDICT:", 1, true)
            and prompt:find("RATIONALE:", 1, true)
        then
            return judge_out
        end
        return debater_reply(rec.llm_calls, prompt)
    end
    stub.log = function(_level, _msg) end

    return stub, rec
end

-- ═══════════════════════════════════════════════════════════════════
-- meta / spec sanity
-- ═══════════════════════════════════════════════════════════════════

describe("debate.meta", function()
    reset()
    _G.alc = make_alc_stub()
    local m = require("debate")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("debate")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("synthesis")
    end)
    it("alc_shapes_compat range", function()
        expect(m.meta.alc_shapes_compat).to.equal("^0.25")
    end)
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 1: 2R + 1 alc.llm calls, sequential dependency
-- (each debater sees the prior transcript when composing its turn)
-- ═══════════════════════════════════════════════════════════════════

describe("debate.run sequential 2R + 1 flow", function()
    lust.after(reset)

    it("emits exactly 2R + 1 alc.llm calls (R = 3 default → 7)", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        m.run({ question = "Is P = NP?" })

        expect(rec.llm_calls).to.equal(7) -- 2*3 debater + 1 judge
    end)

    it("each debater turn after the first sees prior transcript", function()
        reset()
        -- Distinctive arguments so we can grep the prompt of the next turn.
        local stub, rec = make_alc_stub({
            debater_reply = function(idx, _p) return "UNIQUE_ARG_" .. idx end,
        })
        _G.alc = stub
        local m = require("debate")
        m.run({ question = "Q?" })

        -- Turn 1 (A round 1): no prior transcript.
        expect(rec.prompts[1]:find("no prior arguments", 1, true)).to_not.equal(nil)
        -- Turn 2 (B round 1): sees A's turn 1.
        expect(rec.prompts[2]:find("UNIQUE_ARG_1", 1, true)).to_not.equal(nil)
        -- Turn 3 (A round 2): sees turns 1 and 2.
        expect(rec.prompts[3]:find("UNIQUE_ARG_1", 1, true)).to_not.equal(nil)
        expect(rec.prompts[3]:find("UNIQUE_ARG_2", 1, true)).to_not.equal(nil)
        -- Judge (turn 7): sees all 6 debater turns.
        for i = 1, 6 do
            expect(rec.prompts[7]:find("UNIQUE_ARG_" .. i, 1, true)).to_not.equal(nil)
        end
    end)

    it("populates transcript with 2R ordered turns and rounds_used", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        local ctx = m.run({ question = "Q?", rounds = 2 })

        expect(#ctx.result.transcript).to.equal(4)
        expect(ctx.result.transcript[1].round).to.equal(1)
        expect(ctx.result.transcript[1].side).to.equal("A")
        expect(ctx.result.transcript[2].round).to.equal(1)
        expect(ctx.result.transcript[2].side).to.equal("B")
        expect(ctx.result.transcript[3].round).to.equal(2)
        expect(ctx.result.transcript[3].side).to.equal("A")
        expect(ctx.result.transcript[4].round).to.equal(2)
        expect(ctx.result.transcript[4].side).to.equal("B")
        expect(ctx.result.rounds_used).to.equal(2)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2: default rounds = 3 (Khan 2024 §3 Table 2)
-- ═══════════════════════════════════════════════════════════════════

describe("debate.run default rounds", function()
    lust.after(reset)

    it("defaults to 3 rounds when ctx.rounds omitted", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        local ctx = m.run({ question = "Q?" })

        expect(ctx.result.rounds_used).to.equal(3)
        expect(#ctx.result.transcript).to.equal(6)
    end)

    it("honors an explicit ctx.rounds", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        local ctx = m.run({ question = "Q?", rounds = 1 })

        expect(ctx.result.rounds_used).to.equal(1)
        expect(#ctx.result.transcript).to.equal(2)
        expect(rec.llm_calls).to.equal(3) -- 2*1 + 1
    end)

    it("_internal.DEFAULT_ROUNDS is 3 (Khan 2024 §3 canonical)", function()
        reset()
        _G.alc = make_alc_stub()
        local m = require("debate")
        expect(m._internal.DEFAULT_ROUNDS).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 3: judge_criteria injection
-- ═══════════════════════════════════════════════════════════════════

describe("debate.run judge_criteria injection", function()
    lust.after(reset)

    it("injects ctx.judge_criteria verbatim into the judge prompt", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        m.run({
            question = "Q?",
            rounds = 1,
            judge_criteria = "MUST cite a peer-reviewed source XYZ123",
        })

        -- Judge is the last call (2*1 + 1 = 3rd).
        expect(rec.prompts[3]:find("MUST cite a peer-reviewed source XYZ123", 1, true))
            .to_not.equal(nil)
    end)

    it("falls back to the default criteria when ctx.judge_criteria omitted", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("debate")
        local default_criteria = m._internal.DEFAULT_JUDGE_CRITERIA
        m.run({ question = "Q?", rounds = 1 })

        expect(rec.prompts[3]:find(default_criteria, 1, true)).to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 4: ctx.question validation
-- ═══════════════════════════════════════════════════════════════════

describe("debate.run question validation", function()
    lust.after(reset)

    it("errors when ctx.question is missing", function()
        reset()
        _G.alc = make_alc_stub()
        local m = require("debate")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("question") ~= nil).to.equal(true)
    end)

    it("errors when ctx.question is empty string", function()
        reset()
        _G.alc = make_alc_stub()
        local m = require("debate")
        local ok, err = pcall(m.run, { question = "" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("question") ~= nil).to.equal(true)
    end)

    it("errors when ctx.question is whitespace only", function()
        reset()
        _G.alc = make_alc_stub()
        local m = require("debate")
        local ok, err = pcall(m.run, { question = "   \t  " })
        expect(ok).to.equal(false)
        expect(tostring(err):find("question") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 5: judge output parsing + fallback
-- ═══════════════════════════════════════════════════════════════════

describe("debate._internal.parse_judge_output", function()
    reset()
    _G.alc = make_alc_stub()
    local m = require("debate")
    local parse = m._internal.parse_judge_output

    it("parses WINNER / VERDICT / RATIONALE from a well-formed block", function()
        local w, v, r = parse(
            "WINNER: B\nVERDICT: B was more persuasive.\nRATIONALE: B cited data.\n")
        expect(w).to.equal("B")
        expect(v).to.equal("B was more persuasive.")
        expect(r).to.equal("B cited data.")
    end)

    it("returns nil winner when WINNER marker is absent or malformed", function()
        local w, _v, _r = parse("VERDICT: unclear.\nRATIONALE: tie.\n")
        expect(w).to.equal(nil)
    end)

    it("only accepts A or B as WINNER value", function()
        local w, _v, _r = parse("WINNER: Q\nVERDICT: x\nRATIONALE: y\n")
        expect(w).to.equal(nil)
    end)
end)

describe("debate.run judge winner extraction", function()
    lust.after(reset)

    it("propagates WINNER: B from the judge output", function()
        reset()
        local stub = make_alc_stub({
            judge_out = "WINNER: B\nVERDICT: B wins.\nRATIONALE: strong evidence.\n",
        })
        _G.alc = stub
        local m = require("debate")
        local ctx = m.run({ question = "Q?", rounds = 1 })

        expect(ctx.result.winner).to.equal("B")
        expect(ctx.result.verdict).to.equal("B wins.")
        expect(ctx.result.rationale).to.equal("strong evidence.")
    end)

    it("defaults winner to \"A\" when the WINNER marker is unparsable", function()
        reset()
        local stub = make_alc_stub({
            judge_out = "(no clear verdict — the debate was close)\n",
        })
        _G.alc = stub
        local m = require("debate")
        local ctx = m.run({ question = "Q?", rounds = 1 })

        expect(ctx.result.winner).to.equal("A")
    end)
end)

reset()
