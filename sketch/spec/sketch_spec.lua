--- Tests for sketch package (Sketch-of-Thought, Aytes, Baek & Hwang
--- 2025 arXiv:2503.05179, EMNLP 2025).
---
--- Run via:
---   just alc-pkg-test-file sketch/spec/sketch_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- Build a mock _G.alc.
---   opts.execute_response — what the paradigm-execute stub returns.
---     Default has parseable <sketch>...</sketch> + Answer.
---   opts.route_paradigm — paradigm name to return from llm_route stub.
local function mock_alc(opts)
    opts = opts or {}
    local execute_response = opts.execute_response
        or "<sketch>\nA → B → C\n</sketch>\nAnswer: final ABC"
    local route_paradigm = opts.route_paradigm or "chunked_symbolism"
    local call_log = {}
    local log_calls = {}
    local c = { route = 0, execute = 0 }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Classify this problem into exactly ONE", 1, true) then
                c.route = c.route + 1
                return route_paradigm
            else
                c.execute = c.execute + 1
                return execute_response
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
    package.loaded["sketch"] = nil
end

describe("sketch.meta", function()
    reset()
    mock_alc()
    local m = require("sketch")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("sketch")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("sketch.spec", function()
    reset()
    mock_alc()
    local m = require("sketch")
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("sketch.run", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("sketch")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("ctx.task")).to_not.equal(nil)
    end)

    it("manual paradigm bypasses routing (1 LLM call, method='manual')", function()
        reset()
        local log = mock_alc()
        local m = require("sketch")
        local ctx = m.run({ task = "T", paradigm = "conceptual_chaining" })
        expect(#log).to.equal(1)
        expect(ctx.result.paradigm).to.equal("conceptual_chaining")
        expect(ctx.result.routing.method).to.equal("manual")
        expect(ctx.result.routing.confidence).to.equal(1.0)
        expect(ctx.result.answer).to.equal("final ABC")
        expect(ctx.result.reasoning:find("A → B → C", 1, true)).to_not.equal(nil)
    end)

    it("keyword routing fires on a math-heavy task (chunked_symbolism)", function()
        reset()
        local log = mock_alc()
        local m = require("sketch")
        local ctx = m.run({
            task = "calculate the total cost: 3 * 5 + 2.5 = ?",
            routing_threshold = 0.0,  -- accept any positive keyword confidence
        })
        -- routing is keyword-based → 1 execute call only (no llm_route)
        expect(#log).to.equal(1)
        expect(ctx.result.routing.method).to.equal("keyword")
        expect(ctx.result.paradigm).to.equal("chunked_symbolism")
    end)

    it("low keyword confidence falls back to LLM routing (2 LLM calls)", function()
        reset()
        local log = mock_alc({ route_paradigm = "chunked_symbolism" })
        local m = require("sketch")
        local ctx = m.run({
            task = "xyz",  -- no keywords
            routing_threshold = 0.5,
        })
        -- llm_route (1) + execute (1) = 2 calls
        expect(#log).to.equal(2)
        expect(ctx.result.routing.method).to.equal("llm")
        expect(ctx.result.paradigm).to.equal("chunked_symbolism")
    end)

    it("unknown manually-supplied paradigm falls back to conceptual_chaining + warn", function()
        reset()
        local log, log_calls = mock_alc()
        local m = require("sketch")
        local ctx = m.run({ task = "T", paradigm = "bogus_name" })
        expect(ctx.result.paradigm).to.equal("conceptual_chaining")
        local warn_seen = false
        for _, lc in ipairs(log_calls) do
            if lc.level == "warn" then warn_seen = true end
        end
        expect(warn_seen).to.equal(true)
    end)

    it("LLM-route response 'expert' selects expert_lexicons", function()
        reset()
        mock_alc({ route_paradigm = "expert_lexicons please" })
        local m = require("sketch")
        local ctx = m.run({ task = "xyz", routing_threshold = 0.5 })
        expect(ctx.result.paradigm).to.equal("expert_lexicons")
    end)
end)

reset()
