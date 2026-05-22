--- Tests for cod package (Chain-of-Density, Adams et al. 2023
--- arXiv:2309.04269). Note ctx.text (not ctx.task) is the input field.
---
--- Run via:
---   just alc-pkg-test-file cod/spec/cod_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local function mock_alc()
    local call_log = {}
    local log_calls = {}
    local c = { sparse = 0, dense = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Rewrite this summary to be DENSER", 1, true) then
                c.dense = c.dense + 1
                return "dense_round_" .. c.dense .. " text"
            else
                c.sparse = c.sparse + 1
                return "sparse summary text"
            end
        end,
        log = function(level, msg)
            log_calls[#log_calls + 1] = { level = level, msg = msg }
        end,
    }
    return call_log, log_calls
end

local function reset()
    _G.alc = nil
    package.loaded["cod"] = nil
end

describe("cod.meta", function()
    reset()
    mock_alc()
    local m = require("cod")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("cod")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("optimization")
    end)
end)

describe("cod.spec", function()
    reset()
    mock_alc()
    local m = require("cod")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("cod.run", function()
    it("errors when ctx.text is missing (note: text, not task)", function()
        reset()
        mock_alc()
        local m = require("cod")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.text")).to_not.equal(nil)
    end)

    it("default rounds=3 → 1 sparse + 3 dense = 4 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("cod")
        local ctx = m.run({ text = "some source text with many words to summarize here" })
        expect(#log).to.equal(4)
        expect(ctx.result.total_rounds).to.equal(3)
        -- history has round 0 + 3 dense rounds = 4 entries
        expect(#ctx.result.history).to.equal(4)
        expect(ctx.result.history[1].round).to.equal(0)
        expect(ctx.result.history[4].round).to.equal(3)
    end)

    it("rounds=1 → 1 sparse + 1 dense = 2 LLM calls", function()
        reset()
        local log = mock_alc()
        local m = require("cod")
        local ctx = m.run({ text = "src", rounds = 1 })
        expect(#log).to.equal(2)
        expect(ctx.result.total_rounds).to.equal(1)
        expect(#ctx.result.history).to.equal(2)
    end)

    it("output is the last dense round's text", function()
        reset()
        mock_alc()
        local m = require("cod")
        local ctx = m.run({ text = "src", rounds = 2 })
        expect(ctx.result.output).to.equal("dense_round_2 text")
    end)

    it("computes input_words / output_words / compression_ratio", function()
        reset()
        mock_alc()
        local m = require("cod")
        local ctx = m.run({ text = "one two three four five", rounds = 1 })
        expect(ctx.result.input_words).to.equal(5)
        -- "sparse summary text" = 3 words but output is "dense_round_1 text" = 2
        expect(ctx.result.output_words).to.equal(2)
        expect(ctx.result.compression_ratio).to.equal(2 / 5)
    end)

    it("target_length override is embedded in the sparse prompt", function()
        reset()
        local log = mock_alc()
        local m = require("cod")
        m.run({ text = "src", rounds = 0, target_length = 17 })
        expect(log[1].prompt:find("approximately 17 words", 1, true)).to_not.equal(nil)
    end)
end)

reset()
