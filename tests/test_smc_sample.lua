--- Tests for smc_sample (Markovic-Voronov et al. 2026, arXiv:2604.16453).
---
--- Coverage (issue §10 + §13.3 mathematical rigor):
---   Subtask 1 (pure helpers, this file's first batch):
---     1. compute_weights — α=0 equal-weighted / α=1 / α=4 tempering
---     2. compute_ess — equal weights ⇒ ESS=N
---     3. compute_ess — single-particle domination ⇒ ESS=1
---     4. compute_ess — intermediate distribution numerically verified
---     5. resample_multinomial — deterministic rng picks argmax-prob bucket
---     6. resample_multinomial — preserves N (#out == #in)
---     7. mh_accept — π(x')>π(x) symmetric ⇒ always accept
---     8. mh_accept — π(x')=0 ⇒ always reject
---     9. mh_accept — asymmetric proposal bumps acceptance
---    10. incremental_weight_update — w_prev=1, Δr=1, α=4 ⇒ exp(4)
---    11. α → ∞ limit — only argmax-reward particle retains weight
---   Subtask 2 (M.run orchestration, added alongside LLM mock):
---    12+ reward_fn injection, fail-fast, K-iteration, argmax selection,
---         Card emission spy (nested schema), fail-safe on missing alc.card.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Derive REPO from the first `?.lua` entry already prepended to
-- `package.path` by `mlua-probe-mcp`'s `search_paths` (see
-- tests/test_gen_docs.lua:23-33 and CLAUDE.md §「失敗記録 2026-04-19
-- tests/test_*.lua の REPO 解決規約」). `os.getenv("PWD")` under
-- mlua-probe-mcp points at the server's startup CWD (often the parent
-- repo) and would silently route requires to the wrong worktree.
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

-- Force fresh load of alc_shapes so the worktree's smc_sampled shape is
-- visible even if a prior test run cached the parent-repo version.
for _, name in ipairs({
    "smc_sample",
    "alc_shapes",
    "alc_shapes.t",
    "alc_shapes.check",
    "alc_shapes.reflect",
}) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["smc_sample"] = nil
    _G.alc = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Meta
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local smc = require("smc_sample")
        expect(smc.meta.name).to.equal("smc_sample")
    end)

    it("has version 0.1.0", function()
        local smc = require("smc_sample")
        expect(smc.meta.version).to.equal("0.1.0")
    end)

    it("category is selection", function()
        local smc = require("smc_sample")
        expect(smc.meta.category).to.equal("selection")
    end)

    it("description mentions Sequential Monte Carlo", function()
        local smc = require("smc_sample")
        expect(smc.meta.description:find("Sequential Monte Carlo") ~= nil).to.equal(true)
    end)

    it("defaults match paper §4.1 HumanEval setting", function()
        local smc = require("smc_sample")
        expect(smc._defaults.n_particles).to.equal(16)
        expect(smc._defaults.n_iterations).to.equal(4)
        expect(smc._defaults.alpha).to.equal(4.0)
        expect(smc._defaults.ess_threshold).to.equal(0.5)
        expect(smc._defaults.rejuv_steps).to.equal(2)
        expect(smc._defaults.gen_tokens).to.equal(600)
    end)

    it("exposes _internal pure helpers", function()
        local smc = require("smc_sample")
        expect(type(smc._internal.compute_weights)).to.equal("function")
        expect(type(smc._internal.compute_ess)).to.equal("function")
        expect(type(smc._internal.resample_multinomial)).to.equal("function")
        expect(type(smc._internal.mh_accept)).to.equal("function")
        expect(type(smc._internal.incremental_weight_update)).to.equal("function")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 1: compute_weights — tempering at α=0 / α=1 / α=4
-- ═══════════════════════════════════════════════════════════════════

local function approx(a, b, eps)
    eps = eps or 1e-9
    return math.abs(a - b) <= eps
end

describe("smc_sample.compute_weights", function()
    lust.after(reset)

    it("α=0 ⇒ all particles equal-weighted (1/N)", function()
        local smc = require("smc_sample")
        local rewards = { 0.1, 0.5, 0.9, 0.3 }
        local w = smc._internal.compute_weights(rewards, 0)
        expect(#w).to.equal(4)
        for i = 1, 4 do
            expect(approx(w[i], 0.25, 1e-12)).to.equal(true)
        end
    end)

    it("α=1 ⇒ weights ∝ exp(r_i), normalized", function()
        local smc = require("smc_sample")
        local rewards = { 0, 1, 2 }
        local w = smc._internal.compute_weights(rewards, 1)
        -- Hand-computed reference: exp([0,1,2]) / Σ ≈ [1, 2.718, 7.389] / 11.107
        local denom = math.exp(0) + math.exp(1) + math.exp(2)
        expect(approx(w[1], math.exp(0) / denom, 1e-9)).to.equal(true)
        expect(approx(w[2], math.exp(1) / denom, 1e-9)).to.equal(true)
        expect(approx(w[3], math.exp(2) / denom, 1e-9)).to.equal(true)
        -- Σw ≈ 1
        expect(approx(w[1] + w[2] + w[3], 1, 1e-9)).to.equal(true)
    end)

    it("α=4 ⇒ sharper distribution than α=1", function()
        local smc = require("smc_sample")
        local rewards = { 0, 0.5, 1 }
        local w1 = smc._internal.compute_weights(rewards, 1)
        local w4 = smc._internal.compute_weights(rewards, 4)
        -- Top-reward particle gets more mass at higher α
        expect(w4[3] > w1[3]).to.equal(true)
        -- Lower-reward particle gets less mass at higher α
        expect(w4[1] < w1[1]).to.equal(true)
        -- Both still normalize to 1
        expect(approx(w4[1] + w4[2] + w4[3], 1, 1e-9)).to.equal(true)
    end)

    it("numerically stable at high α (max-shift)", function()
        local smc = require("smc_sample")
        -- Without max-shift, exp(4 * 1000) would be +Inf.
        local rewards = { 0, 1000 }
        local w = smc._internal.compute_weights(rewards, 4)
        expect(approx(w[1] + w[2], 1, 1e-9)).to.equal(true)
        -- Top particle dominates but weight is finite
        expect(w[2] > 0.99).to.equal(true)
    end)

    it("rejects non-table rewards", function()
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.compute_weights, "bad", 1)
        expect(ok).to.equal(false)
        expect(err:find("rewards must be table") ~= nil).to.equal(true)
    end)

    it("rejects empty rewards", function()
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.compute_weights, {}, 1)
        expect(ok).to.equal(false)
        expect(err:find("non%-empty") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 2/3/4: compute_ess — edge cases + intermediate
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.compute_ess", function()
    lust.after(reset)

    it("equal weights (N=4, w=0.25) ⇒ ESS=N=4", function()
        local smc = require("smc_sample")
        local ess = smc._internal.compute_ess({ 0.25, 0.25, 0.25, 0.25 })
        expect(approx(ess, 4, 1e-12)).to.equal(true)
    end)

    it("single-particle domination ⇒ ESS=1", function()
        local smc = require("smc_sample")
        local ess = smc._internal.compute_ess({ 1, 0, 0, 0 })
        expect(approx(ess, 1, 1e-12)).to.equal(true)
    end)

    it("intermediate w=[0.5,0.3,0.1,0.1] ⇒ 1/0.36 ≈ 2.777...", function()
        local smc = require("smc_sample")
        -- (Σw)² = 1, Σw² = 0.25 + 0.09 + 0.01 + 0.01 = 0.36 ⇒ ESS = 1/0.36
        local ess = smc._internal.compute_ess({ 0.5, 0.3, 0.1, 0.1 })
        expect(approx(ess, 1 / 0.36, 1e-9)).to.equal(true)
    end)

    it("equal un-normalized (w=1 each) ⇒ ESS=N", function()
        local smc = require("smc_sample")
        -- ESS formula is scale-invariant: w=[1,1,1] → (3²)/(3) = 3
        local ess = smc._internal.compute_ess({ 1, 1, 1 })
        expect(approx(ess, 3, 1e-12)).to.equal(true)
    end)

    it("all zero weights ⇒ ESS=0 (degenerate, not NaN)", function()
        local smc = require("smc_sample")
        local ess = smc._internal.compute_ess({ 0, 0, 0 })
        expect(ess).to.equal(0)
    end)

    it("rejects non-number weight", function()
        local smc = require("smc_sample")
        local ok = pcall(smc._internal.compute_ess, { 0.5, "bad", 0.5 })
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 5/6: resample_multinomial — deterministic rng + N-preservation
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.resample_multinomial", function()
    lust.after(reset)

    it("deterministic rng → 0.01 picks first bucket under w=[0.9,0.1]", function()
        local smc = require("smc_sample")
        local particles = { "A", "B" }
        local weights   = { 0.9, 0.1 }
        -- draw() returns 0.01 ≤ cdf[1]=0.9 ⇒ always pick A
        local out = smc._internal.resample_multinomial(particles, weights,
            function() return 0.01 end)
        expect(#out).to.equal(2)
        expect(out[1]).to.equal("A")
        expect(out[2]).to.equal("A")
    end)

    it("deterministic rng → 0.95 picks second bucket under w=[0.9,0.1]", function()
        local smc = require("smc_sample")
        local particles = { "A", "B" }
        local weights   = { 0.9, 0.1 }
        -- 0.95 > cdf[1]=0.9 ⇒ picks B (cdf[2]=1.0)
        local out = smc._internal.resample_multinomial(particles, weights,
            function() return 0.95 end)
        expect(out[1]).to.equal("B")
        expect(out[2]).to.equal("B")
    end)

    it("preserves N", function()
        local smc = require("smc_sample")
        local particles = { "a", "b", "c", "d", "e" }
        local weights   = { 0.1, 0.2, 0.4, 0.2, 0.1 }
        -- rng cycling through 0.05, 0.25, 0.5, 0.75, 0.95
        local seq = { 0.05, 0.25, 0.5, 0.75, 0.95 }
        local idx = 0
        local out = smc._internal.resample_multinomial(particles, weights,
            function() idx = idx + 1; return seq[((idx - 1) % #seq) + 1] end)
        expect(#out).to.equal(5)
    end)

    it("rejects #weights != #particles", function()
        local smc = require("smc_sample")
        local ok = pcall(smc._internal.resample_multinomial,
            { "a", "b" }, { 0.5 })
        expect(ok).to.equal(false)
    end)

    it("rejects Σweights == 0", function()
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.resample_multinomial,
            { "a", "b" }, { 0, 0 })
        expect(ok).to.equal(false)
        expect(err:find("must be > 0") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 7/8/9: mh_accept — symmetric / zero-π / asymmetric
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.mh_accept", function()
    lust.after(reset)

    -- Deterministic coverage: in a symmetric proposal with π(x')>π(x),
    -- ratio > 1 so min(1, ratio) == 1 and math.random() < 1 always.
    it("π(x')>π(x) symmetric ⇒ always accept (many trials)", function()
        local smc = require("smc_sample")
        for _ = 1, 50 do
            expect(smc._internal.mh_accept(0.2, 0.8, 1.0, 1.0)).to.equal(true)
        end
    end)

    it("π(x')==0 ⇒ always reject (many trials)", function()
        local smc = require("smc_sample")
        for _ = 1, 50 do
            expect(smc._internal.mh_accept(0.5, 0, 1.0, 1.0)).to.equal(false)
        end
    end)

    it("π(x)==0 ⇒ always reject (ratio undefined, treat as reject)", function()
        local smc = require("smc_sample")
        expect(smc._internal.mh_accept(0, 0.5, 1.0, 1.0)).to.equal(false)
    end)

    it("asymmetric proposal: q_x_given_xprime >> q_xprime_given_x bumps ratio", function()
        local smc = require("smc_sample")
        -- With π(x)=π(x')=0.5 and asymmetric q (20x boost), ratio=20 > 1 ⇒ accept
        for _ = 1, 50 do
            expect(smc._internal.mh_accept(0.5, 0.5, 20.0, 1.0)).to.equal(true)
        end
    end)

    it("rejects non-number args", function()
        local smc = require("smc_sample")
        local ok = pcall(smc._internal.mh_accept, "bad", 0.5, 1, 1)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 10: incremental_weight_update — Target I formula
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.incremental_weight_update", function()
    lust.after(reset)

    it("w_prev=1, r_new=1, r_prev=0, α=4 ⇒ exp(4) ≈ 54.598", function()
        local smc = require("smc_sample")
        local w = smc._internal.incremental_weight_update(1, 1, 0, 4)
        expect(approx(w, math.exp(4), 1e-9)).to.equal(true)
    end)

    it("Δr=0 ⇒ weight unchanged (identity update)", function()
        local smc = require("smc_sample")
        local w = smc._internal.incremental_weight_update(0.25, 0.7, 0.7, 4)
        expect(approx(w, 0.25, 1e-12)).to.equal(true)
    end)

    it("Δr<0 ⇒ weight shrinks", function()
        local smc = require("smc_sample")
        local w = smc._internal.incremental_weight_update(1, 0, 1, 4)
        -- exp(-4) ≈ 0.01831563...
        expect(approx(w, math.exp(-4), 1e-12)).to.equal(true)
    end)

    it("α=0 ⇒ weight unchanged regardless of Δr", function()
        local smc = require("smc_sample")
        local w = smc._internal.incremental_weight_update(0.42, 10, -5, 0)
        expect(approx(w, 0.42, 1e-12)).to.equal(true)
    end)

    it("rejects non-number args", function()
        local smc = require("smc_sample")
        local ok = pcall(smc._internal.incremental_weight_update, "bad", 1, 0, 4)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 11: α limit behavior — α=0 uniform / α=1000 argmax-only
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample α limit behavior", function()
    lust.after(reset)

    it("α=0 collapses compute_weights to uniform", function()
        local smc = require("smc_sample")
        local w = smc._internal.compute_weights({ 0.1, 0.9, 0.5 }, 0)
        for i = 1, 3 do
            expect(approx(w[i], 1 / 3, 1e-12)).to.equal(true)
        end
    end)

    it("α=1000 concentrates mass on argmax reward", function()
        local smc = require("smc_sample")
        -- rewards[2] is strictly largest ⇒ after tempering it dominates
        local w = smc._internal.compute_weights({ 0.1, 0.9, 0.5 }, 1000)
        -- argmax bucket has ~1.0 mass; others underflow to ~0.
        expect(w[2] > 0.99).to.equal(true)
        expect(w[1] < 1e-100).to.equal(true)
        expect(w[3] < 1e-100).to.equal(true)
        -- Σ still 1 after max-shift
        expect(approx(w[1] + w[2] + w[3], 1, 1e-9)).to.equal(true)
    end)

    it("α=0 in incremental_weight_update is a no-op", function()
        local smc = require("smc_sample")
        local w = smc._internal.incremental_weight_update(0.7, 5, -2, 0)
        expect(approx(w, 0.7, 1e-12)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Shape registration — smc_sampled validates (spec_resolver sanity)
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample shape registration", function()
    lust.after(reset)

    it("alc_shapes.smc_sampled is a shape", function()
        local S = require("alc_shapes")
        expect(S.is_schema(S.smc_sampled)).to.equal(true)
    end)

    it("smc_sampled accepts a valid minimal result", function()
        local S = require("alc_shapes")
        local ok = S.check({
            answer = "42",
            particles = {
                {
                    answer  = "42",
                    weight  = 1.0,
                    reward  = 0.9,
                    history = {},
                },
            },
            weights        = { 1.0 },
            iterations     = 1,
            resample_count = 0,
            ess_trace      = { 1 },
            stats = {
                total_llm_calls    = 1,
                total_reward_calls = 1,
            },
        }, S.smc_sampled)
        expect(ok).to.equal(true)
    end)

    it("smc_sampled rejects missing required field", function()
        local S = require("alc_shapes")
        local ok = S.check({
            -- answer missing
            particles = {},
            weights = {},
            iterations = 0,
            resample_count = 0,
            ess_trace = {},
            stats = { total_llm_calls = 0, total_reward_calls = 0 },
        }, S.smc_sampled)
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Subtask 2 — LLM-integrated tests (mocked _G.alc)
-- ═══════════════════════════════════════════════════════════════════
--
-- Mock conventions (tests/test_conformal_vote.lua:569-584 pattern):
--   * _G.alc.llm : function — returns the next canned response
--   * _G.alc.map : serial implementation so ordering is deterministic
--   * _G.alc.log : { warn, info } sinks (silent)
--   * _G.alc.card : { create, write_samples } spies for Card emission
--   * _G.alc.hash : stub hasher (so pkg_name is deterministic)
--
-- Every describe() resets via lust.after(reset) so _G.alc leaks between
-- blocks can't cross-contaminate.

-- Helper: build a deterministic alc stub. `fixtures` is either a list
-- (consumed in order) or a function(prompt, opts, call_idx) -> string.
-- Returns the stub table AND the counter table so tests can read the
-- call count without exposing implementation via upvalue hacks.
local function make_alc_stub(opts)
    opts = opts or {}
    local counter = { llm_calls = 0 }
    local fixtures = opts.fixtures
    local llm_fn
    if type(fixtures) == "function" then
        llm_fn = function(prompt, o)
            counter.llm_calls = counter.llm_calls + 1
            return fixtures(prompt, o, counter.llm_calls)
        end
    elseif type(fixtures) == "table" then
        llm_fn = function(_prompt, _o)
            counter.llm_calls = counter.llm_calls + 1
            local v = fixtures[counter.llm_calls]
            if v == nil then v = "default_response_" .. tostring(counter.llm_calls) end
            return v
        end
    else
        llm_fn = function(_prompt, _o)
            counter.llm_calls = counter.llm_calls + 1
            return "stub_answer_" .. tostring(counter.llm_calls)
        end
    end

    local stub = {
        llm = llm_fn,
        map = function(collection, fn)
            local out = {}
            for i, v in ipairs(collection) do out[i] = fn(v, i) end
            return out
        end,
        log = {
            warn = function(...) end,
            info = function(...) end,
        },
        hash = function(s) return "deadbeef" .. tostring(#s) end,
    }
    if opts.with_card then
        local card_state = { create_calls = 0, samples_calls = 0 }
        stub.card = {
            create = function(args)
                card_state.create_calls = card_state.create_calls + 1
                card_state.last_args = args
                return { card_id = opts.card_id or "stub_card_7" }
            end,
            write_samples = function(id, list)
                card_state.samples_calls = card_state.samples_calls + 1
                card_state.last_id = id
                card_state.last_list = list
            end,
        }
        counter.card = card_state
    end
    return stub, counter
end

-- ═══════════════════════════════════════════════════════════════════
-- Test 12: init_particles — N parallel LLM calls, unique answers
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample._internal.init_particles (mocked alc.llm)", function()
    lust.after(reset)

    it("produces N particles, one per LLM call, each with history={}", function()
        local stub, counter = make_alc_stub({
            fixtures = { "ans_1", "ans_2", "ans_3", "ans_4" },
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local particles = smc._internal.init_particles("task-prompt", 4, 123)
        expect(#particles).to.equal(4)
        expect(counter.llm_calls).to.equal(4)
        for i = 1, 4 do
            expect(particles[i].answer).to.equal("ans_" .. tostring(i))
            expect(type(particles[i].history)).to.equal("table")
            expect(#particles[i].history).to.equal(0)
        end
    end)

    it("coerces nil / non-string LLM response to empty-string safely", function()
        -- Fixture function returns nil on the first call so we can
        -- verify init_particles coerces nil → "" via tostring(... or "").
        local call = 0
        local stub = {
            llm = function()
                call = call + 1
                if call == 1 then return nil end
                return "ok"
            end,
            map = function(coll, fn)
                local out = {}
                for i, v in ipairs(coll) do out[i] = fn(v, i) end
                return out
            end,
            log = { warn = function() end, info = function() end },
        }
        _G.alc = stub
        local smc = require("smc_sample")
        local particles = smc._internal.init_particles("t", 2, 100)
        expect(particles[1].answer).to.equal("")  -- nil → ""
        expect(particles[2].answer).to.equal("ok")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 13: evaluate_rewards — reward_fn injection, fail-fast policy
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample._internal.evaluate_rewards (reward_fn injection)", function()
    lust.after(reset)

    it("calls reward_fn for each particle with (answer, task)", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local particles = {
            { answer = "a", history = {} },
            { answer = "b", history = {} },
            { answer = "c", history = {} },
        }
        local seen = {}
        local reward_fn = function(answer, task)
            seen[#seen + 1] = { answer = answer, task = task }
            return #answer / 10
        end
        local rewards, n_calls = smc._internal.evaluate_rewards(particles, "my-task", reward_fn)
        expect(#rewards).to.equal(3)
        expect(n_calls).to.equal(3)
        expect(#seen).to.equal(3)
        for i = 1, 3 do
            expect(seen[i].task).to.equal("my-task")
        end
        expect(seen[1].answer).to.equal("a")
        expect(seen[2].answer).to.equal("b")
        expect(seen[3].answer).to.equal("c")
    end)

    it("fail-fast: reward_fn error propagates (no silent weight=0)", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.evaluate_rewards,
            { { answer = "a", history = {} } },
            "task",
            function() error("reward_fn exploded") end)
        expect(ok).to.equal(false)
        expect(err:find("reward_fn failed for particle") ~= nil).to.equal(true)
    end)

    it("fail-fast: NaN reward rejected", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.evaluate_rewards,
            { { answer = "a", history = {} } },
            "task",
            function() return 0 / 0 end)
        expect(ok).to.equal(false)
        expect(err:find("NaN") ~= nil).to.equal(true)
    end)

    it("fail-fast: negative reward rejected (contract: r ∈ [0, +∞))", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.evaluate_rewards,
            { { answer = "a", history = {} } },
            "task",
            function() return -0.5 end)
        expect(ok).to.equal(false)
        expect(err:find("negative") ~= nil).to.equal(true)
    end)

    it("fail-fast: +Inf reward rejected", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.evaluate_rewards,
            { { answer = "a", history = {} } },
            "task",
            function() return math.huge end)
        expect(ok).to.equal(false)
        expect(err:find("%+Inf") ~= nil).to.equal(true)
    end)

    it("fail-fast: non-number reward rejected", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc._internal.evaluate_rewards,
            { { answer = "a", history = {} } },
            "task",
            function() return "not-a-number" end)
        expect(ok).to.equal(false)
        expect(err:find("non%-number") ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 14: mh_rejuvenate — S step semantics, reject path, counters
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample._internal.mh_rejuvenate (one MH step)", function()
    lust.after(reset)

    it("returns 5 values (new_parts, new_rews, n_llm, n_rew, n_rej)", function()
        local stub, _c = make_alc_stub({
            fixtures = { "refined_1", "refined_2" },
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local particles = {
            { answer = "p1", history = {} },
            { answer = "p2", history = {} },
        }
        local rewards = { 0.1, 0.1 }
        local new_parts, new_rews, n_llm, n_rew, n_rej =
            smc._internal.mh_rejuvenate(particles, rewards, 4.0, "task", 100,
                function(_a, _t) return 0.9 end)
        expect(#new_parts).to.equal(2)
        expect(#new_rews).to.equal(2)
        expect(n_llm).to.equal(2)
        expect(n_rew).to.equal(2)
        expect(type(n_rej)).to.equal("number")
    end)

    it("LLM failure on proposal → that slot is rejected (kept prev)", function()
        -- First LLM call fails (error), second returns an answer.
        local call = 0
        local stub = {
            llm = function()
                call = call + 1
                if call == 1 then error("llm down") end
                return "refined_ok"
            end,
            map = function(coll, fn)
                local out = {}
                for i, v in ipairs(coll) do out[i] = fn(v, i) end
                return out
            end,
            log = { warn = function() end, info = function() end },
        }
        _G.alc = stub
        local smc = require("smc_sample")
        local particles = {
            { answer = "old_1", history = {} },
            { answer = "old_2", history = {} },
        }
        local rewards = { 0.1, 0.1 }
        -- reward_fn returns high reward for refined answer so we know
        -- MH would otherwise accept slot 2.
        local reward_fn = function(a, _t)
            if a == "refined_ok" then return 0.95 end
            return 0.1
        end
        local new_parts, new_rews, n_llm, n_rew, n_rej =
            smc._internal.mh_rejuvenate(particles, rewards, 4.0, "task", 100, reward_fn)
        -- Slot 1: proposal failed → kept old_1, counted as reject
        expect(new_parts[1].answer).to.equal("old_1")
        expect(new_rews[1]).to.equal(0.1)
        -- Slot 2: proposal succeeded with high reward → always accepted (ratio > 1)
        expect(new_parts[2].answer).to.equal("refined_ok")
        expect(new_rews[2]).to.equal(0.95)
        -- Counters
        expect(n_llm).to.equal(1)  -- only slot 2 made a successful LLM call
        expect(n_rew).to.equal(2)  -- reward is always evaluated for both slots
        expect(n_rej >= 1).to.equal(true)  -- at least slot 1 rejected
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 15: M.run orchestration — K-iteration, counters, argmax
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.run (M.run end-to-end, mocked alc)", function()
    lust.after(reset)

    it("K=2, S=1, N=2: total_llm_calls == N + K·S·N = 6", function()
        local stub, counter = make_alc_stub({
            fixtures = function(_p, _o, i) return "answer_" .. tostring(i) end,
        })
        _G.alc = stub
        local smc = require("smc_sample")
        -- Constant reward across all particles → MH accept is a fair
        -- coin (ratio=1). We only care about the call-count invariant.
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.5 end,
            n_particles  = 2,
            n_iterations = 2,
            rejuv_steps  = 1,
            alpha        = 4.0,
        }
        smc.run(ctx)
        -- Paper §10 comment: N + K·N·(1+S) assumes reward_fn is itself
        -- an LLM call. Our mock reward_fn is a pure Lua closure, so
        -- total_llm_calls counts only actual alc.llm() invocations:
        -- init N + per iteration (S proposals × N particles).
        expect(ctx.result.stats.total_llm_calls).to.equal(2 + 2 * 1 * 2)
        expect(counter.llm_calls).to.equal(6)
        -- Reward calls: init N + per iter S·N
        expect(ctx.result.stats.total_reward_calls).to.equal(2 + 2 * 1 * 2)
    end)

    it("K=0 edge case: init-only, no MH, no resample", function()
        local stub, counter = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.5 end,
            n_particles  = 3,
            n_iterations = 0,
            rejuv_steps  = 2,
            alpha        = 4.0,
        }
        smc.run(ctx)
        expect(ctx.result.iterations).to.equal(0)
        expect(ctx.result.resample_count).to.equal(0)
        expect(#ctx.result.ess_trace).to.equal(0)
        expect(counter.llm_calls).to.equal(3)  -- init only
        expect(ctx.result.stats.total_llm_calls).to.equal(3)
        expect(#ctx.result.particles).to.equal(3)
    end)

    it("N=1 edge case: single particle, argmax is that particle", function()
        local stub, _c = make_alc_stub({ fixtures = { "only_answer" } })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.8 end,
            n_particles  = 1,
            n_iterations = 0,  -- skip K loop so the single fixture is enough
            rejuv_steps  = 0,
            alpha        = 4.0,
        }
        smc.run(ctx)
        expect(ctx.result.answer).to.equal("only_answer")
        expect(#ctx.result.particles).to.equal(1)
        expect(#ctx.result.weights).to.equal(1)
        expect(approx(ctx.result.weights[1], 1.0, 1e-12)).to.equal(true)
    end)

    it("α=0 limit: ESS stays = N (all weights remain 1/N after incr update)", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task          = "t",
            reward_fn     = function() return 0.3 end,  -- constant
            n_particles   = 4,
            n_iterations  = 2,
            rejuv_steps   = 0,           -- skip MH so weights stay exact
            alpha         = 0,
            ess_threshold = 0,           -- never resample
        }
        smc.run(ctx)
        -- α=0 in incremental_weight_update is a no-op, weights stay 1/4
        for i = 1, 4 do
            expect(approx(ctx.result.weights[i], 1/4, 1e-12)).to.equal(true)
        end
        -- ESS trace entries should all equal N
        for _, e in ipairs(ctx.result.ess_trace) do
            expect(approx(e, 4, 1e-9)).to.equal(true)
        end
        expect(ctx.result.resample_count).to.equal(0)
    end)

    it("argmax selection: highest-reward particle wins", function()
        -- Fixture: 3 init answers; reward_fn scores them 0.1 / 0.2 / 0.9.
        -- With α=4 and no MH, weights are sharply concentrated on #3 and
        -- the argmax should be particle 3's answer.
        local stub, _c = make_alc_stub({
            fixtures = { "low", "mid", "high" },
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function(a, _t)
                if a == "low" then return 0.1
                elseif a == "mid" then return 0.2
                elseif a == "high" then return 0.9
                end
                return 0
            end,
            n_particles  = 3,
            n_iterations = 0,  -- static: no MH can displace 'high'
            rejuv_steps  = 0,
            alpha        = 4.0,
        }
        smc.run(ctx)
        expect(ctx.result.answer).to.equal("high")
    end)

    it("fail-fast: reward_fn raising error halts M.run", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ok, err = pcall(smc.run, {
            task = "t",
            reward_fn = function() error("verifier crashed") end,
            n_particles = 2,
            n_iterations = 1,
            rejuv_steps = 1,
            alpha = 4.0,
        })
        expect(ok).to.equal(false)
        expect(err:find("reward_fn failed") ~= nil).to.equal(true)
    end)

    it("missing ctx.task error", function()
        _G.alc = make_alc_stub()
        local smc = require("smc_sample")
        local ok, err = pcall(smc.run, { reward_fn = function() return 0.5 end })
        expect(ok).to.equal(false)
        expect(err:find("ctx.task is required") ~= nil).to.equal(true)
    end)

    it("missing ctx.reward_fn error", function()
        _G.alc = make_alc_stub()
        local smc = require("smc_sample")
        local ok, err = pcall(smc.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err:find("ctx.reward_fn is required") ~= nil).to.equal(true)
    end)

    it("ctx.reward_fn as non-function rejected", function()
        _G.alc = make_alc_stub()
        local smc = require("smc_sample")
        local ok, err = pcall(smc.run, { task = "t", reward_fn = 42 })
        expect(ok).to.equal(false)
        expect(err:find("reward_fn") ~= nil).to.equal(true)
    end)

    it("ctx.result validates against smc_sampled shape", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local S = require("alc_shapes")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.4 end,
            n_particles  = 3,
            n_iterations = 1,
            rejuv_steps  = 1,
            alpha        = 4.0,
        }
        smc.run(ctx)
        local ok = S.check(ctx.result, S.smc_sampled)
        expect(ok).to.equal(true)
    end)

    it("weights remain normalized after K iterations", function()
        local stub, _c = make_alc_stub()
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function(a, _t) return (#a % 5) / 10 end,
            n_particles  = 4,
            n_iterations = 3,
            rejuv_steps  = 1,
            alpha        = 4.0,
        }
        smc.run(ctx)
        local sum = 0
        for i = 1, #ctx.result.weights do sum = sum + ctx.result.weights[i] end
        expect(approx(sum, 1, 1e-9)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 16: Card emission — nested schema spy, override, fail-safe
-- ═══════════════════════════════════════════════════════════════════

describe("smc_sample.run — Card emission (auto_card spy)", function()
    lust.after(reset)

    it("auto_card=true emits card with nested schema (pkg/scenario/params/stats/smc_sample)", function()
        local stub, counter = make_alc_stub({
            fixtures = { "a1", "a2" },
            with_card = true,
            card_id = "stub_card_7",
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task          = "hello",
            reward_fn     = function() return 0.5 end,
            n_particles   = 2,
            n_iterations  = 1,
            rejuv_steps   = 1,
            alpha         = 4.0,
            auto_card     = true,
            scenario_name = "unit_test_scn",
        }
        smc.run(ctx)
        expect(counter.card.create_calls).to.equal(1)
        expect(counter.card.samples_calls).to.equal(1)
        expect(ctx.result.card_id).to.equal("stub_card_7")
        local args = counter.card.last_args
        -- nested schema (NOT a 'body' key — see issue §13.2)
        expect(args.body).to.equal(nil)
        expect(type(args.pkg)).to.equal("table")
        expect(type(args.pkg.name)).to.equal("string")
        -- Default pkg_name format is "smc_sample_<hash_prefix>" per
        -- implementation (smc_sample/init.lua:589). Match the fixed 11-char
        -- prefix "smc_sample_" (10 letters + underscore).
        expect(args.pkg.name:sub(1, 11)).to.equal("smc_sample_")
        expect(args.scenario.name).to.equal("unit_test_scn")
        expect(type(args.params)).to.equal("table")
        expect(args.params.n_particles).to.equal(2)
        expect(args.params.n_iterations).to.equal(1)
        expect(args.params.alpha).to.equal(4.0)
        expect(type(args.stats)).to.equal("table")
        expect(args.stats.total_llm_calls).to.equal(ctx.result.stats.total_llm_calls)
        expect(type(args.smc_sample)).to.equal("table")
        expect(args.smc_sample.n_particles).to.equal(2)
        expect(args.smc_sample.alpha).to.equal(4.0)
        -- Tier 2 samples
        expect(counter.card.last_id).to.equal("stub_card_7")
        expect(#counter.card.last_list).to.equal(2)
        expect(counter.card.last_list[1].particle_idx).to.equal(1)
        expect(counter.card.last_list[2].particle_idx).to.equal(2)
    end)

    it("auto_card=false (default) → no card emission", function()
        local stub, counter = make_alc_stub({
            fixtures = { "a" },
            with_card = true,
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task        = "t",
            reward_fn   = function() return 0.3 end,
            n_particles = 1,
            n_iterations = 0,
            rejuv_steps = 0,
        }
        smc.run(ctx)
        expect(counter.card.create_calls).to.equal(0)
        expect(counter.card.samples_calls).to.equal(0)
        expect(ctx.result.card_id).to.equal(nil)
    end)

    it("card_pkg override: pkg.name == ctx.card_pkg verbatim", function()
        local stub, counter = make_alc_stub({
            fixtures = { "x" },
            with_card = true,
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.4 end,
            n_particles  = 1,
            n_iterations = 0,
            rejuv_steps  = 0,
            alpha        = 4.0,
            auto_card    = true,
            card_pkg     = "my_override_pkg",
        }
        smc.run(ctx)
        expect(counter.card.create_calls).to.equal(1)
        expect(counter.card.last_args.pkg.name).to.equal("my_override_pkg")
    end)

    it("fail-safe: alc.card absent → auto_card emits warn log and card_id=nil", function()
        local stub, _c = make_alc_stub({ fixtures = { "only" } })
        -- intentionally omit stub.card
        local warn_msgs = {}
        stub.log = {
            warn = function(m) warn_msgs[#warn_msgs + 1] = tostring(m) end,
            info = function() end,
        }
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.5 end,
            n_particles  = 1,
            n_iterations = 0,
            rejuv_steps  = 0,
            alpha        = 4.0,
            auto_card    = true,
        }
        smc.run(ctx)
        expect(ctx.result.card_id).to.equal(nil)
        -- A warn must have been emitted about alc.card being unavailable
        local matched = false
        for _, m in ipairs(warn_msgs) do
            if m:find("alc%.card unavailable") then matched = true; break end
        end
        expect(matched).to.equal(true)
    end)

    it("scenario_name omitted → defaults to 'unknown'", function()
        local stub, counter = make_alc_stub({
            fixtures = { "only" },
            with_card = true,
        })
        _G.alc = stub
        local smc = require("smc_sample")
        local ctx = {
            task         = "t",
            reward_fn    = function() return 0.5 end,
            n_particles  = 1,
            n_iterations = 0,
            rejuv_steps  = 0,
            alpha        = 4.0,
            auto_card    = true,
        }
        smc.run(ctx)
        expect(counter.card.last_args.scenario.name).to.equal("unknown")
    end)
end)
