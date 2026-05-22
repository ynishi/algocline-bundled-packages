--- Tests for listwise_rank (LLM-emitted bracketed ranking + sliding-window aggregation).
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
    package.loaded["listwise_rank"] = nil
end

describe("listwise_rank", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("listwise_rank")
        expect(m.meta.name).to.equal("listwise_rank")
        expect(m.meta.category).to.equal("selection")
    end)

    it("errors without candidates", function()
        mock_alc(function() return "mock" end)
        local m = require("listwise_rank")
        local ok = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
    end)

    it("single window: 1 LLM call ranks all", function()
        local log = mock_alc(function() return "[3] > [1] > [4] > [2]" end)
        local m = require("listwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c", "d" } })
        expect(#log).to.equal(1)
        expect(ctx.result.best_index).to.equal(3)
        expect(ctx.result.ranked[1].index).to.equal(3)
        expect(ctx.result.ranked[2].index).to.equal(1)
    end)

    it("top_k splits kept/killed", function()
        mock_alc(function() return "[2] > [1] > [3]" end)
        local m = require("listwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" }, top_k = 1 })
        expect(#ctx.result.top_k).to.equal(1)
        expect(#ctx.result.killed).to.equal(2)
        expect(ctx.result.top_k[1].index).to.equal(2)
    end)

    it("missing indices filled in original order", function()
        mock_alc(function() return "[2]" end)
        local m = require("listwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" } })
        expect(ctx.result.ranked[1].index).to.equal(2)
        expect(ctx.result.ranked[2].index).to.equal(1)
        expect(ctx.result.ranked[3].index).to.equal(3)
    end)

    it("prose with stray numbers does not pollute bracketed ranking", function()
        mock_alc(function() return "Ranking 4 candidates: [3] > [1] > [4] > [2]" end)
        local m = require("listwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c", "d" } })
        expect(ctx.result.ranked[1].index).to.equal(3)
        expect(ctx.result.ranked[2].index).to.equal(1)
        expect(ctx.result.ranked[3].index).to.equal(4)
        expect(ctx.result.ranked[4].index).to.equal(2)
    end)

    it("bare-number fallback only when no brackets present", function()
        mock_alc(function() return "Best to worst: 2, 3, 1" end)
        local m = require("listwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" } })
        expect(ctx.result.ranked[1].index).to.equal(2)
        expect(ctx.result.ranked[2].index).to.equal(3)
        expect(ctx.result.ranked[3].index).to.equal(1)
    end)

    it("sliding window for n > window_size", function()
        local log = mock_alc(function() return "[1] > [2] > [3]" end)
        local m = require("listwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "c", "d", "e" },
            window_size = 3,
            step = 2,
        })
        expect(#log >= 2).to.equal(true)
    end)

    it("sliding window N=8 w=3 s=2: head window is full 3 items (not shrunk)", function()
        local windows = {}
        mock_alc(function(prompt)
            local items = {}
            for body in prompt:gmatch("%[(%d+)%] (%a)") do
                items[#items + 1] = body
            end
            windows[#windows + 1] = #items
            return "[1] > [2] > [3]"
        end)
        local m = require("listwise_rank")
        m.run({
            task = "T",
            candidates = { "a", "b", "c", "d", "e", "f", "g", "h" },
            window_size = 3,
            step = 2,
        })
        expect(#windows).to.equal(4)
        for _, w in ipairs(windows) do
            expect(w).to.equal(3)
        end
    end)

    it("sliding window N=8: head item can win via overlap propagation", function()
        mock_alc(function(prompt)
            local order = {}
            local seen_w = false
            for idx, body in prompt:gmatch("%[(%d+)%] (%a)") do
                if body == "w" then seen_w = true end
                order[#order + 1] = { idx = idx, body = body }
            end
            if seen_w then
                local parts = { "[" }
                for _, it in ipairs(order) do
                    if it.body == "w" then
                        parts[1] = "[" .. it.idx .. "]"
                    end
                end
                local rest = {}
                for _, it in ipairs(order) do
                    if it.body ~= "w" then
                        rest[#rest + 1] = "[" .. it.idx .. "]"
                    end
                end
                return parts[1] .. " > " .. table.concat(rest, " > ")
            end
            return "[1] > [2] > [3]"
        end)
        local m = require("listwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "c", "d", "e", "f", "g", "w" },
            window_size = 3,
            step = 2,
        })
        expect(ctx.result.ranked[1].index).to.equal(8)
        expect(ctx.result.best).to.equal("w")
    end)

    it("sliding window N=8 w=3 s=2: head-placed winner survives to rank 1", function()
        mock_alc(function(prompt)
            local order = {}
            local seen_w = false
            for idx, body in prompt:gmatch("%[(%d+)%] (%a)") do
                if body == "w" then seen_w = true end
                order[#order + 1] = { idx = idx, body = body }
            end
            if seen_w then
                local winner_idx
                local rest = {}
                for _, it in ipairs(order) do
                    if it.body == "w" then
                        winner_idx = it.idx
                    else
                        rest[#rest + 1] = "[" .. it.idx .. "]"
                    end
                end
                return "[" .. winner_idx .. "] > " .. table.concat(rest, " > ")
            end
            return "[1] > [2] > [3]"
        end)
        local m = require("listwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "w", "d", "e", "f", "g", "h" },
            window_size = 3,
            step = 2,
        })
        expect(ctx.result.ranked[1].index).to.equal(3)
        expect(ctx.result.best).to.equal("w")
    end)

    it("sliding window: window-local ranking is merged into global order", function()
        local call = 0
        local window_sizes = {}
        local window_cands = {}
        mock_alc(function(prompt)
            call = call + 1
            local cands = {}
            for body in prompt:gmatch("%[%d+%] (%a)") do
                cands[#cands + 1] = body
            end
            window_sizes[call] = #cands
            window_cands[call] = table.concat(cands, ",")
            if call == 1 then return "[3] > [1] > [2]" end
            return "[2] > [1] > [3]"
        end)
        local m = require("listwise_rank")
        local ctx = m.run({
            task = "T",
            candidates = { "a", "b", "c", "d" },
            window_size = 3,
            step = 2,
        })
        expect(#window_sizes).to.equal(2)
        expect(window_sizes[1]).to.equal(3)
        expect(window_sizes[2]).to.equal(3)
        expect(window_cands[1]).to.equal("b,c,d")
        expect(window_cands[2]).to.equal("a,d,b")
        expect(ctx.result.ranked[1].index).to.equal(4)
        expect(ctx.result.ranked[2].index).to.equal(1)
        expect(ctx.result.ranked[3].index).to.equal(2)
        expect(ctx.result.ranked[4].index).to.equal(3)
    end)
end)
