--- Tests for router_semantic package

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        json_decode = function(s)
            local sel = s:match('"selected"%s*:%s*"([^"]+)"')
            local conf = s:match('"confidence"%s*:%s*([%d%.]+)')
            local reason = s:match('"reasoning"%s*:%s*"([^"]*)"')
            if sel then
                return { selected = sel, confidence = tonumber(conf), reasoning = reason }
            end
            return nil
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["router_semantic"] = nil
end

-- ================================================================
describe("router_semantic: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        local m = require("router_semantic")
        expect(m.meta.name).to.equal("router_semantic")
        expect(m.meta.category).to.equal("routing")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)
end)

-- ================================================================
describe("router_semantic: keyword match (0 LLM calls)", function()
    lust.after(reset)

    it("matches bugfix keywords", function()
        local log = mock_alc(function() return "should not be called" end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({ task = "Fix the crash bug in session handler" })

        expect(#log).to.equal(0) -- no LLM calls
        expect(ctx.result.selected).to.equal("bugfix")
        expect(ctx.result.method).to.equal("keyword")
        expect(ctx.result.confidence > 0).to.equal(true)
    end)

    it("matches feature keywords", function()
        local log = mock_alc(function() return "mock" end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({ task = "Add new support for creating users" })

        expect(#log).to.equal(0)
        expect(ctx.result.selected).to.equal("feature")
        expect(ctx.result.method).to.equal("keyword")
    end)

    it("matches refactor keywords", function()
        local log = mock_alc(function() return "mock" end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({ task = "Refactor and simplify the extract logic" })

        expect(#log).to.equal(0)
        expect(ctx.result.selected).to.equal("refactor")
    end)
end)

-- ================================================================
describe("router_semantic: LLM fallback (1 LLM call)", function()
    lust.after(reset)

    it("falls back to LLM when no keyword match", function()
        local log = mock_alc(function()
            return '{"selected": "feature", "confidence": 0.8, "reasoning": "Looks like a feature"}'
        end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({ task = "Migrate the database schema to v2" })

        expect(#log).to.equal(1) -- 1 LLM call
        expect(ctx.result.selected).to.equal("feature")
        expect(ctx.result.method).to.equal("llm_fallback")
        expect(ctx.result.confidence).to.equal(0.8)
    end)

    it("falls back to keyword_forced on LLM parse failure", function()
        local log = mock_alc(function()
            return "I'm not sure how to classify this."
        end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({ task = "Migrate the database schema to v2" })

        expect(#log).to.equal(1)
        expect(ctx.result.method).to.equal("keyword_forced")
    end)
end)

-- ================================================================
describe("router_semantic: custom rules + threshold", function()
    lust.after(reset)

    it("uses custom rules", function()
        local log = mock_alc(function() return "mock" end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        local ctx = m.run({
            task = "Migrate the schema and alter tables",
            rules = {
                { name = "migration", keywords = { "migrate", "schema", "alter", "table" }, description = "DB migration" },
                { name = "feature", keywords = { "add", "implement" }, description = "Feature" },
            },
        })

        expect(#log).to.equal(0) -- keyword match
        expect(ctx.result.selected).to.equal("migration")
    end)

    it("respects higher threshold", function()
        local log = mock_alc(function()
            return '{"selected": "bugfix", "confidence": 0.9, "reasoning": "test"}'
        end)
        package.loaded["router_semantic"] = nil
        local m = require("router_semantic")
        -- "fix" matches 1/7 keywords = 0.14, below threshold 0.5
        local ctx = m.run({ task = "Fix the typo", threshold = 0.5 })

        expect(#log).to.equal(1) -- forced LLM due to high threshold
        expect(ctx.result.method).to.equal("llm_fallback")
    end)
end)
