--- Tests for pairwise_rank (allpair / sorting modes with Copeland or rank_inverse scoring).
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
    package.loaded["pairwise_rank"] = nil
end

describe("pairwise_rank", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("pairwise_rank")
        expect(m.meta.name).to.equal("pairwise_rank")
        expect(m.meta.category).to.equal("selection")
    end)

    it("errors without candidates", function()
        mock_alc(function() return "mock" end)
        local m = require("pairwise_rank")
        local ok = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
    end)

    it("allpair: N=3 -> 6 LLM calls", function()
        local log = mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "allpair" })
        expect(#log).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(6)
    end)

    it("allpair: 'a' always wins -> ranked first", function()
        mock_alc(function(prompt)
            local ai = prompt:find("Candidate A:\na\n")
            local bi = prompt:find("Candidate B:\na\n")
            if ai then return "Verdict: A" end
            if bi then return "Verdict: B" end
            return "Verdict: tie"
        end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "x", "a", "y" }, method = "allpair" })
        expect(ctx.result.best_index).to.equal(2)
    end)

    it("sorting mode: fewer calls than allpair for larger N", function()
        local log = mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        m.run({ task = "T", candidates = { "a", "b", "c", "d", "e" }, method = "sorting" })
        expect(#log < 20).to.equal(true)
    end)

    it("invalid method errors", function()
        mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ok = pcall(m.run, { task = "T", candidates = { "a", "b" }, method = "bogus" })
        expect(ok).to.equal(false)
    end)

    it("lenient parse: prose 'I think A is better' parses as A (not tie)", function()
        mock_alc(function() return "I think A is better here." end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b" }, method = "allpair" })
        expect(ctx.result.best_index).to.equal(1)
    end)

    it("unparseable verdict raises error (no silent tie)", function()
        mock_alc(function() return "hmm not sure" end)
        local m = require("pairwise_rank")
        local ok, err = pcall(m.run, {
            task = "T", candidates = { "a", "b" }, method = "allpair",
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("cannot parse verdict") ~= nil).to.equal(true)
    end)

    it("top_k splits kept/killed", function()
        mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c", "d" }, top_k = 2 })
        expect(#ctx.result.top_k).to.equal(2)
        expect(#ctx.result.killed).to.equal(2)
    end)

    it("ranked entries expose `score` field; semantics differ by mode", function()
        mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx_a = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "allpair" })
        expect(ctx_a.result.score_semantics).to.equal("copeland")
        expect(ctx_a.result.ranked[1].score ~= nil).to.equal(true)
        local ctx_s = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "sorting" })
        expect(ctx_s.result.score_semantics).to.equal("rank_inverse")
        expect(ctx_s.result.ranked[1].score).to.equal(3)
    end)

    it("position-bias splits are counted (Verdict A returned regardless of order)", function()
        mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "allpair" })
        expect(ctx.result.position_bias_splits).to.equal(3)
    end)
end)
