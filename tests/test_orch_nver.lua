--- Tests for orch_nver package

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
            local reason = s:match('"reasoning"%s*:%s*"([^"]*)"')
            if score then
                return { score = tonumber(score), reasoning = reason }
            end
            return nil
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["orch_nver"] = nil
end

-- ================================================================
describe("orch_nver: meta", function()
    lust.after(reset)

    it("has correct meta", function()
        local m = require("orch_nver")
        expect(m.meta.name).to.equal("orch_nver")
        expect(m.meta.category).to.equal("orchestration")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)
end)

-- ================================================================
describe("orch_nver: score mode (default)", function()
    lust.after(reset)

    it("generates N variants and selects highest score", function()
        local variant_count = 0
        local log = mock_alc(function(prompt)
            if prompt:match("evaluate") or prompt:match("Score") then
                -- Score: variant 2 gets highest
                if prompt:match("variant_2_output") then
                    return '{"score": 9, "reasoning": "excellent"}'
                end
                return '{"score": 6, "reasoning": "ok"}'
            end
            variant_count = variant_count + 1
            return "variant_" .. variant_count .. "_output"
        end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        local ctx = m.run({ task = "Solve problem", n = 3 })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.method).to.equal("score")
        expect(ctx.result.best_score).to.equal(9)
        expect(ctx.result.selected).to.equal("variant_2_output")
        expect(#ctx.result.rankings).to.equal(3)
        -- 3 generation + 3 evaluation = 6
        expect(ctx.result.total_llm_calls).to.equal(6)
    end)
end)

-- ================================================================
describe("orch_nver: vote mode", function()
    lust.after(reset)

    it("selects by majority vote", function()
        local log = mock_alc(function(prompt)
            if prompt:match("majority consensus") then
                return "2" -- pick variant 2
            end
            return "variant output"
        end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        local ctx = m.run({ task = "What is X?", n = 3, selection = "vote" })

        expect(ctx.result.status).to.equal("completed")
        expect(ctx.result.method).to.equal("vote")
        -- 3 generation + 1 vote = 4
        expect(ctx.result.total_llm_calls).to.equal(4)
    end)
end)

-- ================================================================
describe("orch_nver: multi-phase variants", function()
    lust.after(reset)

    it("each variant runs through phase pipeline", function()
        local log = mock_alc(function(prompt)
            if prompt:match("evaluate") or prompt:match("Score") then
                return '{"score": 7, "reasoning": "good"}'
            end
            return "phase_output"
        end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        local ctx = m.run({
            task = "Build it",
            n = 2,
            phases = {
                { name = "plan", prompt = "Plan variant {variant}: {task}" },
                { name = "implement", prompt = "Implement: {prev_output}" },
            },
        })

        expect(ctx.result.status).to.equal("completed")
        -- 2 variants x 2 phases + 2 evaluations = 6
        expect(ctx.result.total_llm_calls).to.equal(6)
        expect(#ctx.result.rankings).to.equal(2)
    end)
end)

-- ================================================================
describe("orch_nver: score parse fallback", function()
    lust.after(reset)

    it("defaults to score 5 on parse failure", function()
        mock_alc(function(prompt)
            if prompt:match("evaluate") or prompt:match("Score") then
                return "I cannot evaluate this properly"
            end
            return "output"
        end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        local ctx = m.run({ task = "Do thing", n = 2 })

        expect(ctx.result.best_score).to.equal(5) -- fallback
    end)
end)

-- ================================================================
describe("orch_nver: template expansion with % characters", function()
    lust.after(reset)

    it("handles % in task and prev_output without error", function()
        local prompts = {}
        mock_alc(function(prompt)
            prompts[#prompts + 1] = prompt
            if prompt:match("evaluate") or prompt:match("Score") then
                return '{"score": 7, "reasoning": "good"}'
            end
            return "output with 100% success %d"
        end)
        package.loaded["orch_nver"] = nil
        local m = require("orch_nver")
        m.run({
            task = "task with 50% done",
            n = 1,
            phases = {
                { name = "p1", prompt = "Do: {task}" },
                { name = "p2", prompt = "Prev: {prev_output}" },
            },
        })

        expect(prompts[1]).to.equal("Do: task with 50% done")
        expect(prompts[2]).to.equal("Prev: output with 100% success %d")
    end)
end)
