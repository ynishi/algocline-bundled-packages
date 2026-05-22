--- Tests for dissent (governance — minority-opinion judging + optional revision).
--- Extracted from tests/test_governance.lua (Phase C decomposition).

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
    local stats_log = {}
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
        stats = {
            record = function(key, value)
                stats_log[key] = value
            end,
        },
    }
    _G.alc = a
    return call_log, stats_log
end

local function reset()
    _G.alc = nil
    package.loaded["dissent"] = nil
end

describe("dissent: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        mock_alc(function() return "mock" end)
        local m = require("dissent")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("dissent")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("governance")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.consensus", function()
        mock_alc(function() return "mock" end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.consensus is required")).to_not.equal(nil)
    end)
end)

describe("dissent: consensus held (low merit)", function()
    lust.after(reset)

    it("makes 2 LLM calls when dissent has no merit", function()
        local log, stats = mock_alc(function(_, _, n)
            if n == 1 then
                return "Challenge 1: The consensus ignores edge cases."
            else
                return [[## Challenge Evaluations
1. Edge cases: INVALID — The consensus explicitly addresses edge cases in paragraph 2

## Overall Assessment
MERIT_SCORE: 0.1
REVISION_NEEDED: NO
KEY_ISSUES: ]]
            end
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "Design API",
            consensus = "We should use REST with proper error handling for edge cases",
        })
        expect(#log).to.equal(2)
        expect(ctx.result.consensus_held).to.equal(true)
        expect(ctx.result.merit_score).to.equal(0.1)
        expect(ctx.result.revised_consensus).to.equal(nil)
        expect(ctx.result.output).to.equal("We should use REST with proper error handling for edge cases")
        expect(stats["dissent_revised"]).to.equal(0)
    end)
end)

describe("dissent: consensus revised (high merit)", function()
    lust.after(reset)

    it("makes 3 LLM calls when revision is needed", function()
        local log, stats = mock_alc(function(_, _, n)
            if n == 1 then
                return "Challenge 1: Security not addressed.\nChallenge 2: No rate limiting."
            elseif n == 2 then
                return [[## Challenge Evaluations
1. Security: VALID — No mention of authentication
2. Rate limiting: PARTIAL — Implied but not explicit

## Overall Assessment
MERIT_SCORE: 0.75
REVISION_NEEDED: YES
KEY_ISSUES: missing authentication, rate limiting not explicit]]
            else
                return [[## Revised Consensus
We should use REST with JWT authentication and explicit rate limiting.

## Changes Made
- Added JWT authentication requirement
- Made rate limiting explicit]]
            end
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "Design API",
            consensus = "We should use REST",
        })
        expect(#log).to.equal(3)
        expect(ctx.result.consensus_held).to.equal(false)
        expect(ctx.result.merit_score).to.equal(0.75)
        expect(ctx.result.revised_consensus).to_not.equal(nil)
        expect(ctx.result.output).to.equal(ctx.result.revised_consensus)
        expect(stats["dissent_revised"]).to.equal(1)
    end)
end)

describe("dissent: with perspectives", function()
    lust.after(reset)

    it("includes perspectives in dissent prompt (string format)", function()
        local saw_perspectives = false
        mock_alc(function(prompt, _, n)
            if n == 1 and prompt:match("Perspective 1") and prompt:match("Perspective 2") then
                saw_perspectives = true
            end
            if n == 1 then return "Challenge" end
            return "MERIT_SCORE: 0.0\nREVISION_NEEDED: NO\nKEY_ISSUES: "
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        m.run({
            task = "Question",
            consensus = "Agreed answer",
            perspectives = { "Agent 1 thinks X", "Agent 2 thinks Y" },
        })
        expect(saw_perspectives).to.equal(true)
    end)

    it("includes perspectives in dissent prompt (table format)", function()
        local saw_named = false
        mock_alc(function(prompt, _, n)
            if n == 1 and prompt:match("Expert A") and prompt:match("Expert B") then
                saw_named = true
            end
            if n == 1 then return "Challenge" end
            return "MERIT_SCORE: 0.0\nREVISION_NEEDED: NO\nKEY_ISSUES: "
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        m.run({
            task = "Question",
            consensus = "Agreed answer",
            perspectives = {
                { name = "Expert A", output = "analysis A" },
                { name = "Expert B", output = "analysis B" },
            },
        })
        expect(saw_named).to.equal(true)
    end)
end)

describe("dissent: threshold gating", function()
    lust.after(reset)

    it("does not revise when merit_score < threshold despite REVISION_NEEDED=YES", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "Weak challenge" end
            return "MERIT_SCORE: 0.3\nREVISION_NEEDED: YES\nKEY_ISSUES: minor wording"
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "T",
            consensus = "C",
            merit_threshold = 0.6,
        })
        expect(#log).to.equal(2)
        expect(ctx.result.consensus_held).to.equal(true)
    end)

    it("respects custom threshold", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "Challenge" end
            if n == 2 then return "MERIT_SCORE: 0.3\nREVISION_NEEDED: YES\nKEY_ISSUES: issue" end
            return "Revised"
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "T",
            consensus = "C",
            merit_threshold = 0.2,
        })
        expect(#log).to.equal(3)
        expect(ctx.result.consensus_held).to.equal(false)
    end)
end)
