--- Tests for ranking packages: ab_select, listwise_rank, pairwise_rank, setwise_rank
--- Mocked LLM, no real API calls.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
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
    for _, name in ipairs({ "ab_select", "listwise_rank", "pairwise_rank", "setwise_rank" }) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- ab_select
-- ================================================================
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
        -- Force parse_score to fail too — exercise the strict error path.
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
        -- Cand 1 always scores high, others score low
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

-- ================================================================
-- listwise_rank
-- ================================================================
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
        -- "Ranking 4 candidates" — the bare "4" must NOT become rank 1.
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
        -- With clamping, the final head window must contain 3 items, not 2.
        -- We capture the items present in each LLM call and verify the
        -- last call's prompt references 3 bracketed passages.
        local windows = {}
        mock_alc(function(prompt)
            local items = {}
            for body in prompt:gmatch("%[(%d+)%] (%a)") do
                items[#items + 1] = body
            end
            windows[#windows + 1] = #items
            -- Preserve identity order to keep the trace deterministic.
            return "[1] > [2] > [3]"
        end)
        local m = require("listwise_rank")
        m.run({
            task = "T",
            candidates = { "a", "b", "c", "d", "e", "f", "g", "h" },
            window_size = 3,
            step = 2,
        })
        -- 4 windows expected: [6,7,8] [4,5,6] [2,3,4] [1,2,3]
        expect(#windows).to.equal(4)
        for _, w in ipairs(windows) do
            expect(w).to.equal(3)
        end
    end)

    it("sliding window N=8: head item can win via overlap propagation", function()
        -- Winner candidate 'w' starts at position 8 (tail). It must bubble
        -- to rank 1 via the overlap chain 6-7-8 → 4-5-6 → 2-3-4 → 1-2-3.
        mock_alc(function(prompt)
            -- If prompt contains 'w', put it first.
            local order = {}
            local seen_w = false
            for idx, body in prompt:gmatch("%[(%d+)%] (%a)") do
                if body == "w" then seen_w = true end
                order[#order + 1] = { idx = idx, body = body }
            end
            if seen_w then
                local parts = { "[" }
                -- Winner first
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
        expect(ctx.result.ranked[1].index).to.equal(8)  -- 'w' reached rank 1
        expect(ctx.result.best).to.equal("w")
    end)

    it("sliding window N=8 w=3 s=2: head-placed winner survives to rank 1", function()
        -- Winner at position 3. Without head-window clamping, item 3 might
        -- never share a window with item 1 — in old code the final window
        -- is [1,2] only. With the fix, the final window [1,2,3] guarantees
        -- head-side items are compared against the previous segment's best.
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
        -- N=4, window=3, step=2.
        -- Pass 1: tail window indices [2,3,4] = candidates {b,c,d}.
        --         LLM returns [3] > [1] > [2]  → order: d, b, c
        -- Pass 2: head window indices [1,2,3] (now {a, d, b}).
        --         LLM returns [2] > [1] > [3]  → order: d, a, b
        -- Final global order: [d, a, b, c]  (index sequence: 4, 1, 2, 3)
        --
        -- NOTE: this also asserts the window-size invariant — without
        -- head clamping, pass 2 would shrink to a 2-item window [a, d]
        -- and the test's "Pass 2 cands = {a, d, b}" comment would be a lie.
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
        -- Window-size invariant: both passes use the full window_size=3
        expect(#window_sizes).to.equal(2)
        expect(window_sizes[1]).to.equal(3)
        expect(window_sizes[2]).to.equal(3)
        -- Exact content of each window
        expect(window_cands[1]).to.equal("b,c,d")
        expect(window_cands[2]).to.equal("a,d,b")
        -- Final order
        expect(ctx.result.ranked[1].index).to.equal(4)  -- d
        expect(ctx.result.ranked[2].index).to.equal(1)  -- a
        expect(ctx.result.ranked[3].index).to.equal(2)  -- b
        expect(ctx.result.ranked[4].index).to.equal(3)  -- c
    end)
end)

-- ================================================================
-- pairwise_rank
-- ================================================================
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

    it("allpair: N=3 → 6 LLM calls", function()
        local log = mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "allpair" })
        -- C(3,2) = 3 pairs, x2 directions = 6
        expect(#log).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(6)
    end)

    it("allpair: 'a' always wins → ranked first", function()
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
        -- Sorting with binary insertion uses fewer than allpair's 20 calls
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
        -- A wins both directions → cand 1 ranked first
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
        expect(ctx_s.result.ranked[1].score).to.equal(3)  -- n - 1 + 1
    end)

    it("position-bias splits are counted (Verdict A returned regardless of order)", function()
        -- Both directions return "A" → split detected on every pair
        mock_alc(function() return "Verdict: A" end)
        local m = require("pairwise_rank")
        local ctx = m.run({ task = "T", candidates = { "a", "b", "c" }, method = "allpair" })
        -- C(3,2) = 3 pairs, all are splits
        expect(ctx.result.position_bias_splits).to.equal(3)
    end)
end)

-- ================================================================
-- setwise_rank
-- ================================================================
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
        -- Always pick the slot containing 'best'
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

    it("top_k=2 → 2 ranked entries", function()
        mock_alc(function(prompt)
            -- Always pick first in group
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
        -- 6 cands, set_size 2: round1=3 calls, round2=2... should be > 3
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
