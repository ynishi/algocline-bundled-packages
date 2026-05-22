--- Tests for compute_alloc.
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
    package.loaded["compute_alloc"] = nil
end

describe("compute_alloc", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("compute_alloc")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("compute_alloc")
        expect(m.meta.category).to.equal("orchestration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("EASY classification → single paradigm, 2 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "EASY — straightforward factual question" end
            return "The answer is 42."
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "What is 6*7?" })
        expect(ctx.result.difficulty).to.equal("easy")
        expect(ctx.result.paradigm).to.equal("single")
        expect(#log).to.equal(2) -- classify + direct
        expect(ctx.result.total_llm_calls).to.equal(2)
    end)

    it("MEDIUM classification → parallel paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "MEDIUM — requires multi-step reasoning" end
            return "response " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Explain the CAP theorem" })
        expect(ctx.result.difficulty).to.equal("medium")
        expect(ctx.result.paradigm).to.equal("parallel")
        -- 1 classify + 3 samples + 1 selection = 5
        expect(#log).to.equal(5)
    end)

    it("HARD classification → sequential paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "HARD — complex mathematical proof" end
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "step-by-step solution " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Prove P=NP" })
        expect(ctx.result.difficulty).to.equal("hard")
        expect(ctx.result.paradigm).to.equal("sequential")
    end)

    it("VERY_HARD classification → hybrid paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "VERY_HARD — open research problem" end
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "response " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Solve the Riemann hypothesis" })
        expect(ctx.result.difficulty).to.equal("very_hard")
        expect(ctx.result.paradigm).to.equal("hybrid")
    end)

    it("budget='low' overrides to easy (no classification call)", function()
        local log = mock_alc(function() return "direct answer" end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Simple Q", budget = "low" })
        expect(ctx.result.difficulty).to.equal("easy")
        expect(#log).to.equal(1) -- no classification, just direct
        expect(ctx.result.total_llm_calls).to.equal(1)
    end)

    it("budget='high' overrides to hard (no classification call)", function()
        local log = mock_alc(function(prompt)
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "answer"
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Q", budget = "high" })
        expect(ctx.result.difficulty).to.equal("hard")
        expect(ctx.result.total_llm_calls > 1).to.equal(true)
    end)

    it("sequential stops early when VERIFIED_CORRECT", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "HARD" end
            if n == 2 then return "step by step solution" end
            -- First verification passes immediately
            return "All steps are correct. VERIFIED_CORRECT"
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Math" })
        -- 1 classify + 1 generate + 1 verify = 3 (no revision needed)
        expect(#log).to.equal(3)
    end)
end)
