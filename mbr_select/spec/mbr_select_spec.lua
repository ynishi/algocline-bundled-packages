--- Tests for mbr_select.
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
    package.loaded["mbr_select"] = nil
end

describe("mbr_select", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("mbr_select")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("mbr_select")
        expect(m.meta.category).to.equal("selection")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("N=3: 3 gen + 3 pairwise = 6 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 3 then return "candidate " .. n end
            -- Pairwise similarity scores
            return "7"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "Test", n = 3 })
        -- 3 gen + C(3,2)=3 pairwise = 6
        expect(#log).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(6)
        expect(#ctx.result.candidates).to.equal(3)
    end)

    it("N=4: 4 gen + 6 pairwise = 10 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 4 then return "candidate " .. n end
            return "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "Test", n = 4 })
        -- 4 gen + C(4,2)=6 pairwise = 10
        expect(#log).to.equal(10)
    end)

    it("similarity matrix is symmetric", function()
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "c" .. n end
            return "8"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        local sim = ctx.result.similarity_matrix
        for i = 1, 3 do
            for j = 1, 3 do
                expect(sim[i][j]).to.equal(sim[j][i])
            end
            -- Self-similarity = 1.0
            expect(sim[i][i]).to.equal(1.0)
        end
    end)

    it("selects the candidate with highest MBR score", function()
        local pair_idx = 0
        local pair_scores = {
            -- For N=3: pairs are (1,2), (1,3), (2,3)
            "9",  -- 1-2: very similar
            "9",  -- 1-3: very similar
            "2",  -- 2-3: very different
        }
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "candidate " .. n end
            pair_idx = pair_idx + 1
            return pair_scores[pair_idx] or "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        -- Candidate 1 has highest agreement: sim(1,2)=0.9, sim(1,3)=0.9
        -- MBR(1) = (1.0 + 0.9 + 0.9) / 3 = 0.933
        -- MBR(2) = (0.9 + 1.0 + 0.2) / 3 = 0.7
        -- MBR(3) = (0.9 + 0.2 + 1.0) / 3 = 0.7
        expect(ctx.result.best_index).to.equal(1)
    end)

    it("ranking is sorted descending by MBR score", function()
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "c" end
            return "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        local ranking = ctx.result.ranking
        expect(#ranking).to.equal(3)
        for i = 1, #ranking - 1 do
            expect(ranking[i].mbr_score >= ranking[i + 1].mbr_score).to.equal(true)
        end
    end)
end)
