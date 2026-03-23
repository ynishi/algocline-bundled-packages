--- Tests for orch_gatephase package

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
    package.loaded["orch_gatephase"] = nil
end

-- ================================================================
describe("orch_gatephase: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        local m = require("orch_gatephase")
        expect(m.meta.name).to.equal("orch_gatephase")
        expect(m.meta.category).to.equal("orchestration")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ok, err = pcall(m.run, { phases = {} })
        expect(ok).to.equal(false)
    end)
end)

-- ================================================================
describe("orch_gatephase: skip rules", function()
    lust.after(reset)

    it("skips design phase for bugfix", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Evaluate") or prompt:match("Answer") then return "YES" end
            return "output"
        end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ctx = m.run({
            task = "Fix the bug",
            task_type = "bugfix", -- pre-classified
            phases = {
                { name = "plan", prompt = "Plan: {task}", gate = "OK?" },
                { name = "design", prompt = "Design: {context}", gate = "OK?" },
                { name = "implement", prompt = "Impl: {context}", gate = "OK?" },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        -- design should be skipped (bugfix skips design + architecture)
        expect(#ctx.result.phases).to.equal(2) -- plan + implement
        expect(ctx.result.phases[1].name).to.equal("plan")
        expect(ctx.result.phases[2].name).to.equal("implement")
    end)

    it("skips multiple phases for typo", function()
        mock_alc(function(prompt)
            if prompt:match("Answer") then return "YES" end
            return "output"
        end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ctx = m.run({
            task = "Fix typo",
            task_type = "typo",
            phases = {
                { name = "design", prompt = "D: {task}", gate = "OK?" },
                { name = "architecture", prompt = "A: {task}", gate = "OK?" },
                { name = "implement", prompt = "I: {task}", gate = "OK?" },
                { name = "review", prompt = "R: {task}", gate = "OK?" },
                { name = "test", prompt = "T: {task}", gate = "OK?" },
            },
        })

        -- typo skips design, architecture, review, test → only implement
        expect(#ctx.result.phases).to.equal(1)
        expect(ctx.result.phases[1].name).to.equal("implement")
    end)

    it("runs all phases for feature", function()
        mock_alc(function(prompt)
            if prompt:match("Evaluate") then return "YES, looks good" end
            return "output"
        end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ctx = m.run({
            task = "Add feature",
            task_type = "feature",
            phases = {
                { name = "plan", prompt = "P: {task}", gate = "OK?" },
                { name = "implement", prompt = "I: {task}", gate = "OK?" },
            },
        })

        expect(#ctx.result.phases).to.equal(2)
    end)
end)

-- ================================================================
describe("orch_gatephase: auto-classification", function()
    lust.after(reset)

    it("classifies task type via LLM when not provided", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "bugfix" end -- classification call
            if prompt:match("Evaluate") then return "YES, looks good" end
            return "output"
        end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ctx = m.run({
            task = "Fix the null pointer",
            phases = {
                { name = "plan", prompt = "P: {task}", gate = "OK?" },
                { name = "design", prompt = "D: {task}", gate = "OK?" },
                { name = "implement", prompt = "I: {task}", gate = "OK?" },
            },
        })

        expect(ctx.result.task_type).to.equal("bugfix")
        -- design skipped
        expect(#ctx.result.phases).to.equal(2)
    end)
end)

-- ================================================================
describe("orch_gatephase: additional checks", function()
    lust.after(reset)

    it("fails when additional check fails", function()
        local call_n = 0
        mock_alc(function(prompt)
            call_n = call_n + 1
            -- gate passes but additional check fails
            if prompt:match("Answer YES or NO") then
                return "YES, looks fine"
            end
            if prompt:match("Check the following") then
                return "NO, found unwrap usage"
            end
            return "implementation code"
        end)
        package.loaded["orch_gatephase"] = nil
        local m = require("orch_gatephase")
        local ctx = m.run({
            task = "Implement handler",
            task_type = "feature",
            max_retries = 1,
            on_fail = "error",
            phases = {
                {
                    name = "implement",
                    prompt = "Implement: {task}",
                    gate = "Is this correct?",
                    checks = {
                        { name = "no_unwrap", prompt = "Does this avoid unwrap/expect?" },
                    },
                },
            },
        })

        expect(ctx.result.status).to.equal("failed")
        expect(ctx.result.phases[1].gate_passed).to.equal(false)
    end)
end)
