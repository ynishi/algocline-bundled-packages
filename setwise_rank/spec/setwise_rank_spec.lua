--- Tests for setwise_rank (group-pick ranking with set_size + multiple rounds).
--- Extracted from tests/test_ranking_packages.lua (Phase C decomposition).

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
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("[%d%.]+")) or 5
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["setwise_rank"] = nil
end

describe("setwise_rank", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("setwise_rank")
        expect(m.meta.name).to.equal("setwise_rank")
        expect(m.meta.category).to.equal("selection")
    end)

    it("errors without candidates", function()
        mock_alc(function() return "mock" end)
        local m = require("setwise_rank")
        local ok = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
    end)

    it("picks the candidate the LLM names as best", function()
        mock_alc(function(prompt)
            for line in prompt:gmatch("(%[%d+%] [^\n]*)") do
                if line:find("best") then
                    local idx = line:match("%[(%d+)%]")
                    return idx
                end
            end
            return "1"
        end)
        local m = require("setwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "best", "d" },
            top_k = 1,
            set_size = 4,
        })
        expect(ctx.result.best_index).to.equal(3)
    end)

    it("top_k=2 -> 2 ranked entries", function()
        mock_alc(function(prompt)
            return "1"
        end)
        local m = require("setwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "c", "d" },
            top_k = 2,
            set_size = 4,
        })
        expect(#ctx.result.top_k).to.equal(2)
        expect(#ctx.result.killed).to.equal(2)
    end)

    it("set_size smaller than N triggers multiple rounds", function()
        local log = mock_alc(function() return "1" end)
        local m = require("setwise_rank")
        m.run({
            task = "T",
            candidates = { "a", "b", "c", "d", "e", "f" },
            top_k = 1,
            set_size = 2,
        })
        expect(#log > 3).to.equal(true)
    end)

    it("unparseable pick raises error (no silent slot-1 fallback)", function()
        mock_alc(function() return "garbage" end)
        local m = require("setwise_rank")
        local ok, err = pcall(m.run, {
            task = "T",
            candidates = { "a", "b" },
            top_k = 1,
            set_size = 2,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("cannot parse pick") ~= nil).to.equal(true)
    end)
end)
