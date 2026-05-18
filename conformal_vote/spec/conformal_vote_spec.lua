--- Tests for conformal_vote (Wang et al. 2026, arXiv:2604.07667).
---
--- Coverage (issue §10):
---   1.  calibrate quantile matches sorted[⌈(n+1)(1-α)⌉]
---   2.  aggregate uniform weights ⇒ arithmetic mean
---   3.  aggregate custom weights + Σw=1 enforcement
---   4.  predict_set threshold application
---   5.  decide — 4 cases (Proposition 3 incl. |C|=1 ∧ p1<τ edge)
---   6.  Monte Carlo coverage guarantee (seed=42, tolerance 0.92)
---   7.  Decision 3-value consistency (commit ⇒ selected != nil)
---   8.  run with mocked alc.llm (decision flows end-to-end)
---   9.  spec_resolver: args/input exclusivity per-entry
---   10. conformal_decided shape validates
---   11. Card emission (auto_card=true + stubbed alc.card)
---   12. parse_probabilities uniform fallback (BP, §4.6)

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function reset()
    package.loaded["conformal_vote"] = nil
    _G.alc = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Meta
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local cv = require("conformal_vote")
        expect(cv.meta.name).to.equal("conformal_vote")
    end)

    it("has version 0.1.0", function()
        local cv = require("conformal_vote")
        expect(cv.meta.version).to.equal("0.1.0")
    end)

    it("category is validation", function()
        local cv = require("conformal_vote")
        expect(cv.meta.category).to.equal("validation")
    end)

    it("description mentions conformal and coverage", function()
        local cv = require("conformal_vote")
        expect(cv.meta.description:find("conformal") ~= nil).to.equal(true)
        expect(cv.meta.description:find("coverage") ~= nil).to.equal(true)
    end)

    it("exposes calibrate/aggregate/predict_set/decide/run", function()
        local cv = require("conformal_vote")
        expect(type(cv.calibrate)).to.equal("function")
        expect(type(cv.aggregate)).to.equal("function")
        expect(type(cv.predict_set)).to.equal("function")
        expect(type(cv.decide)).to.equal("function")
        expect(type(cv.run)).to.equal("function")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 1: calibrate finite-sample quantile
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.calibrate — finite-sample quantile", function()
    lust.after(reset)

    it("n=100, α=0.05 ⇒ q_hat equals sorted[96]", function()
        local cv = require("conformal_vote")
        -- Build 100 calibration samples with deterministic scores.
        -- agent_probs such that with uniform weights 1/3, p_social(true)
        -- is a ramp from ~0.01 to ~1.00 across the 100 samples, so
        -- s_nc = 1 - p_social(true) is a reverse ramp (1.00 → 0.01).
        -- After sort ascending, sorted[96] is the 96th-smallest score.
        local samples = {}
        for i = 1, 100 do
            local p = i / 101  -- strictly increasing, in (0, 1)
            local leftover = (1 - p) / 2
            samples[i] = {
                agent_probs = {
                    [1] = { A = p, B = leftover, C = leftover },
                    [2] = { A = p, B = leftover, C = leftover },
                    [3] = { A = p, B = leftover, C = leftover },
                },
                true_label = "A",
            }
        end
        local cal = cv.calibrate({
            calibration_samples = samples,
            alpha = 0.05,
        })
        -- Index ⌈101·0.95⌉ = ⌈95.95⌉ = 96
        -- Scores ascending are 1 - i/101 sorted asc, i.e. the set
        -- { 1 - 100/101, 1 - 99/101, ..., 1 - 1/101 } = { 1/101, ...,
        -- 100/101 } sorted asc. So sorted[96] = 96/101.
        local expected = 96 / 101
        expect(math.abs(cal.q_hat - expected) < 1e-9).to.equal(true)
        expect(cal.n).to.equal(100)
        expect(cal.alpha).to.equal(0.05)
        expect(math.abs(cal.tau - (1 - expected)) < 1e-9).to.equal(true)
    end)

    it("returns weights = uniform array when weights nil", function()
        local cv = require("conformal_vote")
        local samples = {}
        for i = 1, 10 do
            samples[i] = {
                agent_probs = {
                    [1] = { A = 0.7, B = 0.3 },
                    [2] = { A = 0.6, B = 0.4 },
                    [3] = { A = 0.8, B = 0.2 },
                },
                true_label = "A",
            }
        end
        local cal = cv.calibrate({ calibration_samples = samples, alpha = 0.1 })
        expect(type(cal.weights)).to.equal("table")
        expect(#cal.weights).to.equal(3)
        for i = 1, 3 do
            expect(math.abs(cal.weights[i] - 1/3) < 1e-9).to.equal(true)
        end
    end)

    it("rejects alpha <= 0 or alpha >= 1", function()
        local cv = require("conformal_vote")
        local samples = { {
            agent_probs = { [1] = { A = 0.5, B = 0.5 } },
            true_label = "A",
        } }
        local ok, err = pcall(cv.calibrate, {
            calibration_samples = samples, alpha = 0,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("alpha") ~= nil).to.equal(true)

        ok, _ = pcall(cv.calibrate, { calibration_samples = samples, alpha = 1 })
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 2 & 3: aggregate — uniform and custom weights
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.aggregate", function()
    lust.after(reset)

    it("uniform weights: equal arithmetic mean", function()
        local cv = require("conformal_vote")
        local p = cv.aggregate({
            agent_probs = {
                { A = 0.9, B = 0.1 },
                { A = 0.6, B = 0.4 },
                { A = 0.3, B = 0.7 },
            },
        })
        expect(math.abs(p.A - 0.6) < 1e-9).to.equal(true)
        expect(math.abs(p.B - 0.4) < 1e-9).to.equal(true)
    end)

    it("custom weights: weighted average respects Σw = 1", function()
        local cv = require("conformal_vote")
        local p = cv.aggregate({
            agent_probs = {
                { A = 1.0 },
                { A = 0.0 },
                { A = 0.5 },
            },
            weights = { 0.5, 0.3, 0.2 },
        })
        expect(math.abs(p.A - 0.6) < 1e-9).to.equal(true)
    end)

    it("rejects weights that do not sum to 1", function()
        local cv = require("conformal_vote")
        local ok, err = pcall(cv.aggregate, {
            agent_probs = { { A = 1.0 }, { A = 1.0 } },
            weights = { 0.5, 0.6 },
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("sum") ~= nil).to.equal(true)
    end)

    it("rejects weights length mismatch", function()
        local cv = require("conformal_vote")
        local ok, err = pcall(cv.aggregate, {
            agent_probs = { { A = 1.0 }, { A = 1.0 }, { A = 1.0 } },
            weights = { 0.5, 0.5 },
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("length") ~= nil).to.equal(true)
    end)

    it("handles disjoint label sets across agents", function()
        local cv = require("conformal_vote")
        local p = cv.aggregate({
            agent_probs = {
                { A = 1.0 },
                { B = 1.0 },
            },
        })
        expect(math.abs(p.A - 0.5) < 1e-9).to.equal(true)
        expect(math.abs(p.B - 0.5) < 1e-9).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 4: predict_set
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.predict_set", function()
    lust.after(reset)

    it("returns { y : p_social[y] >= tau }", function()
        local cv = require("conformal_vote")
        local pset = cv.predict_set({
            p_social = { A = 0.5, B = 0.3, C = 0.2 },
            tau = 0.4,
        })
        expect(#pset.labels).to.equal(1)
        expect(pset.labels[1]).to.equal("A")
        expect(pset.top1).to.equal("A")
        expect(math.abs(pset.top1_prob - 0.5) < 1e-9).to.equal(true)
        expect(pset.top2).to.equal("B")
        expect(math.abs(pset.top2_prob - 0.3) < 1e-9).to.equal(true)
    end)

    it("includes all labels above threshold when tau is low", function()
        local cv = require("conformal_vote")
        local pset = cv.predict_set({
            p_social = { A = 0.5, B = 0.3, C = 0.2 },
            tau = 0.15,
        })
        expect(#pset.labels).to.equal(3)
    end)

    it("returns empty labels when tau exceeds top1", function()
        local cv = require("conformal_vote")
        local pset = cv.predict_set({
            p_social = { A = 0.3, B = 0.2 },
            tau = 0.5,
        })
        expect(#pset.labels).to.equal(0)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 5: decide — 4 cases incl. |C|=1 ∧ p1<τ edge
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.decide — Proposition 3", function()
    lust.after(reset)

    it("commit: |C|=1 ∧ p1≥τ ∧ p2<τ", function()
        local cv = require("conformal_vote")
        local d = cv.decide({
            prediction_set = {
                labels = { "A" },
                top1 = "A", top1_prob = 0.7,
                top2 = "B", top2_prob = 0.2,
            },
            tau = 0.4,
        })
        expect(d.action).to.equal("commit")
        expect(d.selected).to.equal("A")
    end)

    it("escalate: |C|≥2 ∧ p2≥τ", function()
        local cv = require("conformal_vote")
        local d = cv.decide({
            prediction_set = {
                labels = { "A", "B" },
                top1 = "A", top1_prob = 0.5,
                top2 = "B", top2_prob = 0.45,
            },
            tau = 0.4,
        })
        expect(d.action).to.equal("escalate")
        expect(d.selected).to.equal(nil)
    end)

    it("anomaly (empty): |C|=0", function()
        local cv = require("conformal_vote")
        local d = cv.decide({
            prediction_set = {
                labels = {},
                top1 = nil, top1_prob = 0.3,
                top2 = nil, top2_prob = 0.2,
            },
            tau = 0.4,
        })
        expect(d.action).to.equal("anomaly")
        expect(d.selected).to.equal(nil)
    end)

    it("anomaly edge: |C|=1 ∧ p1<τ (Proposition 3 edge)", function()
        local cv = require("conformal_vote")
        local d = cv.decide({
            prediction_set = {
                labels = { "A" },
                top1 = "A", top1_prob = 0.3,
                top2 = "B", top2_prob = 0.2,
            },
            tau = 0.4,
        })
        expect(d.action).to.equal("anomaly")
        expect(d.selected).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 6: Monte Carlo coverage guarantee (Theorem 2)
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote — Theorem 2 coverage (Monte Carlo)", function()
    lust.after(reset)

    it("empirical coverage ≥ 1-α - 3σ under synthetic IID data (seed=42)", function()
        local cv = require("conformal_vote")
        math.randomseed(42)

        local options = {}
        for i = 1, 10 do options[i] = string.char(64 + i) end  -- A..J

        -- Generate a calibration/test sample: each of 3 agents places
        -- p_correct ∈ U(0.6, 0.8) on the true label and spreads the
        -- remainder uniformly over the other options. The three agents
        -- are drawn independently per sample to satisfy IID.
        local function gen_sample()
            local true_label = options[math.random(1, #options)]
            local ap = {}
            for a = 1, 3 do
                local p_correct = 0.6 + math.random() * 0.2
                local dist = {}
                local leftover = (1 - p_correct) / (#options - 1)
                for i = 1, #options do
                    local y = options[i]
                    dist[y] = (y == true_label) and p_correct or leftover
                end
                ap[a] = dist
            end
            return { agent_probs = ap, true_label = true_label }
        end

        local cal_set, test_set = {}, {}
        for i = 1, 500 do cal_set[i] = gen_sample() end
        for i = 1, 500 do test_set[i] = gen_sample() end

        local alpha = 0.05
        local cal = cv.calibrate({
            calibration_samples = cal_set,
            alpha = alpha,
        })

        local covered = 0
        for i = 1, #test_set do
            local s = test_set[i]
            local ap_list = {}
            for j = 1, 3 do ap_list[j] = s.agent_probs[j] end
            local p_social = cv.aggregate({
                agent_probs = ap_list,
                weights = cal.weights,
            })
            local pset = cv.predict_set({ p_social = p_social, tau = cal.tau })
            -- y_true ∈ C(x) iff p_social[y_true] >= tau
            if (p_social[s.true_label] or 0) >= cal.tau then
                covered = covered + 1
            end
        end
        local coverage = covered / #test_set
        -- Tolerance 0.92 = 0.95 - 3σ with σ = sqrt(0.05·0.95/500) ≈ 0.00975
        expect(coverage >= 0.92).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 7: decision consistency (commit ⇒ selected != nil)
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.decide — consistency", function()
    lust.after(reset)

    it("commit ⇒ selected != nil; escalate/anomaly ⇒ selected == nil", function()
        local cv = require("conformal_vote")
        local fixtures = {
            { labels = { "X" }, top1 = "X", top1_prob = 0.9, top2 = "Y", top2_prob = 0.05 },
            { labels = { "X", "Y" }, top1 = "X", top1_prob = 0.55, top2 = "Y", top2_prob = 0.45 },
            { labels = {}, top1 = nil, top1_prob = 0.1, top2 = nil, top2_prob = 0.1 },
        }
        local taus = { 0.5, 0.4, 0.5 }
        for i, pset in ipairs(fixtures) do
            local d = cv.decide({ prediction_set = pset, tau = taus[i] })
            if d.action == "commit" then
                expect(d.selected ~= nil).to.equal(true)
            else
                expect(d.selected).to.equal(nil)
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 8: run end-to-end with mocked alc.llm (weights required)
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.run — mocked alc.llm", function()
    lust.after(reset)

    it("commits on high-agreement fixture", function()
        local call_count = 0
        local fixtures = {
            "<answer>\nA: 0.85\nB: 0.10\nC: 0.05\n</answer>",
            "<answer>\nA: 0.80\nB: 0.15\nC: 0.05\n</answer>",
            "<answer>\nA: 0.90\nB: 0.05\nC: 0.05\n</answer>",
        }
        _G.alc = {
            llm = function(_, _)
                call_count = call_count + 1
                return fixtures[call_count]
            end,
            log = setmetatable(
                { warn = function(_) end, info = function(_) end },
                { __call = function(_, _, _) end }
            ),
        }

        local cv = require("conformal_vote")
        local ctx = {
            task = "Demo",
            options = { "A", "B", "C" },
            calibration = {
                q_hat = 0.3, tau = 0.7, alpha = 0.05, n = 100,
                weights = { 1/3, 1/3, 1/3 },  -- weights field required
            },
            agents = { "agent1", "agent2", "agent3" },
        }
        cv.run(ctx)
        expect(ctx.result.action).to.equal("commit")
        expect(ctx.result.selected).to.equal("A")
        expect(ctx.result.total_llm_calls).to.equal(3)
        expect(type(ctx.result.p_social)).to.equal("table")
        expect(type(ctx.result.p_social.A)).to.equal("number")
        expect(ctx.result.coverage_level).to.equal(0.95)
    end)

    it("escalates on ambiguous fixture", function()
        local call_count = 0
        local fixtures = {
            "<answer>\nA: 0.45\nB: 0.45\nC: 0.10\n</answer>",
            "<answer>\nA: 0.50\nB: 0.40\nC: 0.10\n</answer>",
            "<answer>\nA: 0.45\nB: 0.50\nC: 0.05\n</answer>",
        }
        _G.alc = {
            llm = function() call_count = call_count + 1; return fixtures[call_count] end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
        }
        local cv = require("conformal_vote")
        local ctx = {
            task = "Demo2",
            options = { "A", "B", "C" },
            calibration = { q_hat = 0.6, tau = 0.4, alpha = 0.05, n = 100,
                weights = { 1/3, 1/3, 1/3 } },
            agents = { "a1", "a2", "a3" },
        }
        cv.run(ctx)
        expect(ctx.result.action).to.equal("escalate")
        expect(ctx.result.selected).to.equal(nil)
    end)

    it("rejects missing ctx.calibration.weights", function()
        _G.alc = {
            llm = function() return "<answer>A: 1.0</answer>" end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
        }
        local cv = require("conformal_vote")
        local ok, err = pcall(cv.run, {
            task = "X",
            options = { "A" },
            calibration = { q_hat = 0.1, tau = 0.9, alpha = 0.05, n = 10 },
            agents = { "a" },
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("weights") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 9: spec_resolver exclusivity
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.spec_resolver", function()
    lust.after(reset)

    it("pure entries use args (not input); run uses input (not args)", function()
        local cv = require("conformal_vote")
        local S = require("alc_shapes")
        local resolved = S.spec_resolver.resolve(cv)
        expect(resolved.kind).to.equal("typed")
        expect(resolved.entries.calibrate.args ~= nil).to.equal(true)
        expect(resolved.entries.calibrate.input).to.equal(nil)
        expect(resolved.entries.aggregate.args ~= nil).to.equal(true)
        expect(resolved.entries.aggregate.input).to.equal(nil)
        expect(resolved.entries.predict_set.args ~= nil).to.equal(true)
        expect(resolved.entries.predict_set.input).to.equal(nil)
        expect(resolved.entries.decide.args ~= nil).to.equal(true)
        expect(resolved.entries.decide.input).to.equal(nil)
        expect(resolved.entries.run.input ~= nil).to.equal(true)
        expect(resolved.entries.run.args).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 10: conformal_decided shape validates
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_decided shape", function()
    lust.after(reset)

    it("accepts a well-formed run result", function()
        local cv = require("conformal_vote")
        local S = require("alc_shapes")
        local call_count = 0
        local fixtures = {
            "<answer>A: 0.9\nB: 0.05\nC: 0.05</answer>",
            "<answer>A: 0.85\nB: 0.10\nC: 0.05</answer>",
            "<answer>A: 0.80\nB: 0.15\nC: 0.05</answer>",
        }
        _G.alc = {
            llm = function() call_count = call_count + 1; return fixtures[call_count] end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
        }
        local ctx = {
            task = "q",
            options = { "A", "B", "C" },
            calibration = { q_hat = 0.3, tau = 0.7, alpha = 0.05, n = 100,
                weights = { 1/3, 1/3, 1/3 } },
            agents = { "a1", "a2", "a3" },
        }
        cv.run(ctx)
        local ok, reason = S.check(ctx.result, S.conformal_decided)
        if not ok then error("shape check failed: " .. tostring(reason)) end
        expect(ok).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 11: Card emission (auto_card = true)
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote.run — Card emission", function()
    lust.after(reset)

    it("sets ctx.result.card_id from stubbed alc.card.create", function()
        local create_args, sampled_args
        local create_calls, sample_calls = 0, 0
        local fixtures = {
            "<answer>A: 0.9\nB: 0.1</answer>",
            "<answer>A: 0.85\nB: 0.15</answer>",
            "<answer>A: 0.88\nB: 0.12</answer>",
        }
        local call_count = 0
        _G.alc = {
            llm = function() call_count = call_count + 1; return fixtures[call_count] end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
            card = {
                create = function(args)
                    create_calls = create_calls + 1
                    create_args = args
                    return { card_id = "stub_card_42" }
                end,
                write_samples = function(id, list)
                    sample_calls = sample_calls + 1
                    sampled_args = { id = id, list = list }
                end,
            },
        }
        local cv = require("conformal_vote")
        local ctx = {
            task = "q",
            options = { "A", "B" },
            calibration = { q_hat = 0.3, tau = 0.7, alpha = 0.05, n = 100,
                weights = { 1/3, 1/3, 1/3 } },
            agents = { "a1", "a2", "a3" },
            auto_card = true,
        }
        cv.run(ctx)
        expect(ctx.result.card_id).to.equal("stub_card_42")
        expect(create_calls).to.equal(1)
        expect(sample_calls).to.equal(1)
        expect(create_args.pkg.name:sub(1, 15)).to.equal("conformal_vote_")
        expect(sampled_args.id).to.equal("stub_card_42")
        expect(#sampled_args.list).to.equal(3)
    end)

    it("card_pkg override is respected", function()
        _G.alc = {
            llm = function() return "<answer>A: 1.0</answer>" end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
            card = {
                create = function(args) return { card_id = "ok", _name = args.pkg.name } end,
                write_samples = function() end,
            },
        }
        local cv = require("conformal_vote")
        local ctx = {
            task = "q",
            options = { "A" },
            calibration = { q_hat = 0.05, tau = 0.95, alpha = 0.05, n = 10,
                weights = { 1 } },
            agents = { "a" },
            auto_card = true,
            card_pkg = "my_override_pkg",
        }
        cv.run(ctx)
        expect(ctx.result.card_id).to.equal("ok")
    end)

    it("no card_id when auto_card is false", function()
        _G.alc = {
            llm = function() return "<answer>A: 1.0</answer>" end,
            log = setmetatable({ warn = function() end, info = function() end },
                { __call = function() end }),
            card = { create = function() error("should not be called") end },
        }
        local cv = require("conformal_vote")
        local ctx = {
            task = "q",
            options = { "A" },
            calibration = { q_hat = 0.05, tau = 0.95, alpha = 0.05, n = 10,
                weights = { 1 } },
            agents = { "a" },
        }
        cv.run(ctx)
        expect(ctx.result.card_id).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 12: parse_probabilities — uniform fallback (BP §4.6)
-- ═══════════════════════════════════════════════════════════════════

describe("conformal_vote._internal.parse_probabilities", function()
    lust.after(reset)

    it("uniform fallback on garbage response", function()
        local cv = require("conformal_vote")
        local parse = cv._internal.parse_probabilities
        local p, failed = parse("some garbage with no labels", { "A", "B", "C" })
        expect(failed).to.equal(true)
        expect(math.abs(p.A - 1/3) < 1e-9).to.equal(true)
        expect(math.abs(p.B - 1/3) < 1e-9).to.equal(true)
        expect(math.abs(p.C - 1/3) < 1e-9).to.equal(true)
    end)

    it("normalizes non-unit probabilities", function()
        local cv = require("conformal_vote")
        local parse = cv._internal.parse_probabilities
        local p, failed = parse("A: 0.3\nB: 0.3\nC: 0.3", { "A", "B", "C" })
        expect(failed).to.equal(false)
        expect(math.abs(p.A - 1/3) < 1e-9).to.equal(true)
        expect(math.abs(p.B - 1/3) < 1e-9).to.equal(true)
    end)

    it("fills missing labels with zero probability", function()
        local cv = require("conformal_vote")
        local parse = cv._internal.parse_probabilities
        local p, failed = parse("A: 0.8\nB: 0.2", { "A", "B", "C" })
        expect(failed).to.equal(false)
        expect(p.C).to.equal(0)
    end)

    it("strips <answer> tags if present", function()
        local cv = require("conformal_vote")
        local parse = cv._internal.parse_probabilities
        local p, failed = parse(
            "Reasoning noise here\n<answer>\nA: 0.6\nB: 0.4\n</answer>\nmore noise",
            { "A", "B" }
        )
        expect(failed).to.equal(false)
        expect(math.abs(p.A - 0.6) < 1e-9).to.equal(true)
    end)
end)
