--- Tests for sprt (Wald Sequential Probability Ratio Test)
---
--- Coverage:
---   * Meta + API surface
---   * Input validation
---   * Boundary computation matches Wald's formula
---   * observe/decide behaviour including terminal no-op
---   * Monte Carlo α/β grid: realized error rates stay within the
---     Wald upper bound (α/(1-β), β/(1-α)) with buffer, verifying the
---     primitive delivers its declared promise on synthetic streams.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function reset()
    package.loaded["sprt"] = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Meta
-- ═══════════════════════════════════════════════════════════════════

describe("sprt.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local sprt = require("sprt")
        expect(sprt.meta.name).to.equal("sprt")
    end)

    it("has version 0.1.0", function()
        local sprt = require("sprt")
        expect(sprt.meta.version).to.equal("0.1.0")
    end)

    it("category is validation", function()
        local sprt = require("sprt")
        expect(sprt.meta.category).to.equal("validation")
    end)

    it("description mentions Wald and Bernoulli", function()
        local sprt = require("sprt")
        expect(sprt.meta.description:find("Wald") ~= nil).to.equal(true)
        expect(sprt.meta.description:find("Bernoulli") ~= nil).to.equal(true)
    end)

    it("exposes new/observe/decide/simulate/expected_n_envelope", function()
        local sprt = require("sprt")
        expect(type(sprt.new)).to.equal("function")
        expect(type(sprt.observe)).to.equal("function")
        expect(type(sprt.decide)).to.equal("function")
        expect(type(sprt.simulate)).to.equal("function")
        expect(type(sprt.expected_n_envelope)).to.equal("function")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Input validation
-- ═══════════════════════════════════════════════════════════════════

describe("sprt.new validation", function()
    lust.after(reset)

    it("rejects p0 >= p1", function()
        local sprt = require("sprt")
        local ok, err = pcall(sprt.new,
            { p0 = 0.7, p1 = 0.5, alpha = 0.05, beta = 0.1 })
        expect(ok).to.equal(false)
        expect(err:find("p0 < p1") ~= nil).to.equal(true)
    end)

    it("rejects p0 <= 0", function()
        local sprt = require("sprt")
        local ok = pcall(sprt.new,
            { p0 = 0, p1 = 0.7, alpha = 0.05, beta = 0.1 })
        expect(ok).to.equal(false)
    end)

    it("rejects p1 >= 1", function()
        local sprt = require("sprt")
        local ok = pcall(sprt.new,
            { p0 = 0.5, p1 = 1.0, alpha = 0.05, beta = 0.1 })
        expect(ok).to.equal(false)
    end)

    it("rejects alpha >= 0.5", function()
        local sprt = require("sprt")
        local ok = pcall(sprt.new,
            { p0 = 0.5, p1 = 0.7, alpha = 0.5, beta = 0.1 })
        expect(ok).to.equal(false)
    end)

    it("rejects beta <= 0", function()
        local sprt = require("sprt")
        local ok = pcall(sprt.new,
            { p0 = 0.5, p1 = 0.7, alpha = 0.05, beta = 0 })
        expect(ok).to.equal(false)
    end)

    it("accepts well-formed config", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        expect(st).to.exist()
        expect(st.verdict).to.equal("continue")
        expect(st.log_lr).to.equal(0)
        expect(st.n).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Boundary formula
-- ═══════════════════════════════════════════════════════════════════

describe("sprt boundaries", function()
    lust.after(reset)

    it("A = log((1 - β) / α)", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        local expected_a = math.log((1 - 0.1) / 0.05)
        expect(math.abs(st.a_bound - expected_a) < 1e-9).to.equal(true)
    end)

    it("B = log(β / (1 - α))", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        local expected_b = math.log(0.1 / (1 - 0.05))
        expect(math.abs(st.b_bound - expected_b) < 1e-9).to.equal(true)
    end)

    it("A > 0 > B for typical configs", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        expect(st.a_bound > 0).to.equal(true)
        expect(st.b_bound < 0).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- observe / decide
-- ═══════════════════════════════════════════════════════════════════

describe("sprt.observe", function()
    lust.after(reset)

    it("success increments log_lr by log(p1/p0)", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        sprt.observe(st, 1)
        local expected = math.log(0.8 / 0.5)
        expect(math.abs(st.log_lr - expected) < 1e-9).to.equal(true)
        expect(st.n).to.equal(1)
    end)

    it("failure increments log_lr by log((1-p1)/(1-p0))", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        sprt.observe(st, 0)
        local expected = math.log(0.2 / 0.5)
        expect(math.abs(st.log_lr - expected) < 1e-9).to.equal(true)
        expect(st.n).to.equal(1)
    end)

    it("accepts boolean outcomes", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        sprt.observe(st, true)
        sprt.observe(st, false)
        expect(st.n).to.equal(2)
    end)

    it("rejects non-binary outcomes", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        local ok = pcall(sprt.observe, st, 0.5)
        expect(ok).to.equal(false)
    end)

    it("transitions to accept_h1 when log_lr crosses A", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        -- All successes — log_lr grows by log(0.8/0.5) = 0.4700 per trial.
        -- A = log(0.9/0.05) = 2.8904. Should terminate at n = 7 (7 × 0.47 = 3.29 ≥ 2.89).
        for _ = 1, 10 do sprt.observe(st, 1) end
        expect(st.verdict).to.equal("accept_h1")
    end)

    it("transitions to accept_h0 when log_lr crosses B", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        -- All failures — decrement per trial log(0.2/0.5) = -0.9163.
        -- B = log(0.1/0.95) = -2.2513. Terminates at n=3.
        for _ = 1, 10 do sprt.observe(st, 0) end
        expect(st.verdict).to.equal("accept_h0")
    end)

    it("is a no-op after terminal verdict", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        for _ = 1, 10 do sprt.observe(st, 1) end
        local n_at_term = st.n
        local lr_at_term = st.log_lr
        sprt.observe(st, 1)
        sprt.observe(st, 0)
        expect(st.n).to.equal(n_at_term)
        expect(st.log_lr).to.equal(lr_at_term)
        expect(st.verdict).to.equal("accept_h1")
    end)
end)

describe("sprt.decide", function()
    lust.after(reset)

    it("snapshots state without mutating", function()
        local sprt = require("sprt")
        local st = sprt.new({ p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 })
        sprt.observe(st, 1)
        local d1 = sprt.decide(st)
        local d2 = sprt.decide(st)
        expect(d1.verdict).to.equal(d2.verdict)
        expect(d1.log_lr).to.equal(d2.log_lr)
        expect(d1.n).to.equal(d2.n)
        expect(st.n).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- simulate + Monte Carlo α/β verification
-- ═══════════════════════════════════════════════════════════════════

describe("sprt.simulate", function()
    lust.after(reset)

    it("returns truncated=true when max_n reached without decision", function()
        local sprt = require("sprt")
        -- Very tight gap + very small max_n → almost certain truncation.
        local r = sprt.simulate(
            { p0 = 0.49, p1 = 0.51, alpha = 0.05, beta = 0.05 },
            0.5, 3, 42
        )
        expect(r.truncated).to.equal(true)
        expect(r.verdict).to.equal("continue")
    end)

    it("fires accept_h1 on p=1 success stream", function()
        local sprt = require("sprt")
        local r = sprt.simulate(
            { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 },
            1.0, 50, 1
        )
        expect(r.verdict).to.equal("accept_h1")
        expect(r.truncated).to.equal(false)
    end)

    it("fires accept_h0 on p=0 failure stream", function()
        local sprt = require("sprt")
        local r = sprt.simulate(
            { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 },
            0.0, 50, 1
        )
        expect(r.verdict).to.equal("accept_h0")
        expect(r.truncated).to.equal(false)
    end)
end)

-- Monte Carlo verification of realized error rates.
--
-- Under H0 (true p = p0): realized alpha_hat ≤ alpha / (1 - beta) (Wald).
-- Under H1 (true p = p1): realized beta_hat ≤ beta / (1 - alpha) (Wald).
-- We use max_n = 500 (well above expected_n_envelope for these configs)
-- so truncation is rare, and check realized rates stay within 2× the
-- declared bound to absorb both Monte Carlo noise (±~0.02 at T=500) and
-- Wald's overshoot slack.
describe("sprt Monte Carlo α/β verification", function()
    lust.after(reset)

    local function run_trials(cfg, true_p, trials, max_n, base_seed)
        local sprt = require("sprt")
        local count_h0, count_h1, count_trunc = 0, 0, 0
        local sum_n = 0
        for i = 1, trials do
            local r = sprt.simulate(cfg, true_p, max_n, base_seed + i)
            sum_n = sum_n + r.n
            if r.verdict == "accept_h0" then
                count_h0 = count_h0 + 1
            elseif r.verdict == "accept_h1" then
                count_h1 = count_h1 + 1
            else
                count_trunc = count_trunc + 1
            end
        end
        return {
            h0 = count_h0, h1 = count_h1, trunc = count_trunc,
            avg_n = sum_n / trials,
        }
    end

    it("realized α_hat ≤ 2·α under H0 (p=p0)", function()
        local cfg = { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10 }
        local trials = 500
        local r = run_trials(cfg, cfg.p0, trials, 500, 10000)
        local alpha_hat = r.h1 / trials
        -- Declared α = 0.05 → bound 2·α = 0.10. Wald's upper envelope
        -- is α/(1-β) = 0.0556 and MC sigma at T=500 is ~0.01.
        expect(alpha_hat <= 0.10).to.equal(true)
        -- Sanity: truncation should be rare at max_n=500.
        expect(r.trunc <= trials * 0.02).to.equal(true)
    end)

    it("realized β_hat ≤ 2·β under H1 (p=p1)", function()
        local cfg = { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10 }
        local trials = 500
        local r = run_trials(cfg, cfg.p1, trials, 500, 20000)
        local beta_hat = r.h0 / trials
        expect(beta_hat <= 0.20).to.equal(true)
        expect(r.trunc <= trials * 0.02).to.equal(true)
    end)

    it("avg_n under H1 is below a fixed-sample baseline", function()
        -- Rough envelope: a fixed-sample binomial test to distinguish
        -- p0=0.5 from p1=0.8 at (α=0.05, power 0.9) needs
        -- n ≈ (z_α + z_β)² · p·(1-p) / (p1-p0)²
        --   ≈ (1.645 + 1.28)² · 0.5·0.5 / 0.09 ≈ 23.8
        -- SPRT's Wald envelope at p=p1 is A / E[log λ|p1] where
        --     E[log λ|p1] = 0.8·log(0.8/0.5) + 0.2·log(0.2/0.5)
        --                 ≈ 0.8·0.4700 + 0.2·(-0.9163) ≈ 0.1927
        --     A = log(0.9/0.05) ≈ 2.890 → E[N | p1] ≈ 15.0
        -- So avg_n should comfortably undercut the fixed-sample 23.8.
        local sprt = require("sprt")
        local cfg = { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.10 }
        local r = run_trials(cfg, cfg.p1, 300, 500, 30000)
        expect(r.avg_n < 24).to.equal(true)
        -- Envelope sanity: expected_n_envelope at p=p1 should be in the
        -- ballpark of the realized avg_n.
        local env = sprt.expected_n_envelope(cfg, cfg.p1)
        expect(env > 10 and env < 30).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- expected_n_envelope
-- ═══════════════════════════════════════════════════════════════════

describe("sprt.expected_n_envelope", function()
    lust.after(reset)

    it("returns positive for p=p1", function()
        local sprt = require("sprt")
        local env = sprt.expected_n_envelope(
            { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 }, 0.8)
        expect(env > 0).to.equal(true)
    end)

    it("returns positive for p=p0", function()
        local sprt = require("sprt")
        local env = sprt.expected_n_envelope(
            { p0 = 0.5, p1 = 0.8, alpha = 0.05, beta = 0.1 }, 0.5)
        expect(env > 0).to.equal(true)
    end)

    it("grows as (p1 - p0) shrinks", function()
        local sprt = require("sprt")
        local wide = sprt.expected_n_envelope(
            { p0 = 0.3, p1 = 0.9, alpha = 0.05, beta = 0.05 }, 0.9)
        local narrow = sprt.expected_n_envelope(
            { p0 = 0.55, p1 = 0.65, alpha = 0.05, beta = 0.05 }, 0.65)
        expect(narrow > wide).to.equal(true)
    end)
end)
