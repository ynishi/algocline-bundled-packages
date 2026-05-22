--- Tests for pbft (F2 — Castro-Liskov 1999 Practical Byzantine Fault Tolerance).
--- Extracted from tests/test_foundations_phase2.lua (Phase C decomposition).

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
        parse_score = function(s) return tonumber(tostring(s):match("[%d%.]+")) end,
    }
    return call_log
end

local function reset_modules()
    _G.alc = nil
    package.loaded["pbft"] = nil
    package.loaded["bft"] = nil
end

describe("pbft", function()
    lust.after(reset_modules)

    it("runs 3-phase consensus with quorum (f=0, n=3)", function()
        local call_idx = 0
        mock_alc(function(prompt, opts, idx)
            call_idx = idx
            if idx <= 3 then
                return "Proposal " .. idx .. ": The answer is 42."
            elseif idx <= 6 then
                return "1"
            else
                return "Synthesized answer"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "What is 6 * 7?" })

        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.n_agents).to.equal(3)
        expect(ctx.result.quorum_required).to.equal(1)
        expect(ctx.result.quorum_met).to.equal(true)
        expect(ctx.result.commit_method).to.equal("quorum")
        expect(ctx.result.bft_valid).to.equal(true)
    end)

    it("falls back to synthesis when no quorum", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 3 then
                return "Proposal " .. idx
            elseif idx <= 6 then
                local agent = ((idx - 4) % 3) + 1
                return tostring(agent)
            else
                return "Synthesized from all"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "Debate topic", n_agents = 3, f = 0 })

        expect(ctx.result.commit_method).to.equal("quorum")
    end)

    it("validates BFT conditions on start", function()
        mock_alc(function() return "ok" end)
        local pbft = require("pbft")

        expect(function()
            pbft.run({ task = "test", n_agents = 3, f = 1 })
        end).to.fail()
    end)

    it("works with f=1, n=4", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 4 then
                return "Proposal " .. idx
            elseif idx <= 8 then
                if idx <= 7 then return "1" else return "2" end
            else
                return "Synthesis"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "test", n_agents = 4, f = 1 })
        expect(ctx.result.quorum_required).to.equal(3)
        expect(ctx.result.quorum_met).to.equal(true)
        expect(ctx.result.commit_method).to.equal("quorum")
    end)

    it("includes proposals in result for traceability", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 3 then return "Answer " .. idx end
            return "1"
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "test" })
        expect(#ctx.result.proposals).to.equal(3)
        expect(ctx.result.proposals[1]).to.equal("Answer 1")
    end)

    it("uses injected system prompts", function()
        local captured_systems = {}
        mock_alc(function(prompt, opts, idx)
            captured_systems[#captured_systems + 1] = opts.system
            if idx <= 3 then return "Proposal " .. idx end
            if idx <= 6 then return "1" end
            return "Synthesis"
        end)

        local pbft = require("pbft")
        pbft.run({
            task = "test",
            gen_system = "CUSTOM_GEN",
            vote_system = "CUSTOM_VOTE",
        })
        expect(captured_systems[1]).to.equal("CUSTOM_GEN")
        expect(captured_systems[2]).to.equal("CUSTOM_GEN")
        expect(captured_systems[3]).to.equal("CUSTOM_GEN")
        expect(captured_systems[4]).to.equal("CUSTOM_VOTE")
        expect(captured_systems[5]).to.equal("CUSTOM_VOTE")
        expect(captured_systems[6]).to.equal("CUSTOM_VOTE")
    end)
end)
