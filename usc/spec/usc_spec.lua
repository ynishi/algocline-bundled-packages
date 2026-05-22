--- Tests for usc.
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
    package.loaded["usc"] = nil
end

describe("usc", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("usc")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("usc")
        expect(m.meta.category).to.equal("aggregation")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("uses N+1 LLM calls (N samples + 1 selection)", function()
        local log = mock_alc(function(_, _, n)
            if n <= 5 then return "candidate " .. n end
            return "Response 3 is most consistent. The answer is candidate 3."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "What is 2+2?" })
        -- default n=5: 5 sampling + 1 selection = 6
        expect(#log).to.equal(6)
        expect(ctx.result.n_sampled).to.equal(5)
        expect(#ctx.result.candidates).to.equal(5)
    end)

    it("custom n=3 uses 4 LLM calls", function()
        local log = mock_alc(function(_, _, n)
            if n <= 3 then return "answer " .. n end
            return "Response 2 is most consistent."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test", n = 3 })
        expect(#log).to.equal(4)
        expect(ctx.result.n_sampled).to.equal(3)
    end)

    it("extracts selected_index from 'Response N' pattern", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "Response 4 is the most consistent answer."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(4)
    end)

    it("extracts selected_index from '#N' pattern", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "The best answer is #2 because it is most consistent."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(2)
    end)

    it("sets selected_index to nil when no index is extractable", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "The consensus is that the answer is 42."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(nil)
    end)

    it("rejects out-of-range index", function()
        mock_alc(function(_, _, n)
            if n <= 3 then return "candidate" end
            return "Response 99 is the best."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test", n = 3 })
        expect(ctx.result.selected_index).to.equal(nil)
    end)

    it("selection prompt includes all candidates", function()
        local selection_prompt = nil
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "answer_" .. n end
            selection_prompt = prompt
            return "Response 1"
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        m.run({ task = "Q", n = 3 })
        expect(selection_prompt:match("answer_1")).to_not.equal(nil)
        expect(selection_prompt:match("answer_2")).to_not.equal(nil)
        expect(selection_prompt:match("answer_3")).to_not.equal(nil)
        expect(selection_prompt:match("Response 1")).to_not.equal(nil)
        expect(selection_prompt:match("Response 2")).to_not.equal(nil)
        expect(selection_prompt:match("Response 3")).to_not.equal(nil)
    end)
end)
