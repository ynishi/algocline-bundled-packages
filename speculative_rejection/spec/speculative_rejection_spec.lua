--- Tests for speculative_rejection (iterative reward-pruned best-of-N).
---
--- Coverage (pass conditions):
---   1. meta / spec sanity
---   2. Two-primitive flow — alc.llm_batch (gen/extend) + alc.llm (score/select)
---      called the expected number of times at default n/rounds/alpha
---   3. Defaults n=8, rounds=3, alpha=0.5 => initial 8 -> 4 -> 2 -> 1
---   4. reject_bottom_alpha edge cases: alpha=0 keeps all, alpha=1 keeps 1,
---      alpha=0.5 keeps ceil(n*0.5), ties broken by ascending index
---   5. Task validation: missing / empty / whitespace-only -> error
---   6. parse_scores helper
---   7. rejection_history shape: 3 entries with round/before/after/rejected
---      /scores; rejected_indices carry ORIGINAL 1-based identities
---   8. Custom n / rounds / alpha honored
---
--- Run via the `lua-debugger` MCP server (mlua-lspec), which injects `lust`
--- as a global and prepends search_paths to package.path.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Make sibling packages (speculative_rejection, alc_shapes) resolvable from
-- the repo root regardless of the harness cwd.
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

for _, name in ipairs({
    "speculative_rejection", "alc_shapes",
    "alc_shapes.t", "alc_shapes.check", "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["speculative_rejection"] = nil
    _G.alc = nil
end

--- Build a mock _G.alc that:
---   - counts alc.llm_batch and alc.llm calls,
---   - classifies alc.llm calls into "score" vs "selector" by prompt substring,
---   - by default emits decreasing scores per candidate (Candidate 1 highest,
---     which keeps candidate 1 across all rounds under alpha=0.5),
---   - by default selects candidate 1 as the final winner.
---
--- opts:
---   selector_out — override selector output (string)
---   scoring_out_fn(call_no, prompt) -> string — override scoring output
---   batch_out_fn(call_no, items) -> array of strings — override batch output
local function make_alc_stub(opts)
    opts = opts or {}
    local rec = {
        batch_calls = 0,
        llm_calls = 0,
        score_calls = 0,
        selector_calls = 0,
        batch_items_hist = {},
        score_prompts = {},
        selector_prompt = nil,
    }

    local stub = {}
    stub.llm_batch = function(items)
        rec.batch_calls = rec.batch_calls + 1
        rec.batch_items_hist[#rec.batch_items_hist + 1] = items
        if opts.batch_out_fn then
            return opts.batch_out_fn(rec.batch_calls, items)
        end
        local out = {}
        for i = 1, #items do
            out[i] = string.format("text_r%d_c%d", rec.batch_calls, i)
        end
        return out
    end

    stub.llm = function(prompt, _o)
        rec.llm_calls = rec.llm_calls + 1
        local is_selector = prompt:find("Select the single best candidate", 1, true)
            ~= nil
        if is_selector then
            rec.selector_calls = rec.selector_calls + 1
            rec.selector_prompt = prompt
            return opts.selector_out
                or "SELECTED: 1\nRATIONALE: candidate 1 best satisfies the rubric.\n"
        else
            rec.score_calls = rec.score_calls + 1
            rec.score_prompts[#rec.score_prompts + 1] = prompt
            if opts.scoring_out_fn then
                return opts.scoring_out_fn(rec.score_calls, prompt)
            end
            -- Default: count "[Candidate <i>]" occurrences and emit
            -- decreasing scores (10, 9, 8, ...). This keeps candidate 1 first
            -- across all rounds under alpha=0.5 (deterministic).
            local count = 0
            for _ in prompt:gmatch("%[Candidate %d+%]") do
                count = count + 1
            end
            local out = ""
            for i = 1, count do
                local sc = 10 - (i - 1)
                if sc < 0 then sc = 0 end
                out = out .. string.format("Candidate %d score: %d\n", i, sc)
            end
            return out
        end
    end

    stub.log = function(_level, _msg) end

    return stub, rec
end

-- ═══════════════════════════════════════════════════════════════════
-- meta / spec sanity
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.meta", function()
    reset()
    make_alc_stub()
    local m = require("speculative_rejection")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("speculative_rejection")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("selection")
    end)
    it("exposes run input + result shapes", function()
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
    it("exposes internal test hooks", function()
        expect(type(m._internal.reject_bottom_alpha)).to.equal("function")
        expect(type(m._internal.parse_scores)).to.equal("function")
        expect(type(m._internal.trim)).to.equal("function")
        expect(type(m._internal.DEFAULT_REWARD_RUBRIC)).to.equal("string")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2/3: default flow — n=8, rounds=3, alpha=0.5
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run defaults", function()
    lust.after(reset)

    it("runs 3 batch calls + 3 score calls + 1 selector call (defaults)", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "Explain sorting algorithms." })

        -- 3 rounds: r1 initial batch, r2/r3 extend batch = 3 batch calls.
        expect(rec.batch_calls).to.equal(3)
        -- 3 rounds × 1 score + 1 final selector = 4 alc.llm calls.
        expect(rec.llm_calls).to.equal(4)
        expect(rec.score_calls).to.equal(3)
        expect(rec.selector_calls).to.equal(1)

        expect(ctx.result.candidates_initial).to.equal(8)
        expect(ctx.result.candidates_final).to.equal(1)
        expect(#ctx.result.rejection_history).to.equal(3)
    end)

    it("initial batch has n=8 items by default", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        m.run({ task = "T" })
        expect(#rec.batch_items_hist[1]).to.equal(8)
    end)

    it("rejection reduces survivors 8 -> 4 -> 2 -> 1 (alpha=0.5)", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T" })
        local h = ctx.result.rejection_history
        expect(h[1].survivors_before).to.equal(8)
        expect(h[1].survivors_after).to.equal(4)
        expect(h[2].survivors_before).to.equal(4)
        expect(h[2].survivors_after).to.equal(2)
        expect(h[3].survivors_before).to.equal(2)
        expect(h[3].survivors_after).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 8: custom n / rounds / alpha honored
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run custom knobs", function()
    lust.after(reset)

    it("honors ctx.n", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        m.run({ task = "T", n = 4 })
        expect(#rec.batch_items_hist[1]).to.equal(4)
    end)

    it("honors ctx.rounds", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T", n = 4, rounds = 2 })
        expect(rec.batch_calls).to.equal(2)
        -- 2 score + 1 selector
        expect(rec.llm_calls).to.equal(3)
        expect(#ctx.result.rejection_history).to.equal(2)
    end)

    it("alpha=0 keeps all candidates every round", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T", n = 4, rounds = 2, alpha = 0 })
        expect(ctx.result.candidates_final).to.equal(4)
        for _, h in ipairs(ctx.result.rejection_history) do
            expect(h.survivors_before).to.equal(4)
            expect(h.survivors_after).to.equal(4)
            expect(#h.rejected_indices).to.equal(0)
        end
    end)

    it("alpha=1 keeps exactly 1 candidate (top scorer) each round", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T", n = 4, rounds = 2, alpha = 1 })
        expect(ctx.result.rejection_history[1].survivors_after).to.equal(1)
        expect(ctx.result.candidates_final).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 5: ctx.task validation
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run task validation", function()
    lust.after(reset)

    it("errors when ctx.task is missing", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is empty string", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ok, err = pcall(m.run, { task = "" })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)

    it("errors when ctx.task is whitespace only", function()
        reset()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ok, err = pcall(m.run, { task = "   \t\n  " })
        expect(ok).to.equal(false)
        expect(tostring(err):find("task") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 4: reject_bottom_alpha unit tests
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection._internal.reject_bottom_alpha", function()
    reset()
    make_alc_stub()
    local m = require("speculative_rejection")
    local reject = m._internal.reject_bottom_alpha

    it("alpha=0 keeps all", function()
        local s, r = reject({ 1, 2, 3, 4 }, 0)
        expect(#s).to.equal(4)
        expect(#r).to.equal(0)
    end)

    it("alpha=1 keeps exactly 1 (top scorer)", function()
        local s, r = reject({ 3, 8, 5, 2 }, 1)
        expect(#s).to.equal(1)
        expect(s[1]).to.equal(2) -- index of score 8
        expect(#r).to.equal(3)
    end)

    it("alpha=0.5 with n=8 keeps top 4", function()
        local s, r = reject({ 10, 9, 8, 7, 6, 5, 4, 3 }, 0.5)
        expect(#s).to.equal(4)
        expect(#r).to.equal(4)
        -- Original ascending order preserved in output.
        expect(s[1]).to.equal(1)
        expect(s[2]).to.equal(2)
        expect(s[3]).to.equal(3)
        expect(s[4]).to.equal(4)
        expect(r[1]).to.equal(5)
        expect(r[4]).to.equal(8)
    end)

    it("alpha=0.5 with n=4 keeps 2", function()
        local s = reject({ 1, 2, 3, 4 }, 0.5)
        expect(#s).to.equal(2)
        -- Top 2 scores are indices 3 and 4.
        expect(s[1]).to.equal(3)
        expect(s[2]).to.equal(4)
    end)

    it("ties broken by ascending original index (stable)", function()
        -- All equal scores -> keep_count = 2 -> keep indices 1 and 2.
        local s, r = reject({ 5, 5, 5, 5 }, 0.5)
        expect(#s).to.equal(2)
        expect(s[1]).to.equal(1)
        expect(s[2]).to.equal(2)
        expect(r[1]).to.equal(3)
        expect(r[2]).to.equal(4)
    end)

    it("empty scores -> empty output", function()
        local s, r = reject({}, 0.5)
        expect(#s).to.equal(0)
        expect(#r).to.equal(0)
    end)

    it("alpha in (0,1) never returns zero survivors", function()
        -- ceil(2 * (1 - 0.9)) = ceil(0.2) = 1, clamped to >= 1.
        local s = reject({ 3, 7 }, 0.9)
        expect(#s).to.equal(1)
        expect(s[1]).to.equal(2) -- top score
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 6: parse_scores helper
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection._internal.parse_scores", function()
    reset()
    make_alc_stub()
    local m = require("speculative_rejection")
    local parse = m._internal.parse_scores

    it("parses well-formed score lines", function()
        local out = parse(
            "Candidate 1 score: 7\nCandidate 2 score: 4\nCandidate 3 score: 9\n")
        expect(out[1]).to.equal(7)
        expect(out[2]).to.equal(4)
        expect(out[3]).to.equal(9)
    end)

    it("tolerates lowercase 'candidate' and decimal scores", function()
        local out = parse("candidate 1 score: 6.5\n")
        expect(out[1]).to.equal(6.5)
    end)

    it("skips unparseable lines", function()
        local out = parse("garbage\nCandidate 2 score: 3\nmore garbage\n")
        expect(out[1]).to.equal(nil)
        expect(out[2]).to.equal(3)
    end)

    it("returns empty map on non-string input", function()
        local out = parse(nil)
        expect(next(out)).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 7: rejection_history shape + original-index tracking
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run rejection_history shape", function()
    lust.after(reset)

    it("each entry has round/before/after/rejected_indices/scores", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T" })
        for _, h in ipairs(ctx.result.rejection_history) do
            expect(type(h.round)).to.equal("number")
            expect(type(h.survivors_before)).to.equal("number")
            expect(type(h.survivors_after)).to.equal("number")
            expect(type(h.rejected_indices)).to.equal("table")
            expect(type(h.scores)).to.equal("table")
        end
    end)

    it("rejected_indices carry ORIGINAL 1-based identity across rounds", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        -- Default scoring stub emits scores [10, 9, 8, ...] in local order.
        -- With n=8, alpha=0.5:
        --   Round 1: local 1..8 -> keep local 1..4 (original 1..4);
        --            reject original 5,6,7,8.
        --   Round 2: local 1..4 map to original 1..4 -> keep local 1,2
        --            (original 1,2); reject original 3,4.
        --   Round 3: local 1..2 map to original 1,2 -> keep local 1
        --            (original 1); reject original 2.
        local ctx = m.run({ task = "T" })
        local h = ctx.result.rejection_history
        table.sort(h[1].rejected_indices)
        table.sort(h[2].rejected_indices)
        table.sort(h[3].rejected_indices)
        expect(h[1].rejected_indices[1]).to.equal(5)
        expect(h[1].rejected_indices[4]).to.equal(8)
        expect(h[2].rejected_indices[1]).to.equal(3)
        expect(h[2].rejected_indices[2]).to.equal(4)
        expect(h[3].rejected_indices[1]).to.equal(2)
    end)

    it("scores array length equals survivors_before for that round", function()
        reset()
        local stub, _rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T" })
        for _, h in ipairs(ctx.result.rejection_history) do
            expect(#h.scores).to.equal(h.survivors_before)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pass condition 2 (extra): reward_rubric injection
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run reward_rubric injection", function()
    lust.after(reset)

    it("injects custom rubric verbatim into every scoring prompt", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        m.run({ task = "T", n = 4, rounds = 2, reward_rubric = "MUST reference RFC7231" })
        for _, p in ipairs(rec.score_prompts) do
            expect(p:find("MUST reference RFC7231", 1, true)).to_not.equal(nil)
        end
    end)

    it("falls back to the default rubric when reward_rubric omitted", function()
        reset()
        local stub, rec = make_alc_stub()
        _G.alc = stub
        local m = require("speculative_rejection")
        local default_rubric = m._internal.DEFAULT_REWARD_RUBRIC
        m.run({ task = "T", n = 4, rounds = 1 })
        expect(rec.score_prompts[1]:find(default_rubric, 1, true))
            .to_not.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Selected candidate is the survivor pointed at by the selector's SELECTED
-- ═══════════════════════════════════════════════════════════════════

describe("speculative_rejection.run final selection", function()
    lust.after(reset)

    it("returns the survivor pointed at by SELECTED", function()
        reset()
        -- Force alpha=0 so multiple survivors reach the selector.
        local stub, _rec = make_alc_stub({
            selector_out = "SELECTED: 2\nRATIONALE: candidate 2 wins final round.\n",
        })
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T", n = 3, rounds = 1, alpha = 0 })
        -- Round 1 initial batch text_r1_c<i>: survivor 2's text is "text_r1_c2".
        expect(ctx.result.selected).to.equal("text_r1_c2")
        expect(ctx.result.rationale).to.equal("candidate 2 wins final round.")
    end)

    it("falls back to candidate 1 when SELECTED is unparseable", function()
        reset()
        local stub, _rec = make_alc_stub({
            selector_out = "no marker here at all\n",
        })
        _G.alc = stub
        local m = require("speculative_rejection")
        local ctx = m.run({ task = "T", n = 2, rounds = 1, alpha = 0 })
        expect(ctx.result.selected).to.equal("text_r1_c1")
    end)
end)

reset()
