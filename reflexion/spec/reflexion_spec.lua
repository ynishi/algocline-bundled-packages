--- Tests for reflexion.
--- Extracted from tests/test_tier1_2.lua (Phase C decomposition).

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for _, item in ipairs(list) do
                results[#results + 1] = fn(item)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("%d+")) or 5
        end,
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
        stats = { record = function() end },
    }
    _G.alc = a
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["reflexion"] = nil
end

describe("reflexion", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("reflexion")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("reflexion")
        expect(m.meta.category).to.equal("refinement")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("passes on first trial = 2 calls, no reflection", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "correct answer" end
            -- Evaluation: passes (score 9 >= threshold 8)
            return '{"score": 9, "passed": true, "feedback": "excellent"}'
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Easy question" })
        expect(#log).to.equal(2) -- attempt + evaluate
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.total_trials).to.equal(1)
        expect(ctx.result.best_trial).to.equal(1)
        expect(#ctx.result.reflections).to.equal(0)
    end)

    it("fails trial 1, passes trial 2 = 5 calls with reflection", function()
        local trial = 0
        local log = mock_alc(function(prompt, _, n)
            -- Count trials by attempt generation
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                if trial == 1 then return "wrong approach" end
                return "correct approach using lesson"
            end
            -- Evaluation
            if prompt:match('"score"') or prompt:match("Evaluate") then
                if trial == 1 then
                    return '{"score": 4, "passed": false, "feedback": "wrong method"}'
                end
                return '{"score": 9, "passed": true, "feedback": "correct"}'
            end
            -- Reflection (after trial 1 failure)
            if prompt:match("Reflect on this failure") then
                return "Lesson: should use method B instead of A"
            end
            return "fallback"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Hard question" })
        -- Trial 1: attempt(1) + eval(2) + reflect(3)
        -- Trial 2: attempt(4) + eval(5)
        expect(#log).to.equal(5)
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.total_trials).to.equal(2)
        expect(ctx.result.best_trial).to.equal(2)
        expect(#ctx.result.reflections).to.equal(1)
    end)

    it("all trials fail = returns best, passed=false", function()
        local trial = 0
        local log = mock_alc(function(prompt)
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                return "attempt " .. trial
            end
            if prompt:match("Evaluate") or prompt:match('"score"') then
                -- Increasing scores but never passing threshold 8
                local scores = { 3, 5, 6 }
                local s = scores[trial] or 5
                return string.format('{"score": %d, "passed": false, "feedback": "still wrong"}', s)
            end
            if prompt:match("Reflect") then
                return "lesson from trial " .. trial
            end
            return "fallback"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Very hard", max_trials = 3 })
        expect(ctx.result.passed).to.equal(false)
        expect(ctx.result.total_trials).to.equal(3)
        -- Best = trial 3 (score 6)
        expect(ctx.result.best_score).to.equal(6)
        expect(ctx.result.best_trial).to.equal(3)
        -- 2 reflections (after trial 1 and 2, not after final trial 3)
        expect(#ctx.result.reflections).to.equal(2)
    end)

    it("episodic memory is passed to subsequent attempts", function()
        local attempt_prompts = {}
        local trial = 0
        mock_alc(function(prompt)
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                attempt_prompts[trial] = prompt
                if trial >= 3 then return "finally correct" end
                return "attempt " .. trial
            end
            if prompt:match("Evaluate") then
                if trial >= 3 then
                    return '{"score": 9, "passed": true, "feedback": "good"}'
                end
                return '{"score": 3, "passed": false, "feedback": "bad"}'
            end
            if prompt:match("Reflect") then
                return "lesson_" .. trial
            end
            return "x"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        m.run({ task = "Q", max_trials = 3 })

        -- Trial 1: no lessons in prompt
        expect(attempt_prompts[1]:match("Lessons")).to.equal(nil)
        -- Trial 2: has lesson_1
        expect(attempt_prompts[2]:match("lesson_1")).to_not.equal(nil)
        -- Trial 3: has both lesson_1 and lesson_2
        expect(attempt_prompts[3]:match("lesson_1")).to_not.equal(nil)
        expect(attempt_prompts[3]:match("lesson_2")).to_not.equal(nil)
    end)

    it("custom success_threshold is respected", function()
        mock_alc(function(prompt, _, n)
            if n == 1 then return "answer" end
            -- Score 6: passes threshold 5, would fail default 8
            return '{"score": 6, "passed": true, "feedback": "ok"}'
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Q", success_threshold = 5 })
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.best_score).to.equal(6)
    end)

    it("fallback parse_score when JSON decode fails", function()
        mock_alc(function(prompt, _, n)
            if n == 1 then return "answer" end
            -- Return non-JSON, fallback to parse_score
            return "Score: 9 out of 10. Very good work."
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Q" })
        -- parse_score extracts 9, which >= threshold 8
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.best_score).to.equal(9)
    end)
end)
