--- Tests for ab_select (Thompson-style A/B selection with budget + posterior sampling).
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
    package.loaded["ab_select"] = nil
end

describe("ab_select", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("ab_select")
        expect(m.meta.name).to.equal("ab_select")
        expect(m.meta.category).to.equal("selection")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        local m = require("ab_select")
        local ok = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)

    it("generates n candidates and evaluates within budget", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 4 then return "candidate answer " .. n end
            return "FINAL: 7"
        end)
        local m = require("ab_select")
        local ctx = m.run({ task = "Solve X", n = 4, budget = 6, seed = 42 })
        expect(ctx.result.best).to_not.equal(nil)
        expect(ctx.result.best_index >= 1 and ctx.result.best_index <= 4).to.equal(true)
        expect(ctx.result.budget_used <= 6).to.equal(true)
        expect(#ctx.result.candidates).to.equal(4)
    end)

    it("unparseable score raises error (no silent zero)", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "cand " .. n end
            return "no number here at all"
        end)
        _G.alc.parse_score = function() return nil end
        local m = require("ab_select")
        local ok, err = pcall(m.run, { task = "T", n = 2, budget = 2, seed = 1 })
        expect(ok).to.equal(false)
        expect(tostring(err):find("cannot parse score") ~= nil).to.equal(true)
    end)

    it("rejects non-integer seed", function()
        mock_alc(function() return "FINAL: 5" end)
        local m = require("ab_select")
        local ok1, e1 = pcall(m.run, { task = "T", n = 2, budget = 2, seed = 1.5 })
        expect(ok1).to.equal(false)
        expect(tostring(e1):find("seed") ~= nil).to.equal(true)
    end)

    it("rejects negative seed", function()
        mock_alc(function() return "FINAL: 5" end)
        local m = require("ab_select")
        local ok, err = pcall(m.run, { task = "T", n = 2, budget = 2, seed = -3 })
        expect(ok).to.equal(false)
        expect(tostring(err):find("seed") ~= nil).to.equal(true)
    end)

    it("rejects string seed", function()
        mock_alc(function() return "FINAL: 5" end)
        local m = require("ab_select")
        local ok, err = pcall(m.run, { task = "T", n = 2, budget = 2, seed = "abc" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("seed") ~= nil).to.equal(true)
    end)

    it("accepts seed=0 (documented default-equivalent)", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "cand " .. n end
            return "FINAL: 5"
        end)
        local m = require("ab_select")
        local ok = pcall(m.run, { task = "T", n = 2, budget = 2, seed = 0 })
        expect(ok).to.equal(true)
    end)

    it("higher posterior wins", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 3 then return "cand " .. n end
            if prompt:match("cand 1") then return "FINAL: 10" end
            return "FINAL: 1"
        end)
        local m = require("ab_select")
        local ctx = m.run({ task = "T", n = 3, budget = 9, seed = 1 })
        expect(ctx.result.best_index).to.equal(1)
    end)
end)
