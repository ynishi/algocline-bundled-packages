--- Tests for panel package (multi-perspective deliberation + moderator
--- synthesis).
---
--- Run via:
---   just alc-pkg-test-file panel/spec/panel_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local function mock_alc()
    local call_log = {}
    local c = { argue = 0, synth = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Synthesize: identify agreements", 1, true) then
                c.synth = c.synth + 1
                return "moderator_synthesis_" .. c.synth
            else
                c.argue = c.argue + 1
                return "argument_" .. c.argue
            end
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["panel"] = nil
end

describe("panel.meta", function()
    reset()
    mock_alc()
    local m = require("panel")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("panel")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("synthesis")
    end)
end)

describe("panel.spec", function()
    reset()
    mock_alc()
    local m = require("panel")
    it("declares run with result tag", function()
        expect(m.spec.entries.run).to_not.equal(nil)
        expect(m.spec.entries.run.result).to.equal("paneled")
    end)
end)

describe("panel.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("panel")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("default 3 roles → 3 arguments + 1 synthesis = 4 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("panel")
        local ctx = m.run({ task = "T" })
        expect(#log).to.equal(4)
        expect(#ctx.result.arguments).to.equal(3)
        expect(ctx.result.arguments[1].role).to.equal("advocate")
        expect(ctx.result.arguments[2].role).to.equal("critic")
        expect(ctx.result.arguments[3].role).to.equal("pragmatist")
        expect(ctx.result.synthesis).to.equal("moderator_synthesis_1")
    end)

    it("custom roles override the default trio", function()
        reset()
        local log = mock_alc()
        local m = require("panel")
        local ctx = m.run({ task = "T", roles = { "expert", "skeptic" } })
        -- 2 arguments + 1 synthesis = 3 calls
        expect(#log).to.equal(3)
        expect(#ctx.result.arguments).to.equal(2)
        expect(ctx.result.arguments[1].role).to.equal("expert")
        expect(ctx.result.arguments[2].role).to.equal("skeptic")
    end)

    it("first role prompt has no prior arguments; later roles see them", function()
        reset()
        local log = mock_alc()
        local m = require("panel")
        m.run({ task = "T" })
        -- log[1] = role 1 initial, log[2] = role 2 with context, log[3] = role 3 with context
        expect(log[1].prompt:find("Previous arguments", 1, true)).to.equal(nil)
        expect(log[2].prompt:find("Previous arguments", 1, true)).to_not.equal(nil)
        expect(log[2].prompt:find("argument_1", 1, true)).to_not.equal(nil)
    end)

    it("synthesis prompt embeds every role's argument", function()
        reset()
        local log = mock_alc()
        local m = require("panel")
        m.run({ task = "T" })
        local synth_prompt = log[#log].prompt
        for i = 1, 3 do
            expect(synth_prompt:find("argument_" .. i, 1, true)).to_not.equal(nil)
        end
    end)
end)

reset()
