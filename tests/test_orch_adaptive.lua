--- Tests for orch_adaptive package

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
        json_decode = function() return nil end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["orch_adaptive"] = nil
end

local ALL_PHASES = {
    { name = "plan", prompt = "Plan: {task}", gate = "OK?" },
    { name = "implement", prompt = "Impl: {prev_output}", gate = "OK?" },
    { name = "review", prompt = "Review: {prev_output}", gate = "OK?" },
    { name = "test", prompt = "Test: {prev_output}", gate = "OK?" },
    { name = "docs", prompt = "Docs: {prev_output}" },
    { name = "deploy", prompt = "Deploy: {prev_output}" },
}

-- ================================================================
describe("orch_adaptive: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        local m = require("orch_adaptive")
        expect(m.meta.name).to.equal("orch_adaptive")
        expect(m.meta.category).to.equal("orchestration")
    end)
end)

-- ================================================================
describe("orch_adaptive: simple difficulty", function()
    lust.after(reset)

    it("limits to 2 phases for simple tasks", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "YES" end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Fix typo",
            difficulty = "simple", -- pre-classified
            phases = ALL_PHASES,
        })

        expect(ctx.result.difficulty).to.equal("simple")
        expect(ctx.result.active_phase_count).to.equal(2)
        expect(ctx.result.total_phase_count).to.equal(6)
        expect(#ctx.result.phases).to.equal(2)
        expect(ctx.result.phases[1].name).to.equal("plan")
        expect(ctx.result.phases[2].name).to.equal("implement")
    end)
end)

-- ================================================================
describe("orch_adaptive: medium difficulty", function()
    lust.after(reset)

    it("limits to 4 phases for medium tasks", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "YES" end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Add endpoint",
            difficulty = "medium",
            phases = ALL_PHASES,
        })

        expect(ctx.result.active_phase_count).to.equal(4)
    end)
end)

-- ================================================================
describe("orch_adaptive: complex difficulty", function()
    lust.after(reset)

    it("uses all 6 phases for complex tasks", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "YES" end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Build auth subsystem",
            difficulty = "complex",
            phases = ALL_PHASES,
        })

        expect(ctx.result.active_phase_count).to.equal(6)
        expect(ctx.result.depth_config.context_mode).to.equal("full")
        expect(ctx.result.depth_config.max_retries).to.equal(5)
    end)
end)

-- ================================================================
describe("orch_adaptive: auto-classification", function()
    lust.after(reset)

    it("classifies via LLM when difficulty not provided", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "simple" end -- classification
            if prompt:match("Evaluate") then return "YES" end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Fix typo",
            phases = ALL_PHASES,
        })

        expect(ctx.result.difficulty).to.equal("simple")
        expect(ctx.result.active_phase_count).to.equal(2)
        -- 1 classification + phase calls
        expect(log[1].opts.max_tokens).to.equal(20) -- classification call
    end)
end)

-- ================================================================
describe("orch_adaptive: retry budget", function()
    lust.after(reset)

    it("simple gets max 1 retry", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "NO" end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Fix typo",
            difficulty = "simple",
            on_fail = "partial",
            phases = {
                { name = "impl", prompt = "{task}", gate = "OK?" },
            },
        })

        expect(ctx.result.phases[1].attempts).to.equal(1) -- max_retries=1
    end)

    it("complex gets max 5 retries", function()
        local attempt_tracker = 0
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then
                attempt_tracker = attempt_tracker + 1
                return "NO"
            end
            return "output"
        end)
        package.loaded["orch_adaptive"] = nil
        local m = require("orch_adaptive")
        local ctx = m.run({
            task = "Build subsystem",
            difficulty = "complex",
            on_fail = "partial",
            phases = {
                { name = "impl", prompt = "{task}", gate = "OK?" },
            },
        })

        expect(ctx.result.phases[1].attempts).to.equal(5)
        expect(attempt_tracker).to.equal(5)
    end)
end)
