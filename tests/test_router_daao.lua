--- Tests for router_daao package
--- Structural tests + parse logic tests (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

--- Build a mock alc global. call_log records all llm calls.
--- llm_fn is called with (prompt, opts) and should return a string.
local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        json_decode = function(s)
            -- Minimal JSON decoder for test purposes
            -- Handles {"difficulty": "...", "reasoning": "..."}
            local diff = s:match('"difficulty"%s*:%s*"([^"]+)"')
            local reason = s:match('"reasoning"%s*:%s*"([^"]*)"')
            if diff then
                return { difficulty = diff, reasoning = reason }
            end
            return nil
        end,
    }
    _G.alc = a
    return call_log
end

--- Reset alc and unload package from cache.
local function reset()
    _G.alc = nil
    package.loaded["router_daao"] = nil
end

-- ================================================================
-- Meta & Structure
-- ================================================================
describe("router_daao: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        local m = require("router_daao")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("router_daao")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("routing")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return '{}' end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)
end)

-- ================================================================
-- Classification: simple
-- ================================================================
describe("router_daao: simple classification", function()
    lust.after(reset)

    it("routes simple tasks correctly", function()
        local log = mock_alc(function()
            return '{"difficulty": "simple", "reasoning": "Single file typo fix"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Fix typo in README.md" })

        expect(#log).to.equal(1) -- exactly 1 LLM call
        expect(ctx.result.difficulty).to.equal("simple")
        expect(ctx.result.selected).to.equal("orch_fixpipe")
        expect(ctx.result.confidence).to.equal(0.85)
        expect(ctx.result.reasoning).to.equal("Single file typo fix")
        expect(ctx.result.profile.depth).to.equal(1)
        expect(ctx.result.profile.max_retries).to.equal(1)
    end)
end)

-- ================================================================
-- Classification: medium
-- ================================================================
describe("router_daao: medium classification", function()
    lust.after(reset)

    it("routes medium tasks correctly", function()
        local log = mock_alc(function()
            return '{"difficulty": "medium", "reasoning": "Multi-file refactor"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Add new API endpoint for users" })

        expect(#log).to.equal(1)
        expect(ctx.result.difficulty).to.equal("medium")
        expect(ctx.result.selected).to.equal("orch_gatephase")
        expect(ctx.result.confidence).to.equal(0.7) -- medium has lower confidence
        expect(ctx.result.profile.depth).to.equal(2)
        expect(ctx.result.profile.max_retries).to.equal(3)
    end)
end)

-- ================================================================
-- Classification: complex
-- ================================================================
describe("router_daao: complex classification", function()
    lust.after(reset)

    it("routes complex tasks correctly", function()
        local log = mock_alc(function()
            return '{"difficulty": "complex", "reasoning": "New subsystem with cross-cutting concerns"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Implement session management with Redis backend" })

        expect(#log).to.equal(1)
        expect(ctx.result.difficulty).to.equal("complex")
        expect(ctx.result.selected).to.equal("orch_gatephase")
        expect(ctx.result.confidence).to.equal(0.85)
        expect(ctx.result.profile.depth).to.equal(3)
        expect(ctx.result.profile.max_retries).to.equal(5)
        expect(ctx.result.profile.context_mode).to.equal("full")
        -- alternatives should include both recommendations
        expect(#ctx.result.alternatives).to.equal(2)
    end)
end)

-- ================================================================
-- JSON parse fallback
-- ================================================================
describe("router_daao: parse fallback", function()
    lust.after(reset)

    it("extracts JSON from noisy LLM response", function()
        mock_alc(function()
            return 'Here is my classification:\n{"difficulty": "simple", "reasoning": "trivial"}\nDone.'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Fix typo" })

        expect(ctx.result.difficulty).to.equal("simple")
        expect(ctx.result.reasoning).to.equal("trivial")
    end)

    it("falls back to medium on unparseable response", function()
        mock_alc(function()
            return "I cannot classify this task properly."
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Something ambiguous" })

        expect(ctx.result.difficulty).to.equal("medium")
        expect(ctx.result.confidence).to.equal(0.5) -- lower confidence for parse failure
        expect(ctx.result.reasoning).to.equal("Classification parse failed, using default")
    end)

    it("falls back to medium on unknown difficulty level", function()
        mock_alc(function()
            return '{"difficulty": "extreme", "reasoning": "off the charts"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({ task = "Something weird" })

        expect(ctx.result.difficulty).to.equal("medium")
        -- reasoning should still be from classification
        expect(ctx.result.reasoning).to.equal("off the charts")
    end)
end)

-- ================================================================
-- Candidates matching
-- ================================================================
describe("router_daao: candidates", function()
    lust.after(reset)

    it("selects matching candidate from profile recommendations", function()
        mock_alc(function()
            return '{"difficulty": "complex", "reasoning": "complex task"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({
            task = "Build new subsystem",
            candidates = { "orch_fixpipe", "orch_nver" },
        })

        -- complex profile recommends orch_gatephase first, then orch_nver
        -- orch_nver matches, so it should be selected
        expect(ctx.result.selected).to.equal("orch_nver")
    end)

    it("uses first candidate when no match found", function()
        mock_alc(function()
            return '{"difficulty": "simple", "reasoning": "easy"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({
            task = "Fix typo",
            candidates = { "custom_strategy_a", "custom_strategy_b" },
        })

        -- simple recommends orch_fixpipe, but neither candidate matches
        expect(ctx.result.selected).to.equal("custom_strategy_a")
    end)

    it("handles table-format candidates with .name field", function()
        mock_alc(function()
            return '{"difficulty": "medium", "reasoning": "medium task"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({
            task = "Refactor module",
            candidates = {
                { name = "orch_gatephase", description = "Gate-based pipeline" },
                { name = "orch_fixpipe", description = "Fixed pipeline" },
            },
        })

        -- medium recommends orch_gatephase, which matches first candidate
        expect(ctx.result.selected).to.equal("orch_gatephase")
    end)

    it("handles empty candidates list gracefully", function()
        mock_alc(function()
            return '{"difficulty": "simple", "reasoning": "easy"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local ctx = m.run({
            task = "Fix typo",
            candidates = {},
        })

        -- Empty list = use default from profile
        expect(ctx.result.selected).to.equal("orch_fixpipe")
    end)
end)

-- ================================================================
-- Custom profiles
-- ================================================================
describe("router_daao: custom profiles", function()
    lust.after(reset)

    it("uses custom profiles when provided", function()
        mock_alc(function()
            return '{"difficulty": "simple", "reasoning": "easy"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        local custom = {
            simple = {
                depth = 0,
                max_retries = 0,
                recommended_strategies = { "direct_fix" },
                skip_phases = { "plan", "review" },
                context_mode = "none",
            },
            medium = {
                depth = 1,
                max_retries = 1,
                recommended_strategies = { "light_review" },
                skip_phases = {},
                context_mode = "summary",
            },
            complex = {
                depth = 5,
                max_retries = 10,
                recommended_strategies = { "full_review" },
                skip_phases = {},
                context_mode = "full",
            },
        }
        local ctx = m.run({
            task = "Quick fix",
            profiles = custom,
        })

        expect(ctx.result.selected).to.equal("direct_fix")
        expect(ctx.result.profile.depth).to.equal(0)
        expect(ctx.result.profile.max_retries).to.equal(0)
    end)
end)

-- ================================================================
-- LLM call count
-- ================================================================
describe("router_daao: LLM efficiency", function()
    lust.after(reset)

    it("always makes exactly 1 LLM call regardless of difficulty", function()
        for _, diff in ipairs({ "simple", "medium", "complex" }) do
            local log = mock_alc(function()
                return '{"difficulty": "' .. diff .. '", "reasoning": "test"}'
            end)
            package.loaded["router_daao"] = nil
            local m = require("router_daao")
            m.run({ task = "Test task for " .. diff })
            expect(#log).to.equal(1)
        end
    end)

    it("passes correct system prompt and max_tokens", function()
        local log = mock_alc(function()
            return '{"difficulty": "simple", "reasoning": "test"}'
        end)
        package.loaded["router_daao"] = nil
        local m = require("router_daao")
        m.run({ task = "Test task" })

        local call = log[1]
        expect(call.opts.max_tokens).to.equal(100)
        expect(call.opts.system:match("task difficulty classifier")).to_not.equal(nil)
        expect(call.prompt:match("Classify this task")).to_not.equal(nil)
    end)
end)
