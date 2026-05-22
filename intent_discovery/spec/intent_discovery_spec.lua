--- Tests for intent_discovery package ("DiscoverLLM: From Executing
--- Intents to Discovering Them" 2026 arXiv:2602.03429). Uses
--- alc.llm + alc.log + alc.specify (user-preference channel).
---
--- Run via:
---   just alc-pkg-test-file intent_discovery/spec/intent_discovery_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local OPTIONS_TEXT =
    "Option A: First approach — short desc one\n"
 .. "Option B: Second approach — short desc two\n"
 .. "Option C: Third approach — short desc three\n"
 .. "KEY_DIMENSION: which axis matters most\n"

--- Build a mock _G.alc.
---   opts.converge — if true, the concretize stub embeds CONVERGENCE: YES
---     so the loop breaks early.
---   opts.options_text — raw output of the Phase 1 surface stub.
local function mock_alc(opts)
    opts = opts or {}
    local options_text = opts.options_text or OPTIONS_TEXT
    local converge = opts.converge
    local call_log = {}
    local log_calls = {}
    local specify_calls = {}
    local c = { surface = 0, concretize = 0, specify = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Generate exactly %d+ distinct approaches") then
                c.surface = c.surface + 1
                return options_text
            else
                c.concretize = c.concretize + 1
                return string.format(
                    "RESOLVED: ok\nREMAINING: nothing\nUPDATED_INTENT: refined task r%d\nCONVERGENCE: %s",
                    c.concretize, converge and "YES" or "NO"
                )
            end
        end,
        specify = function(prompt, options)
            c.specify = c.specify + 1
            specify_calls[#specify_calls + 1] = { prompt = prompt, opts = options }
            return "user_pref_" .. c.specify
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls, specify_calls
end

local function reset()
    _G.alc = nil
    package.loaded["intent_discovery"] = nil
end

describe("intent_discovery.meta", function()
    reset()
    mock_alc()
    local m = require("intent_discovery")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("intent_discovery")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("intent")
    end)
end)

describe("intent_discovery.spec", function()
    reset()
    mock_alc()
    local m = require("intent_discovery")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("intent_discovery.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("intent_discovery")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default max_rounds=3 with CONVERGENCE: NO → 3 rounds × (surface + concretize) = 6 llm + 3 specify", function()
        reset()
        local log, _, specify_log = mock_alc({ converge = false })
        local m = require("intent_discovery")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(6)
        expect(#specify_log).to.equal(3)
        expect(ctx.result.rounds).to.equal(3)
        expect(#ctx.result.exploration_log).to.equal(3)
        expect(#ctx.result.intent_hierarchy).to.equal(3)
    end)

    it("CONVERGENCE: YES breaks the loop after round 1", function()
        reset()
        local log, _, specify_log = mock_alc({ converge = true })
        local m = require("intent_discovery")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(2)  -- 1 surface + 1 concretize
        expect(#specify_log).to.equal(1)
        expect(ctx.result.rounds).to.equal(1)
        expect(ctx.result.converged).to.equal(true)
    end)

    it("populates exploration_log[i] with options + preference + key_dimension", function()
        reset()
        mock_alc({ converge = true })
        local m = require("intent_discovery")
        local ctx = m.run({ task = "T" })
        local entry = ctx.result.exploration_log[1]
        expect(#entry.options).to.equal(3)
        expect(entry.options[1].label).to.equal("A")
        expect(entry.options[1].title).to.equal("First approach")
        expect(entry.options[1].description).to.equal("short desc one")
        expect(entry.preference).to.equal("user_pref_1")
        expect(entry.key_dimension:find("which axis matters most")).to_not.equal(nil)
    end)

    it("intent_hierarchy[i] captures resolved / remaining / understanding", function()
        reset()
        mock_alc({ converge = true })
        local m = require("intent_discovery")
        local ctx = m.run({ task = "T" })
        local h = ctx.result.intent_hierarchy[1]
        expect(h.resolved:find("ok")).to_not.equal(nil)
        expect(h.remaining:find("nothing")).to_not.equal(nil)
        expect(h.understanding:find("refined task r1")).to_not.equal(nil)
        expect(ctx.result.specified_task).to.equal(h.understanding)
    end)

    it("unparseable options output → warn log + early break", function()
        reset()
        local log, log_calls = mock_alc({ options_text = "no options here at all" })
        local m = require("intent_discovery")
        local ctx = m.run({ task = "T" })
        expect(ctx.result.rounds).to.equal(0)
        local warn_seen = false
        for _, lc in ipairs(log_calls) do
            if lc.level == "warn" then warn_seen = true end
        end
        expect(warn_seen).to.equal(true)
    end)
end)

reset()
