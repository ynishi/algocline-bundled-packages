--- Tests for gumbel_search.
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
    package.loaded["gumbel_search"] = nil
end

describe("gumbel_search", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("gumbel_search")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("gumbel_search")
        expect(m.meta.category).to.equal("reasoning")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates N candidates then halves until 1 winner", function()
        local gen_count = 0
        local eval_count = 0
        local log = mock_alc(function(prompt, opts, n)
            -- Generation calls have "solver #" in the system prompt
            if opts and opts.system and opts.system:match("solver #") then
                gen_count = gen_count + 1
                return "candidate answer " .. gen_count
            end
            -- Evaluation: return varying scores
            eval_count = eval_count + 1
            return tostring(5 + (eval_count % 5))
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Solve X", initial_candidates = 4 })

        -- 4 candidates generated
        expect(gen_count).to.equal(4)
        -- Sequential halving: round 1 = 4 evals → keep 2, round 2 = 2 evals → keep 1
        expect(eval_count).to.equal(6)
        -- Result structure
        expect(ctx.result.answer).to_not.equal(nil)
        expect(ctx.result.best_index).to_not.equal(nil)
        expect(ctx.result.halving_rounds).to.equal(2) -- log2(4) = 2
        expect(ctx.result.total_evaluations).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(10) -- 4 gen + 6 eval
    end)

    it("with 2 candidates = 1 halving round", function()
        local log = mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "7"
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 2 })
        expect(ctx.result.halving_rounds).to.equal(1)
        expect(ctx.result.total_evaluations).to.equal(2)
        expect(ctx.result.total_llm_calls).to.equal(4) -- 2 gen + 2 eval
    end)

    it("best_score is normalized to [0,1]", function()
        mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "8" -- score 8/10 = 0.8
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 2 })
        expect(ctx.result.best_score).to.equal(0.8)
    end)

    it("candidate_summary includes all candidates with scores", function()
        mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "6"
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 4 })
        expect(#ctx.result.candidates).to.equal(4)
        for _, c in ipairs(ctx.result.candidates) do
            expect(c.index).to_not.equal(nil)
            expect(c.mean_score).to_not.equal(nil)
            expect(c.n_evals).to_not.equal(nil)
        end
    end)
end)
