--- Tests for orch_escalate package

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
            local score = s:match('"score"%s*:%s*(%d+)')
            local passed = s:match('"passed"%s*:%s*(true)')
            local fb = s:match('"feedback"%s*:%s*"([^"]*)"')
            if score then
                return {
                    score = tonumber(score),
                    passed = passed ~= nil,
                    feedback = fb or "",
                }
            end
            return nil
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["orch_escalate"] = nil
end

-- ================================================================
describe("orch_escalate: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        local m = require("orch_escalate")
        expect(m.meta.name).to.equal("orch_escalate")
        expect(m.meta.category).to.equal("orchestration")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)
end)

-- ================================================================
describe("orch_escalate: quick pass (early return)", function()
    lust.after(reset)

    it("returns at level 1 when score meets threshold", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Threshold") then
                return '{"score": 9, "passed": true, "feedback": ""}'
            end
            return "quick answer"
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ctx = m.run({
            task = "Simple task",
            levels = {
                { name = "quick", prompt_template = "Solve: {task}", threshold = 8, max_tokens = 1000 },
                { name = "heavy", prompt_template = "Heavy: {task}", threshold = 6, max_tokens = 3000 },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.selected_level).to.equal("quick")
        expect(ctx.result.escalation_depth).to.equal(1)
        expect(ctx.result.score).to.equal(9)
        -- 1 generation + 1 evaluation = 2
        expect(ctx.result.total_llm_calls).to.equal(2)
    end)
end)

-- ================================================================
describe("orch_escalate: escalation", function()
    lust.after(reset)

    it("escalates to level 2 when level 1 fails", function()
        local call_n = 0
        local log = mock_alc(function(prompt)
            call_n = call_n + 1
            if prompt:match("Threshold") then
                -- Level 1 fails, level 2 passes
                if call_n <= 2 then
                    return '{"score": 5, "passed": false, "feedback": "incomplete"}'
                end
                return '{"score": 8, "passed": true, "feedback": ""}'
            end
            return "output " .. call_n
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ctx = m.run({
            task = "Medium task",
            levels = {
                { name = "quick", prompt_template = "Quick: {task}", threshold = 8, max_tokens = 1000 },
                { name = "structured", prompt_template = "Structured: {task}\nPrev: {prev_output}\nFB: {feedback}", threshold = 7, max_tokens = 2000 },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.selected_level).to.equal("structured")
        expect(ctx.result.escalation_depth).to.equal(2)
        expect(#ctx.result.levels).to.equal(2)
        expect(ctx.result.levels[1].passed).to.equal(false)
        expect(ctx.result.levels[2].passed).to.equal(true)
    end)

    it("passes prev_output and feedback to next level", function()
        local prompts = {}
        mock_alc(function(prompt)
            prompts[#prompts + 1] = prompt
            if prompt:match("Threshold") then
                if #prompts <= 2 then
                    return '{"score": 3, "passed": false, "feedback": "needs more detail"}'
                end
                return '{"score": 8, "passed": true, "feedback": ""}'
            end
            return "level output"
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        m.run({
            task = "Do it",
            levels = {
                { name = "l1", prompt_template = "L1: {task}", threshold = 8, max_tokens = 1000 },
                { name = "l2", prompt_template = "L2: {task} prev={prev_output} fb={feedback}", threshold = 6, max_tokens = 2000 },
            },
        })

        -- Level 2 prompt should contain prev_output and feedback
        local l2_prompt = prompts[3] -- l1 gen, l1 eval, l2 gen
        expect(l2_prompt:match("prev=level output")).to_not.equal(nil)
        expect(l2_prompt:match("fb=needs more detail")).to_not.equal(nil)
    end)
end)

-- ================================================================
describe("orch_escalate: multi_phase level", function()
    lust.after(reset)

    it("executes multi-phase level correctly", function()
        local eval_count = 0
        mock_alc(function(prompt)
            if prompt:match("Threshold") then
                eval_count = eval_count + 1
                -- level 1 eval fails, level 2 eval passes
                if eval_count == 1 then
                    return '{"score": 4, "passed": false, "feedback": "bad"}'
                end
                return '{"score": 8, "passed": true, "feedback": ""}'
            end
            return "phase output"
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ctx = m.run({
            task = "Complex task",
            levels = {
                { name = "quick", prompt_template = "Quick: {task}", threshold = 8, max_tokens = 1000 },
                {
                    name = "thorough",
                    multi_phase = true,
                    phases = {
                        { prompt = "Plan: {task}", system = "Planner" },
                        { prompt = "Impl: {prev_phase_output}", system = "Developer" },
                    },
                    max_tokens = 3000,
                    threshold = 6,
                },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.selected_level).to.equal("thorough")
        -- l1: 1 gen + 1 eval, l2: 2 phases + 1 eval = 5
        expect(ctx.result.total_llm_calls).to.equal(5)
    end)
end)

-- ================================================================
describe("orch_escalate: all levels fail", function()
    lust.after(reset)

    it("returns best effort on partial mode", function()
        mock_alc(function(prompt)
            if prompt:match("Threshold") then
                return '{"score": 4, "passed": false, "feedback": "not good enough"}'
            end
            return "mediocre output"
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ctx = m.run({
            task = "Hard task",
            on_fail = "partial",
            levels = {
                { name = "l1", prompt_template = "L1: {task}", threshold = 8, max_tokens = 1000 },
                { name = "l2", prompt_template = "L2: {task}", threshold = 7, max_tokens = 2000 },
            },
        })

        expect(ctx.result.status).to.equal("partial")
        expect(ctx.result.score).to.equal(4)
        expect(ctx.result.escalation_depth).to.equal(2)
    end)

    it("returns failed on error mode", function()
        mock_alc(function(prompt)
            if prompt:match("Threshold") then
                return '{"score": 3, "passed": false, "feedback": "bad"}'
            end
            return "bad output"
        end)
        package.loaded["orch_escalate"] = nil
        local m = require("orch_escalate")
        local ctx = m.run({
            task = "Hard task",
            on_fail = "error",
            levels = {
                { name = "l1", prompt_template = "Solve: {task}", threshold = 9, max_tokens = 1000 },
            },
        })

        expect(ctx.result.status).to.equal("failed")
    end)
end)
