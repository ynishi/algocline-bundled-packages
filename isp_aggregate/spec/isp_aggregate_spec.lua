--- Tests for isp_aggregate package — paper-faithful (Zhang 2025) helpers.
--- M.run() requires alc.llm (LLM-dependent), so its happy path is
--- exercised only end-to-end. Here we cover:
---   * Pure helpers (sigma_k / inv / ow_weights / argmax / aggregators
---     / kernel / owi accuracy / parse_probabilities)
---   * M.calibrate (pure: no LLM)
---   * M.run input-validation errors reachable without calling alc.llm.

local describe, it, expect = lust.describe, lust.it, lust.expect

package.loaded["isp_aggregate"] = nil
local isp = require("isp_aggregate")

-- ─── meta ──────────────────────────────────────────────────────────────────

describe("isp_aggregate.meta", function()
    it("has correct name", function()
        expect(isp.meta.name).to.equal("isp_aggregate")
    end)

    it("has correct category", function()
        expect(isp.meta.category).to.equal("aggregation")
    end)

    it("bumps to paper-faithful version line (0.2.x)", function()
        expect(isp.meta.version:sub(1, 3)).to.equal("0.2")
    end)
end)

-- ─── clean_answer / normalize ──────────────────────────────────────────────

describe("isp_aggregate._internal.clean_answer", function()
    local clean = isp._internal.clean_answer
    it("strips whitespace", function()
        expect(clean("  hello  ")).to.equal("hello")
    end)
    it("strips trailing punctuation", function()
        expect(clean("Tokyo.")).to.equal("Tokyo")
        expect(clean("Yes!")).to.equal("Yes")
        expect(clean("A,")).to.equal("A")
    end)
    it("collapses internal whitespace", function()
        expect(clean("the   quick\tbrown")).to.equal("the quick brown")
    end)
    it("returns empty string on non-string input", function()
        expect(clean(nil)).to.equal("")
        expect(clean(42)).to.equal("")
    end)
    it("preserves casing", function()
        expect(clean("Tokyo")).to.equal("Tokyo")
        expect(clean("TOKYO")).to.equal("TOKYO")
    end)
end)

describe("isp_aggregate._internal.normalize", function()
    local norm = isp._internal.normalize
    it("lowercases + strips punctuation", function()
        expect(norm("Tokyo.")).to.equal("tokyo")
        expect(norm("TOKYO!")).to.equal("tokyo")
    end)
    it("returns empty string for non-string input", function()
        expect(norm(nil)).to.equal("")
    end)
end)

-- ─── sigma_k / sigma_k_inv ─────────────────────────────────────────────────

describe("isp_aggregate._internal.sigma_k", function()
    local sigma_k = isp._internal.sigma_k

    it("K=2 matches logistic sigmoid", function()
        -- sigma_2(x) = exp(x)/(1+exp(x)) = 1/(1+exp(-x))
        local x = 1.5
        local expected = 1 / (1 + math.exp(-x))
        expect(math.abs(sigma_k(x, 2) - expected) < 1e-12).to.equal(true)
    end)

    it("sigma_K(0) = 1/K", function()
        for _, K in ipairs({ 2, 3, 5, 10 }) do
            local v = sigma_k(0, K)
            expect(math.abs(v - 1 / K) < 1e-12).to.equal(true)
        end
    end)

    it("monotonically increasing in x", function()
        local y_low = sigma_k(-3, 5)
        local y_mid = sigma_k(0, 5)
        local y_hi  = sigma_k(3, 5)
        expect(y_low < y_mid).to.equal(true)
        expect(y_mid < y_hi).to.equal(true)
    end)

    it("bounded in [0, 1] without NaN / Inf at large |x|", function()
        -- At |x|=50 both branches saturate at double precision; verify
        -- that the guarded form keeps the output in [0, 1] rather than
        -- producing NaN or Inf (the max-shift analogue of smc_sample's
        -- compute_weights numerical guard).
        local y  = sigma_k(50, 4)
        expect(y >= 0 and y <= 1).to.equal(true)
        expect(y == y).to.equal(true)            -- not NaN
        expect(y < math.huge).to.equal(true)     -- not Inf
        local y2 = sigma_k(-50, 4)
        expect(y2 >= 0 and y2 <= 1).to.equal(true)
        expect(y2 == y2).to.equal(true)
        -- Away from saturation, strict (0, 1) still holds.
        local y_mid = sigma_k(5, 4)
        expect(y_mid > 0 and y_mid < 1).to.equal(true)
    end)

    it("errors on K < 2", function()
        expect(function() sigma_k(0, 1) end).to.fail()
        expect(function() sigma_k(0, 2.5) end).to.fail()
    end)
end)

describe("isp_aggregate._internal.sigma_k_inv", function()
    local sigma_k     = isp._internal.sigma_k
    local sigma_k_inv = isp._internal.sigma_k_inv

    it("is inverse of sigma_k", function()
        for _, K in ipairs({ 2, 3, 5, 10 }) do
            for _, x in ipairs({ -2.0, -0.5, 0.0, 0.3, 1.7 }) do
                local y = sigma_k(x, K)
                local x_back = sigma_k_inv(y, K)
                expect(math.abs(x_back - x) < 1e-9).to.equal(true)
            end
        end
    end)

    it("x_i=1/K maps to 0 (neutral weight)", function()
        for _, K in ipairs({ 2, 4, 7 }) do
            local v = sigma_k_inv(1 / K, K)
            expect(math.abs(v) < 1e-9).to.equal(true)
        end
    end)

    it("x_i > 1/K maps to positive weight", function()
        expect(sigma_k_inv(0.8, 2) > 0).to.equal(true)
        expect(sigma_k_inv(0.9, 4) > 0).to.equal(true)
    end)

    it("x_i < 1/K maps to negative weight", function()
        expect(sigma_k_inv(0.2, 2) < 0).to.equal(true)
        expect(sigma_k_inv(0.05, 4) < 0).to.equal(true)
    end)

    it("errors on y outside (0, 1)", function()
        expect(function() sigma_k_inv(0, 2) end).to.fail()
        expect(function() sigma_k_inv(1, 2) end).to.fail()
        expect(function() sigma_k_inv(-0.1, 2) end).to.fail()
    end)
end)

-- ─── ow_weights ────────────────────────────────────────────────────────────

describe("isp_aggregate._internal.ow_weights", function()
    local ow_weights = isp._internal.ow_weights

    it("clamps y=0 / y=1 without erroring", function()
        local w = ow_weights({ 0, 1 }, 2, 1e-6)
        expect(type(w[1])).to.equal("number")
        expect(type(w[2])).to.equal("number")
        expect(w[1] < 0).to.equal(true)  -- near-zero accuracy → negative weight
        expect(w[2] > 0).to.equal(true)  -- near-one accuracy → positive weight
    end)

    it("maps equal accuracies to equal weights", function()
        local w = ow_weights({ 0.7, 0.7, 0.7 }, 4)
        expect(math.abs(w[1] - w[2]) < 1e-12).to.equal(true)
        expect(math.abs(w[2] - w[3]) < 1e-12).to.equal(true)
    end)

    it("errors on empty x_vec", function()
        expect(function() ow_weights({}, 2) end).to.fail()
    end)

    it("errors on non-number entry", function()
        expect(function() ow_weights({ "foo" }, 2) end).to.fail()
    end)
end)

-- ─── count_votes / argmax_options ──────────────────────────────────────────

describe("isp_aggregate._internal.count_votes", function()
    local count_votes = isp._internal.count_votes

    it("tallies recognized options", function()
        local c = count_votes({ "A", "B", "A", "C" }, { "A", "B", "C" })
        expect(c["A"]).to.equal(2)
        expect(c["B"]).to.equal(1)
        expect(c["C"]).to.equal(1)
    end)

    it("silently drops unrecognized", function()
        local c = count_votes({ "A", "X", "A" }, { "A", "B" })
        expect(c["A"]).to.equal(2)
        expect(c["B"]).to.equal(0)
    end)

    it("casing / punctuation normalized", function()
        local c = count_votes({ "tokyo.", "TOKYO", "Kyoto" }, { "Tokyo", "Kyoto" })
        expect(c["Tokyo"]).to.equal(2)
        expect(c["Kyoto"]).to.equal(1)
    end)
end)

describe("isp_aggregate._internal.argmax_options", function()
    local argmax = isp._internal.argmax_options

    it("picks strict max", function()
        local b, s = argmax({ A = 3, B = 1 }, { "A", "B" }, "first_in_options")
        expect(b).to.equal("A")
        expect(s).to.equal(3)
    end)

    it("ties: first_in_options returns first", function()
        local b = argmax({ A = 2, B = 2, C = 1 }, { "A", "B", "C" },
            "first_in_options")
        expect(b).to.equal("A")
        local b2 = argmax({ A = 2, B = 2, C = 1 }, { "B", "A", "C" },
            "first_in_options")
        expect(b2).to.equal("B")
    end)

    it("missing scores treated as -inf", function()
        local b = argmax({ A = 1 }, { "A", "B" }, "first_in_options")
        expect(b).to.equal("A")
    end)

    it("uniform_random resolves to one of the tied options", function()
        math.randomseed(1)
        local seen = { A = false, B = false }
        for _ = 1, 50 do
            local b = argmax({ A = 1, B = 1, C = 0 }, { "A", "B", "C" },
                "uniform_random")
            seen[b] = true
        end
        expect(seen.A).to.equal(true)
        expect(seen.B).to.equal(true)
    end)
end)

-- ─── aggregate_ow ──────────────────────────────────────────────────────────

describe("isp_aggregate._internal.aggregate_ow", function()
    local aggregate_ow = isp._internal.aggregate_ow

    it("reduces to majority vote when all weights equal", function()
        local best, scores = aggregate_ow(
            { "A", "B", "A" }, { 1, 1, 1 },
            { "A", "B" }, "first_in_options"
        )
        expect(best).to.equal("A")
        expect(scores["A"]).to.equal(2)
        expect(scores["B"]).to.equal(1)
    end)

    it("higher-weight minority can win", function()
        -- B has 2 votes but low weight (-1 each);
        -- A has 1 vote with high weight (+5) → A wins.
        local best, scores = aggregate_ow(
            { "A", "B", "B" }, { 5, -1, -1 },
            { "A", "B" }, "first_in_options"
        )
        expect(best).to.equal("A")
        expect(scores["A"]).to.equal(5)
        expect(scores["B"]).to.equal(-2)
    end)

    it("errors on #answers != #weights", function()
        expect(function()
            aggregate_ow({ "A" }, { 1, 2 }, { "A" }, "first_in_options")
        end).to.fail()
    end)
end)

-- ─── compute_s_isp_kernel / s_isp_value / aggregate_isp ────────────────────

describe("isp_aggregate._internal.compute_s_isp_kernel", function()
    local compute_kernel = isp._internal.compute_s_isp_kernel

    it("computes empirical conditional frequencies correctly", function()
        -- 4 reference questions, 2 agents, 2 options.
        local tensor = {
            { "A", "A" },
            { "A", "A" },
            { "A", "B" },
            { "B", "B" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        -- #{A_2=A} = 2 (rows 1,2); A_1 = A in both → P̂(A_1=A|A_2=A) = 1.
        expect(math.abs(kernel[1][2]["A"]["A"] - 1.0) < 1e-12).to.equal(true)
        expect(math.abs(kernel[1][2]["A"]["B"] - 0.0) < 1e-12).to.equal(true)
        -- #{A_2=B} = 2 (rows 3,4); A_1 ∈ {A,B} → P̂(A_1=A|A_2=B) = 0.5.
        expect(math.abs(kernel[1][2]["B"]["A"] - 0.5) < 1e-12).to.equal(true)
        expect(math.abs(kernel[1][2]["B"]["B"] - 0.5) < 1e-12).to.equal(true)
    end)

    it("diagonal (i==j) is absent", function()
        local tensor = { { "A", "B" }, { "B", "A" } }
        local kernel = compute_kernel(tensor, { "A", "B" })
        expect(kernel[1][1]).to.equal(nil)
        expect(kernel[2][2]).to.equal(nil)
    end)

    it("omits cells when the denominator has zero observations", function()
        local tensor = { { "A", "A" }, { "A", "A" } }
        local kernel = compute_kernel(tensor, { "A", "B" })
        -- A_2 never == B → kernel[1][2]["B"] absent
        expect(kernel[1][2]["B"]).to.equal(nil)
        expect(kernel[1][2]["A"]).to.exist()
    end)

    it("rejects inconsistent row widths", function()
        expect(function()
            compute_kernel({ { "A", "B" }, { "A" } }, { "A", "B" })
        end).to.fail()
    end)

    it("rejects rows with fewer than 2 agents", function()
        expect(function()
            compute_kernel({ { "A" } }, { "A", "B" })
        end).to.fail()
    end)
end)

describe("isp_aggregate._internal.aggregate_isp", function()
    local compute_kernel = isp._internal.compute_s_isp_kernel
    local aggregate_isp  = isp._internal.aggregate_isp

    it("matches majority vote when kernel is symmetric flat", function()
        -- Build a kernel from a tensor where A and B are equally frequent
        -- and independent across agents. S_ISP ~ 1/K uniformly, so the
        -- subtraction term is constant and argmax reduces to c1.
        local tensor = {
            { "A", "A" }, { "B", "B" }, { "A", "B" }, { "B", "A" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        local best = aggregate_isp({ "A", "A" }, kernel, { "A", "B" },
            "first_in_options")
        expect(best).to.equal("A")
    end)

    it("surprisingly popular: rare-but-high-signal wins via subtraction", function()
        -- Construct a kernel where A appears rarely given B was picked
        -- (so kernel[i][j]["B"]["A"] is small). Then when a_1=A and
        -- a_2=A both contribute to c1(A), but S_ISP(A, i; a_vec) for
        -- option A is small (because the conditioning excludes a_j=A),
        -- so the subtraction is small and A's score stays high.
        local tensor = {
            { "A", "A" }, { "A", "A" }, { "A", "A" },
            { "B", "B" }, { "B", "B" }, { "B", "B" },
            { "A", "B" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        -- Online: both agents vote A. We expect A to win (strong signal).
        local best = aggregate_isp({ "A", "A" }, kernel, { "A", "B" },
            "first_in_options")
        expect(best).to.equal("A")
    end)

    it("returns c1 ties deterministically via first_in_options", function()
        -- Build a balanced kernel that makes subtraction terms equal.
        local tensor = {
            { "A", "A" }, { "A", "B" }, { "B", "A" }, { "B", "B" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        -- c1(A) = 1, c1(B) = 1, and by symmetry S_ISP terms match →
        -- scores equal. first_in_options resolves to the first listed.
        local best = aggregate_isp({ "A", "B" }, kernel, { "A", "B" },
            "first_in_options")
        expect(best).to.equal("A")
        local best2 = aggregate_isp({ "A", "B" }, kernel, { "B", "A" },
            "first_in_options")
        expect(best2).to.equal("B")
    end)

    it("skips S_ISP inner term when a_j is unrecognized (§4.2 Eq.5 requires a_j ∈ S)", function()
        -- 3 agents on {A, B}. Middle agent returns "Z" ∉ S.
        -- Paper's formula requires a_j ∈ S; the impl must skip j for
        -- which a_vec[j] is nil so `a' ≠ a_j` does NOT collapse to
        -- "all K options" (which would violate the 1/(K-1) denominator).
        local tensor = {
            { "A", "A", "A" }, { "A", "A", "A" }, { "A", "A", "A" },
            { "B", "B", "B" }, { "B", "B", "B" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        local best, scores = aggregate_isp({ "A", "Z", "A" }, kernel,
            { "A", "B" }, "first_in_options")
        -- Result must be a valid option.
        expect(best == "A" or best == "B").to.equal(true)
        -- Scores must be finite (no NaN / Inf from count-off denom).
        for _, s in pairs(scores) do
            expect(s == s).to.equal(true)
            expect(s < math.huge and s > -math.huge).to.equal(true)
        end
        -- Domain check: c1(A) = 2, c1(B) = 0 (Z not in options → not counted).
        -- After nil-skip, S_ISP(s, 1) averages only j=3 (a_j=A);
        -- S_ISP(s, 3) averages only j=1 (a_j=A). i=2 is skipped by
        -- aggregate_isp itself. So score(A) - score(B) ≥ 2 -
        -- 2*max(S_ISP(A,·)) + 2*min(S_ISP(B,·)); with the all-A-dominant
        -- tensor the margin keeps A as the winner.
        expect(best).to.equal("A")
    end)
end)

-- ─── estimate_accuracy_owi ────────────────────────────────────────────────

describe("isp_aggregate._internal.estimate_accuracy_owi", function()
    local compute_kernel = isp._internal.compute_s_isp_kernel
    local estimate       = isp._internal.estimate_accuracy_owi

    it("perfect-agreement tensor gives x_i = 1 for every agent", function()
        local tensor = {
            { "A", "A", "A" }, { "B", "B", "B" }, { "A", "A", "A" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        local x = estimate(tensor, kernel, { "A", "B" }, "first_in_options")
        for i = 1, 3 do
            expect(math.abs(x[i] - 1.0) < 1e-9).to.equal(true)
        end
    end)

    it("returns values in [0, 1]", function()
        local tensor = {
            { "A", "A", "B" }, { "A", "B", "A" }, { "B", "A", "A" },
            { "A", "A", "A" }, { "B", "B", "B" },
        }
        local kernel = compute_kernel(tensor, { "A", "B" })
        local x = estimate(tensor, kernel, { "A", "B" }, "first_in_options")
        for i = 1, 3 do
            expect(x[i] >= 0 and x[i] <= 1).to.equal(true)
        end
    end)
end)

-- ─── parse_probabilities (meta_prompt_sp INJECT parser) ────────────────────

describe("isp_aggregate._internal.parse_probabilities", function()
    local parse = isp._internal.parse_probabilities

    it("L1-normalizes parsed probabilities", function()
        -- Input sums to 0.9 → normalized should sum to 1.0.
        local raw = "<probs>\nA: 0.5\nB: 0.4\n</probs>"
        local r, failed = parse(raw, { "A", "B" })
        expect(failed).to.equal(false)
        expect(math.abs(r["A"] + r["B"] - 1.0) < 1e-9).to.equal(true)
        expect(math.abs(r["A"] - 5 / 9) < 1e-9).to.equal(true)
    end)

    it("uniform fallback when no tag / no match", function()
        local _, f1 = parse("blah blah", { "A", "B" })
        expect(f1).to.equal(true)
        local r2, f2 = parse("<probs>\nA: 0\nB: 0\n</probs>", { "A", "B" })
        expect(f2).to.equal(true)
        expect(r2["A"]).to.equal(0.5)
        expect(r2["B"]).to.equal(0.5)
    end)

    it("fills missing labels with 0 then normalizes", function()
        local r = parse("<probs>\nA: 1.0\n</probs>", { "A", "B", "C" })
        expect(math.abs(r["A"] - 1.0) < 1e-12).to.equal(true)
        expect(r["B"]).to.equal(0)
        expect(r["C"]).to.equal(0)
    end)

    it("case-insensitive label match", function()
        local r = parse("<probs>\na: 0.7\nb: 0.3\n</probs>", { "A", "B" })
        expect(math.abs(r["A"] - 0.7) < 1e-9).to.equal(true)
        expect(math.abs(r["B"] - 0.3) < 1e-9).to.equal(true)
    end)

    it("ignores extraneous labels", function()
        local r = parse("<probs>\nA: 0.6\nB: 0.3\nZ: 0.1\n</probs>",
            { "A", "B" })
        -- 0.6/0.9 + 0.3/0.9 = 1.0 (Z ignored before normalize)
        expect(math.abs(r["A"] - 6 / 9) < 1e-9).to.equal(true)
        expect(math.abs(r["B"] - 3 / 9) < 1e-9).to.equal(true)
    end)
end)

-- ─── validate_options / validate_tensor ────────────────────────────────────

describe("isp_aggregate validation helpers", function()
    local v_opts   = isp._internal.validate_options
    local v_tensor = isp._internal.validate_tensor

    it("rejects empty options", function()
        expect(function() v_opts({}, "calibrate") end).to.fail()
        expect(function() v_opts(nil, "calibrate") end).to.fail()
    end)

    it("rejects duplicate options after normalization", function()
        expect(function()
            v_opts({ "Tokyo", "tokyo." }, "calibrate")
        end).to.fail()
    end)

    it("rejects empty tensor", function()
        expect(function()
            v_tensor({}, { "A", "B" }, "calibrate")
        end).to.fail()
    end)

    it("rejects ragged tensor", function()
        expect(function()
            v_tensor({ { "A", "B" }, { "A" } }, { "A", "B" }, "calibrate")
        end).to.fail()
    end)

    it("rejects non-string cell", function()
        expect(function()
            v_tensor({ { "A", 1 } }, { "A" }, "calibrate")
        end).to.fail()
    end)
end)

-- ─── M.calibrate (pure entry) ──────────────────────────────────────────────

describe("isp_aggregate.calibrate", function()
    local tensor = {
        { "A", "A", "B" },
        { "B", "B", "A" },
        { "A", "B", "A" },
        { "B", "A", "B" },
        { "A", "A", "A" },
    }
    local options = { "A", "B" }

    it("method='isp' returns kernel + nil x_estimated", function()
        local cal = isp.calibrate({
            calibration_tensor = tensor,
            options            = options,
            method             = "isp",
        })
        expect(cal.method).to.equal("isp")
        expect(cal.n_agents).to.equal(3)
        expect(cal.n_samples).to.equal(5)
        expect(cal.K).to.equal(2)
        expect(type(cal.s_isp_kernel)).to.equal("table")
        expect(cal.x_estimated).to.equal(nil)
    end)

    it("method='ow_i' returns kernel AND x_estimated of length N", function()
        local cal = isp.calibrate({
            calibration_tensor = tensor,
            options            = options,
            method             = "ow_i",
        })
        expect(cal.method).to.equal("ow_i")
        expect(type(cal.x_estimated)).to.equal("table")
        expect(#cal.x_estimated).to.equal(3)
        for i = 1, 3 do
            local xi = cal.x_estimated[i]
            expect(xi >= 0 and xi <= 1).to.equal(true)
        end
    end)

    it("method='ow_l' raises not-implemented with paper reference", function()
        local ok, err = pcall(isp.calibrate, {
            calibration_tensor = tensor,
            options            = options,
            method             = "ow_l",
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("§5.2") ~= nil
            or tostring(err):find("§E.2") ~= nil).to.equal(true)
    end)

    it("unknown method errors", function()
        expect(function()
            isp.calibrate({
                calibration_tensor = tensor,
                options            = options,
                method             = "bogus",
            })
        end).to.fail()
    end)

    it("missing method errors with descriptive message", function()
        expect(function()
            isp.calibrate({
                calibration_tensor = tensor,
                options            = options,
            })
        end).to.fail()
    end)
end)

-- ─── M.run input validation (no alc.llm call path) ─────────────────────────

describe("isp_aggregate.run input validation", function()
    it("errors on missing task", function()
        expect(function()
            isp.run({ options = { "A", "B" } })
        end).to.fail()
    end)

    it("errors on missing options", function()
        expect(function()
            isp.run({ task = "Q?" })
        end).to.fail()
    end)

    it("method='ow' without x_direct errors before any LLM call", function()
        expect(function()
            isp.run({
                task    = "Q?",
                options = { "A", "B" },
                method  = "ow",
            })
        end).to.fail()
    end)

    it("method='ow_l' errors with paper-reference before any LLM call", function()
        local cal = isp.calibrate({
            calibration_tensor = { { "A", "B" }, { "B", "A" } },
            options            = { "A", "B" },
            method             = "isp",  -- any valid calibration
        })
        local ok, err = pcall(isp.run, {
            task        = "Q?",
            options     = { "A", "B" },
            method      = "ow_l",
            calibration = cal,
            n           = 2,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("ow_l") ~= nil).to.equal(true)
    end)

    it("method='isp' without calibration errors", function()
        expect(function()
            isp.run({
                task    = "Q?",
                options = { "A", "B" },
                method  = "isp",
                n       = 3,
            })
        end).to.fail()
    end)

    it("calibration N mismatch with run N errors", function()
        local cal = isp.calibrate({
            calibration_tensor = { { "A", "B" }, { "B", "A" } },
            options            = { "A", "B" },
            method             = "isp",
        })
        -- cal was built for N=2; run asks for N=5.
        expect(function()
            isp.run({
                task        = "Q?",
                options     = { "A", "B" },
                method      = "isp",
                calibration = cal,
                n           = 5,
            })
        end).to.fail()
    end)

    it("calibration options mismatch errors", function()
        local cal = isp.calibrate({
            calibration_tensor = { { "A", "B" }, { "B", "A" } },
            options            = { "A", "B" },
            method             = "isp",
        })
        expect(function()
            isp.run({
                task        = "Q?",
                options     = { "A", "C" },  -- differs from calibration
                method      = "isp",
                calibration = cal,
                n           = 2,
            })
        end).to.fail()
    end)

    it("method='ow_i' with isp-only calibration errors", function()
        local cal = isp.calibrate({
            calibration_tensor = { { "A", "B" }, { "B", "A" } },
            options            = { "A", "B" },
            method             = "isp",
        })
        -- OW-I requires x_estimated, which pure ISP cal doesn't produce.
        expect(function()
            isp.run({
                task        = "Q?",
                options     = { "A", "B" },
                method      = "ow_i",
                calibration = cal,
                n           = 2,
            })
        end).to.fail()
    end)
end)
