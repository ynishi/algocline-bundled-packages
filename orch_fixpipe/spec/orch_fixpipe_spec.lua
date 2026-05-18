--- Tests for orch_fixpipe package

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
    package.loaded["orch_fixpipe"] = nil
end

-- ================================================================
describe("orch_fixpipe: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        local m = require("orch_fixpipe")
        expect(m.meta.name).to.equal("orch_fixpipe")
        expect(m.meta.category).to.equal("orchestration")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ok, err = pcall(m.run, { phases = {} })
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.phases", function()
        mock_alc(function() return "mock" end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.phases is required")).to_not.equal(nil)
    end)
end)

-- ================================================================
describe("orch_fixpipe: all gates pass", function()
    lust.after(reset)

    it("completes with status=completed", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "YES, looks good" end
            return "phase output"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ctx = m.run({
            task = "Build feature",
            context_mode = "full",
            phases = {
                { name = "plan", prompt = "Plan: {task}", gate = "Good plan?" },
                { name = "impl", prompt = "Implement: {prev_output}", gate = "Correct?" },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(#ctx.result.phases).to.equal(2)
        expect(ctx.result.phases[1].gate_passed).to.equal(true)
        expect(ctx.result.phases[2].gate_passed).to.equal(true)
        expect(ctx.result.phases[1].attempts).to.equal(1)
        -- 2 phases x (1 exec + 1 gate) = 4 LLM calls
        expect(ctx.result.total_llm_calls).to.equal(4)
    end)
end)

-- ================================================================
describe("orch_fixpipe: gate retry", function()
    lust.after(reset)

    it("retries on gate failure then succeeds", function()
        local attempt_count = 0
        local log = mock_alc(function(prompt)
            if prompt:match("Evaluate") then
                attempt_count = attempt_count + 1
                if attempt_count == 1 then return "NO, missing tests" end
                return "YES, all good"
            end
            return "phase output"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ctx = m.run({
            task = "Build feature",
            max_retries = 3,
            context_mode = "full",
            phases = {
                { name = "impl", prompt = "Implement: {task}. Feedback: {feedback}", gate = "OK?" },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.phases[1].attempts).to.equal(2)
        expect(ctx.result.phases[1].gate_passed).to.equal(true)
    end)
end)

-- ================================================================
describe("orch_fixpipe: max_retries exhausted", function()
    lust.after(reset)

    it("returns failed on error mode", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "NO, still broken" end
            return "bad output"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ctx = m.run({
            task = "Build feature",
            max_retries = 2,
            on_fail = "error",
            context_mode = "full",
            phases = {
                { name = "impl", prompt = "Do: {task}", gate = "OK?" },
                { name = "review", prompt = "Review: {prev_output}", gate = "OK?" },
            },
        })

        expect(ctx.result.status).to.equal("failed")
        expect(#ctx.result.phases).to.equal(1) -- stopped at first failure
        expect(ctx.result.phases[1].gate_passed).to.equal(false)
    end)

    it("returns partial on partial mode", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "NO" end
            return "output"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ctx = m.run({
            task = "Build feature",
            max_retries = 1,
            on_fail = "partial",
            context_mode = "full",
            phases = {
                { name = "p1", prompt = "{task}", gate = "OK?" },
                { name = "p2", prompt = "{prev_output}", gate = "OK?" },
            },
        })

        expect(ctx.result.status).to.equal("partial")
        expect(#ctx.result.phases).to.equal(2) -- continues in partial mode
    end)
end)

-- ================================================================
describe("orch_fixpipe: no gate (auto-pass)", function()
    lust.after(reset)

    it("auto-passes phases without gate", function()
        local log = mock_alc(function() return "output" end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        local ctx = m.run({
            task = "Do thing",
            context_mode = "full",
            phases = {
                { name = "p1", prompt = "Do: {task}" },
                { name = "p2", prompt = "Continue: {prev_output}" },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.phases[1].gate_passed).to.equal(true)
        expect(ctx.result.phases[2].gate_passed).to.equal(true)
        -- No gate calls: 2 exec only
        expect(ctx.result.total_llm_calls).to.equal(2)
    end)
end)

-- ================================================================
describe("orch_fixpipe: template expansion", function()
    lust.after(reset)

    it("expands {task} and {prev_output}", function()
        local prompts = {}
        mock_alc(function(prompt)
            prompts[#prompts + 1] = prompt
            return "output_text"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        m.run({
            task = "MY_TASK",
            context_mode = "full",
            phases = {
                { name = "p1", prompt = "Task is {task}" },
                { name = "p2", prompt = "Prev: {prev_output}" },
            },
        })

        expect(prompts[1]:match("MY_TASK")).to_not.equal(nil)
        expect(prompts[2]:match("output_text")).to_not.equal(nil)
    end)

    it("handles % in values without error", function()
        local prompts = {}
        mock_alc(function(prompt)
            prompts[#prompts + 1] = prompt
            return "100% complete %d %s %%"
        end)
        package.loaded["orch_fixpipe"] = nil
        local m = require("orch_fixpipe")
        m.run({
            task = "task with 50% progress",
            context_mode = "full",
            phases = {
                { name = "p1", prompt = "Do: {task}" },
                { name = "p2", prompt = "Prev: {prev_output}" },
            },
        })

        expect(prompts[1]).to.equal("Do: task with 50% progress")
        expect(prompts[2]).to.equal("Prev: 100% complete %d %s %%")
    end)
end)
