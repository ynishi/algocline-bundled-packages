--- Tests for recipe_quick_vote (Adaptive-stop majority vote w/ SPRT gate)
--- Mocked alc.llm; no real API calls.
---
--- Scenario coverage:
---   * confirmed  — all samples agree with sample-1 leader, SPRT crosses A.
---   * rejected   — subsequent samples all disagree, SPRT crosses B.
---   * truncated  — alternating agree/disagree, loop exits at max_n.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- Mock factory. `answers[k]` is the extracted-answer string returned for
-- the k-th sample's extraction call (the 2k-th alc.llm call overall, since
-- each draw_sample issues reasoning→extract in that order).
local function mock_alc(answers)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            local idx = #call_log
            if idx % 2 == 1 then
                return "mock reasoning for call " .. tostring(idx)
            else
                local sample_idx = idx / 2
                return answers[sample_idx] or "fallback"
            end
        end,
        log = function() end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["recipe_quick_vote"] = nil
    package.loaded["sprt"] = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Meta / structure
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_quick_vote.meta", function()
    lust.after(reset)

    it("has correct name", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r.meta.name).to.equal("recipe_quick_vote")
    end)

    it("is a recipe", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r.meta.category).to.equal("recipe")
    end)

    it("lists sprt as ingredient", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        local found = false
        for _, p in ipairs(r.ingredients) do
            if p == "sprt" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("declares caveats", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(type(r.caveats)).to.equal("table")
        expect(#r.caveats > 0).to.equal(true)
    end)

    it("declares verified.stage_coverage", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(type(r.verified)).to.equal("table")
        expect(type(r.verified.stage_coverage)).to.equal("table")
        expect(#r.verified.stage_coverage >= 1).to.equal(true)
    end)

    it("exposes run fn", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(type(r.run)).to.equal("function")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Internal helpers
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_quick_vote._internal", function()
    lust.after(reset)

    it("clean_answer strips surrounding whitespace", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.clean_answer("  42  ")).to.equal("42")
    end)

    it("clean_answer collapses internal whitespace", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.clean_answer("x    y\t z")).to.equal("x y z")
    end)

    it("clean_answer strips trailing punctuation", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.clean_answer("42.")).to.equal("42")
        expect(r._internal.clean_answer("yes!")).to.equal("yes")
        expect(r._internal.clean_answer("ok?")).to.equal("ok")
    end)

    it("normalize lowercases", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.normalize("Yes.")).to.equal("yes")
    end)

    -- F4 lock-in: numeric canonicalization. These cases are why the
    -- leader-vs-vote table needs a *canonical* representation — the
    -- same integer written three different ways must collide.
    it("normalize canonicalizes integer-valued floats", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.normalize("42.0")).to.equal("42")
        expect(r._internal.normalize("42.00")).to.equal("42")
    end)

    it("normalize strips thousands separators (digit-grouped only)", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.normalize("1,000")).to.equal("1000")
        expect(r._internal.normalize("1,234,567")).to.equal("1234567")
        -- "1,5" is NOT a thousands-group pattern (regex requires 3-digit
        -- groups after each comma), so it is left alone and falls back
        -- to :lower() — guards against de_DE-style decimal-comma input
        -- being silently coerced to 15 or 1.5.
        expect(r._internal.normalize("1,5")).to.equal("1,5")
    end)

    it("normalize evaluates integer-divisible fractions", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.normalize("144/12")).to.equal("12")
        expect(r._internal.normalize("144 / 12")).to.equal("12")
        -- 1/3 is NOT integer-divisible → left as-is (lowercased).
        expect(r._internal.normalize("1/3")).to.equal("1/3")
    end)

    it("normalize leaves non-numeric strings to :lower()", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(r._internal.normalize("Hello World")).to.equal("hello world")
        expect(r._internal.normalize("ABC")).to.equal("abc")
    end)

    it("DIVERSITY_HINTS is a non-empty table", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        expect(type(r._internal.DIVERSITY_HINTS)).to.equal("table")
        expect(#r._internal.DIVERSITY_HINTS > 0).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Parameter validation
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_quick_vote.run validation", function()
    lust.after(reset)

    it("errors without task", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        local ok = pcall(r.run, {})
        expect(ok).to.equal(false)
    end)

    it("errors on p0 >= p1", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        local ok = pcall(r.run, {
            task = "T", p0 = 0.8, p1 = 0.5,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on min_n < 2", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        local ok = pcall(r.run, { task = "T", min_n = 1 })
        expect(ok).to.equal(false)
    end)

    it("errors on max_n < min_n", function()
        mock_alc({})
        local r = require("recipe_quick_vote")
        local ok = pcall(r.run, { task = "T", min_n = 5, max_n = 3 })
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Scenarios
-- ═══════════════════════════════════════════════════════════════════

-- Bounds at (p0=0.5, p1=0.8, α=0.05, β=0.10):
--   A = log(0.9/0.05)  ≈ +2.8904
--   B = log(0.1/0.95) ≈ -2.2513
-- Per-trial increments:
--   agree    : log(0.8/0.5)  ≈ +0.4700
--   disagree : log(0.2/0.5)  ≈ -0.9163
--
-- 7 agreements    →  log_lr ≈ 3.29  ≥ A  → accept_h1  (sample 8)
-- 3 disagreements →  log_lr ≈ -2.75 ≤ B  → accept_h0  (sample 4)

describe("recipe_quick_vote confirmed path", function()
    lust.after(reset)

    it("accepts H1 after 7 agreements (sample 8)", function()
        local log = mock_alc({
            "42", "42", "42", "42", "42",
            "42", "42", "42", "42", "42",
        })
        local r = require("recipe_quick_vote")
        local ctx = r.run({
            task = "What is 17 + 25?",
            p0 = 0.5, p1 = 0.8,
            alpha = 0.05, beta = 0.10,
            min_n = 3, max_n = 10,
        })
        expect(ctx.result.outcome).to.equal("confirmed")
        expect(ctx.result.verdict).to.equal("accept_h1")
        expect(ctx.result.n_samples).to.equal(8)
        expect(ctx.result.answer).to.equal("42")
        expect(ctx.result.leader_norm).to.equal("42")
        expect(ctx.result.total_llm_calls).to.equal(16)
        expect(ctx.result.needs_investigation).to.equal(false)
        -- Sanity: call log matches total_llm_calls.
        expect(#log).to.equal(16)
    end)

    it("leader commits from sample 1 even with punctuation drift", function()
        mock_alc({
            "42.",          -- leader raw has trailing dot
            "42",
            "42!",
            "42,",
            "42",
            "42",
            "42",
            "42",
        })
        local r = require("recipe_quick_vote")
        local ctx = r.run({
            task = "Q",
            min_n = 3, max_n = 10,
        })
        -- clean_answer strips the dot from the raw leader
        expect(ctx.result.answer).to.equal("42")
        expect(ctx.result.leader_norm).to.equal("42")
        expect(ctx.result.outcome).to.equal("confirmed")
    end)
end)

describe("recipe_quick_vote rejected path", function()
    lust.after(reset)

    it("accepts H0 after 3 disagreements (sample 4)", function()
        mock_alc({
            "42",           -- leader
            "43", "43", "43", "43", "43",
        })
        local r = require("recipe_quick_vote")
        local ctx = r.run({
            task = "Ambiguous",
            p0 = 0.5, p1 = 0.8,
            alpha = 0.05, beta = 0.10,
            min_n = 3, max_n = 10,
        })
        expect(ctx.result.outcome).to.equal("rejected")
        expect(ctx.result.verdict).to.equal("accept_h0")
        expect(ctx.result.n_samples).to.equal(4)
        expect(ctx.result.answer).to.equal("42")
        -- 'rejected' is CONCLUSIVE (SPRT accepted H0), so the flag
        -- does NOT fire — the consumer should re-enter with the
        -- plurality-leader, not escalate to investigation.
        expect(ctx.result.needs_investigation).to.equal(false)
        expect(ctx.result.total_llm_calls).to.equal(8)
    end)
end)

describe("recipe_quick_vote truncated path", function()
    lust.after(reset)

    it("truncates at max_n when evidence is inconclusive", function()
        -- Cumulative log_lr trace (per-trial increments: agree=+0.470,
        -- disagree=-0.916; A ≈ +2.89, B ≈ -2.25):
        --   leader                             log_lr = 0
        --   sample 2: agree    0 + 0.470     = +0.470
        --   sample 3: disagree 0.470 - 0.916 = -0.446
        --   sample 4: agree    -0.446+ 0.470 = +0.024
        --   sample 5: disagree 0.024 - 0.916 = -0.892
        -- Neither A nor B is crossed → truncated at max_n = 5.
        mock_alc({
            "42",   -- leader                     (log_lr = 0)
            "42",   -- agree     (log_lr ≈ +0.47)
            "43",   -- disagree  (log_lr ≈ -0.45)
            "42",   -- agree     (log_lr ≈ +0.02)
            "43",   -- disagree  (log_lr ≈ -0.89)  — never crosses A or B
        })
        local r = require("recipe_quick_vote")
        local ctx = r.run({
            task = "Hard",
            p0 = 0.5, p1 = 0.8,
            alpha = 0.05, beta = 0.10,
            min_n = 3, max_n = 5,
        })
        expect(ctx.result.outcome).to.equal("truncated")
        expect(ctx.result.verdict).to.equal("continue")
        expect(ctx.result.n_samples).to.equal(5)
        -- 'truncated' is the ONLY outcome that should fire
        -- needs_investigation under the new semantic.
        expect(ctx.result.needs_investigation).to.equal(true)
        -- Vote counts should reflect the mix (3 × "42", 2 × "43").
        expect(ctx.result.vote_counts["42"]).to.equal(3)
        expect(ctx.result.vote_counts["43"]).to.equal(2)
        -- SPRT snapshot present.
        expect(type(ctx.result.sprt)).to.equal("table")
        expect(type(ctx.result.sprt.log_lr)).to.equal("number")
        expect(type(ctx.result.sprt.a_bound)).to.equal("number")
        expect(type(ctx.result.sprt.b_bound)).to.equal("number")
    end)
end)

describe("recipe_quick_vote context echo", function()
    lust.after(reset)

    it("records params used on the result", function()
        mock_alc({ "42", "42", "42", "42", "42", "42", "42", "42" })
        local r = require("recipe_quick_vote")
        local ctx = r.run({
            task = "Q",
            p0 = 0.5, p1 = 0.8,
            alpha = 0.05, beta = 0.10,
            min_n = 3, max_n = 10,
        })
        expect(ctx.result.params.p0).to.equal(0.5)
        expect(ctx.result.params.p1).to.equal(0.8)
        expect(ctx.result.params.alpha).to.equal(0.05)
        expect(ctx.result.params.beta).to.equal(0.10)
        expect(ctx.result.params.min_n).to.equal(3)
        expect(ctx.result.params.max_n).to.equal(10)
    end)

    it("diversity hint is injected into samples 2+", function()
        local log = mock_alc({
            "42", "42", "42", "42",
            "42", "42", "42", "42",
        })
        local r = require("recipe_quick_vote")
        r.run({ task = "Q", min_n = 3, max_n = 10 })
        -- Every odd call (reasoning) carries one of the DIVERSITY_HINTS
        -- strings in its prompt. Spot-check a non-first reasoning call.
        local hints = require("recipe_quick_vote")._internal.DIVERSITY_HINTS
        local saw_hint = false
        for _, hint in ipairs(hints) do
            if log[3].prompt:find(hint, 1, true) then
                saw_hint = true
                break
            end
        end
        expect(saw_hint).to.equal(true)
    end)
end)
