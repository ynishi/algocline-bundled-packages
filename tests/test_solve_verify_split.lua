--- Tests for solve_verify_split (compute-optimal SC vs GenRM split).
--- Pure computation — no LLM mocking.
---
--- Reference: Singhi et al. "When To Solve, When To Verify"
--- (arXiv:2504.01005, COLM 2025).

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function reset()
    package.loaded["solve_verify_split"] = nil
end

local function approx_eq(a, b, eps)
    eps = eps or 1e-9
    if math.abs(a - b) <= eps then return true end
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- Toy params: §5.2 Llama-3.1-8B + GenRM-FT + MATH transferred
-- ═══════════════════════════════════════════════════════════════════
local function PAPER_PARAMS()
    return {
        lambda = 2.0,
        exponent_solve = 0.57,
        exponent_verify = 0.39,
        prefactor_solve = 1.0,
        prefactor_verify = 1.0,
    }
end

-- ═══════════════════════════════════════════════════════════════════
-- meta
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.meta", function()
    lust.after(reset)

    it("has correct name", function()
        local svs = require("solve_verify_split")
        expect(svs.meta.name).to.equal("solve_verify_split")
    end)

    it("has version 0.1.0", function()
        local svs = require("solve_verify_split")
        expect(svs.meta.version).to.equal("0.1.0")
    end)

    it("category is orchestration", function()
        local svs = require("solve_verify_split")
        expect(svs.meta.category).to.equal("orchestration")
    end)

    it("description mentions Singhi paper / arXiv:2504.01005", function()
        local svs = require("solve_verify_split")
        local d = svs.meta.description
        expect(d:find("2504.01005") ~= nil
            or d:find("Singhi") ~= nil
            or d:find("Compute%-optimal") ~= nil
            or d:find("compute%-optimal") ~= nil).to.equal(true)
    end)

    it("exposes 5 entries", function()
        local svs = require("solve_verify_split")
        expect(type(svs.cost)).to.equal("function")
        expect(type(svs.score_split)).to.equal("function")
        expect(type(svs.optimal_split)).to.equal("function")
        expect(type(svs.sc_pure)).to.equal("function")
        expect(type(svs.compare_paths)).to.equal("function")
    end)

    it("has paper-faithful defaults (§5.2 / §3.1)", function()
        local svs = require("solve_verify_split")
        expect(svs._defaults.lambda).to.equal(1.0)
        expect(svs._defaults.exponent_solve).to.equal(0.57)
        expect(svs._defaults.exponent_verify).to.equal(0.39)
        expect(svs._defaults.integer_method).to.equal("round")
        expect(svs._defaults.rescale_method).to.equal("scale_proportional")
        expect(svs._defaults.sc_fallback_when_v_zero).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- cost (§3.1 hand-computed fixtures)
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.cost positive", function()
    lust.after(reset)

    it("SC pure: C(16, 0, λ=1) = 16", function()
        local svs = require("solve_verify_split")
        expect(svs.cost(16, 0, 1.0)).to.equal(16)
    end)

    it("Equal-token: C(4, 3, λ=1) = 16", function()
        local svs = require("solve_verify_split")
        expect(svs.cost(4, 3, 1.0)).to.equal(16)
    end)

    it("GenRM-FT (λ=2): C(4, 1, λ=2) = 12", function()
        local svs = require("solve_verify_split")
        expect(svs.cost(4, 1, 2.0)).to.equal(12)
    end)

    it("GenRM-FT (λ=2): C(2, 3, λ=2) = 14", function()
        local svs = require("solve_verify_split")
        expect(svs.cost(2, 3, 2.0)).to.equal(14)
    end)
end)

describe("solve_verify_split.cost errors", function()
    lust.after(reset)

    it("negative S errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.cost(-1, 0, 1.0) end).to.fail()
    end)

    it("negative V errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.cost(1, -1, 1.0) end).to.fail()
    end)

    it("non-positive lambda errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.cost(1, 1, 0) end).to.fail()
        expect(function() svs.cost(1, 1, -1.0) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- score_split
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.score_split positive", function()
    lust.after(reset)

    it("returns cost only when params has lambda only", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(4, 3, { lambda = 1.0 })
        expect(r.cost).to.equal(16)
        expect(r.power_law_score_proxy).to_not.exist()
    end)

    it("includes is_within when budget given", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(4, 3, { lambda = 1.0 }, { budget = 16 })
        expect(r.is_within).to.equal(true)
        local r2 = svs.score_split(4, 3, { lambda = 1.0 }, { budget = 15 })
        expect(r2.is_within).to.equal(false)
    end)

    it("includes power_law_score_proxy when full params given (V > 0)", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(4, 3, PAPER_PARAMS())
        expect(type(r.power_law_score_proxy)).to.equal("number")
        expect(r.power_law_score_proxy > 0).to.equal(true)
    end)

    it("power_law_score_proxy is nil when V = 0 (SC pure path)", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(4, 0, PAPER_PARAMS())
        expect(r.power_law_score_proxy).to_not.exist()
    end)
end)

describe("solve_verify_split.score_split errors", function()
    lust.after(reset)

    it("missing params errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.score_split(4, 3, nil) end).to.fail()
    end)

    it("missing lambda errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.score_split(4, 3, {}) end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- optimal_split (paper-faithful)
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.optimal_split paper-faithful", function()
    lust.after(reset)

    it("B=100, paper params: cost_used ≤ B + raw recorded", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS())
        expect(r.cost_used <= 100).to.equal(true)
        expect(approx_eq(r.raw.s_raw, 100 ^ 0.57, 1e-6)).to.equal(true)
        expect(approx_eq(r.raw.v_raw, 100 ^ 0.39, 1e-6)).to.equal(true)
    end)

    it("B=100, paper params: rescale fired (raw 14·13=182 > 100)", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS())
        expect(r.rescaled).to.equal(true)
    end)

    it("integer_method='round' is the default and recorded", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS())
        expect(r.integer_method).to.equal("round")
    end)

    it("lambda echoed in result", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS())
        expect(r.lambda).to.equal(2.0)
    end)
end)

describe("solve_verify_split.optimal_split rescale strategies", function()
    lust.after(reset)

    it("scale_proportional preserves both axes weakly", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS(),
            { rescale_method = "scale_proportional" })
        expect(r.rescale_method).to.equal("scale_proportional")
        expect(r.cost_used <= 100).to.equal(true)
        expect(r.s_opt >= 1).to.equal(true)
    end)

    it("prefer_solve keeps S, shrinks V first", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS(),
            { rescale_method = "prefer_solve" })
        expect(r.rescale_method).to.equal("prefer_solve")
        expect(r.cost_used <= 100).to.equal(true)
    end)

    it("prefer_verify keeps V, shrinks S first", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, PAPER_PARAMS(),
            { rescale_method = "prefer_verify" })
        expect(r.rescale_method).to.equal("prefer_verify")
        expect(r.cost_used <= 100).to.equal(true)
    end)
end)

describe("solve_verify_split.optimal_split SC fallback", function()
    lust.after(reset)

    it("very small B + tiny prefactor_verify → V_raw rounds to 0 → SC pure", function()
        local svs = require("solve_verify_split")
        -- prefactor_verify=0.01 keeps V_raw small enough to round to 0 at B=4.
        local p = PAPER_PARAMS()
        p.prefactor_verify = 0.01
        local r = svs.optimal_split(4, p)
        expect(r.is_sc_fallback).to.equal(true)
        expect(r.v_opt).to.equal(0)
    end)

    it("sc_fallback_when_v_zero=false keeps V=0 without SC takeover", function()
        local svs = require("solve_verify_split")
        local p = PAPER_PARAMS()
        p.prefactor_verify = 0.01
        local r = svs.optimal_split(4, p, { sc_fallback_when_v_zero = false })
        expect(r.is_sc_fallback).to.equal(false)
        expect(r.v_opt).to.equal(0)
    end)
end)

describe("solve_verify_split.optimal_split errors", function()
    lust.after(reset)

    it("B = 0 errors (paper §3.1 needs positive C)", function()
        local svs = require("solve_verify_split")
        expect(function() svs.optimal_split(0, PAPER_PARAMS()) end).to.fail()
    end)

    it("B < 0 errors", function()
        local svs = require("solve_verify_split")
        expect(function() svs.optimal_split(-1, PAPER_PARAMS()) end).to.fail()
    end)

    it("B = 0.5 errors (B must be >= 1)", function()
        local svs = require("solve_verify_split")
        expect(function() svs.optimal_split(0.5, PAPER_PARAMS()) end).to.fail()
    end)

    it("exponent_solve >= 1 errors (must satisfy 0 < a < 1)", function()
        local svs = require("solve_verify_split")
        local p = {
            lambda = 1.0,
            exponent_solve = 5.7,
            exponent_verify = 0.4,
            prefactor_solve = 1.0,
            prefactor_verify = 1.0,
        }
        expect(function() svs.optimal_split(100, p) end).to.fail()
    end)

    it("missing prefactor_solve errors (caller-fit required)", function()
        local svs = require("solve_verify_split")
        local p = PAPER_PARAMS()
        p.prefactor_solve = nil
        expect(function() svs.optimal_split(100, p) end).to.fail()
    end)

    it("missing prefactor_verify errors", function()
        local svs = require("solve_verify_split")
        local p = PAPER_PARAMS()
        p.prefactor_verify = nil
        expect(function() svs.optimal_split(100, p) end).to.fail()
    end)

    it("invalid integer_method errors", function()
        local svs = require("solve_verify_split")
        expect(function()
            svs.optimal_split(100, PAPER_PARAMS(), { integer_method = "trunc" })
        end).to.fail()
    end)

    it("invalid rescale_method errors", function()
        local svs = require("solve_verify_split")
        expect(function()
            svs.optimal_split(100, PAPER_PARAMS(), { rescale_method = "magic" })
        end).to.fail()
    end)

    it("cost_model='independent' errors (NOT paper-faithful, not in v1)", function()
        local svs = require("solve_verify_split")
        expect(function()
            svs.optimal_split(100, PAPER_PARAMS(), { cost_model = "independent" })
        end).to.fail()
    end)
end)

describe("solve_verify_split.optimal_split invariants", function()
    lust.after(reset)

    it("cost_used ≤ B always", function()
        local svs = require("solve_verify_split")
        for _, B in ipairs({ 4, 8, 16, 32, 64, 100, 256 }) do
            local r = svs.optimal_split(B, PAPER_PARAMS())
            expect(r.cost_used <= B).to.equal(true)
        end
    end)

    it("s_opt ≥ 1 always", function()
        local svs = require("solve_verify_split")
        for _, B in ipairs({ 4, 8, 16, 100 }) do
            local r = svs.optimal_split(B, PAPER_PARAMS())
            expect(r.s_opt >= 1).to.equal(true)
        end
    end)

    it("v_opt ≥ 0 always", function()
        local svs = require("solve_verify_split")
        for _, B in ipairs({ 4, 8, 16, 100 }) do
            local r = svs.optimal_split(B, PAPER_PARAMS())
            expect(r.v_opt >= 0).to.equal(true)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- sc_pure
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.sc_pure positive", function()
    lust.after(reset)

    it("B=16, default round → S=16, V=0, cost=16", function()
        local svs = require("solve_verify_split")
        local r = svs.sc_pure(16)
        expect(r.s_opt).to.equal(16)
        expect(r.v_opt).to.equal(0)
        expect(r.cost_used).to.equal(16)
    end)

    it("B=16.4 with floor → S=16", function()
        local svs = require("solve_verify_split")
        local r = svs.sc_pure(16.4, { integer_method = "floor" })
        expect(r.s_opt).to.equal(16)
    end)

    it("B=16.6 with ceil → S=17", function()
        local svs = require("solve_verify_split")
        local r = svs.sc_pure(16.6, { integer_method = "ceil" })
        expect(r.s_opt).to.equal(17)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- compare_paths
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split.compare_paths", function()
    lust.after(reset)

    it("returns sc + genrm + delta_s_opt + delta_v_opt + cost_ratio", function()
        local svs = require("solve_verify_split")
        local r = svs.compare_paths(100, PAPER_PARAMS())
        expect(type(r.sc)).to.equal("table")
        expect(type(r.genrm)).to.equal("table")
        expect(type(r.delta_s_opt)).to.equal("number")
        expect(type(r.delta_v_opt)).to.equal("number")
        expect(type(r.cost_ratio)).to.equal("number")
    end)

    it("sc.s_opt = round(B), v_opt = 0", function()
        local svs = require("solve_verify_split")
        local r = svs.compare_paths(100, PAPER_PARAMS())
        expect(r.sc.s_opt).to.equal(100)
        expect(r.sc.v_opt).to.equal(0)
    end)

    it("delta_s_opt = genrm.s_opt - sc.s_opt", function()
        local svs = require("solve_verify_split")
        local r = svs.compare_paths(100, PAPER_PARAMS())
        expect(r.delta_s_opt).to.equal(r.genrm.s_opt - r.sc.s_opt)
    end)

    it("delta_v_opt = genrm.v_opt - sc.v_opt (sc.v_opt always 0)", function()
        local svs = require("solve_verify_split")
        local r = svs.compare_paths(100, PAPER_PARAMS())
        expect(r.delta_v_opt).to.equal(r.genrm.v_opt - r.sc.v_opt)
    end)

    it("cost_ratio = genrm.cost_used / sc.cost_used", function()
        local svs = require("solve_verify_split")
        local r = svs.compare_paths(100, PAPER_PARAMS())
        expect(approx_eq(r.cost_ratio, r.genrm.cost_used / r.sc.cost_used)).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Internal helpers (numerical hand-checks)
-- ═══════════════════════════════════════════════════════════════════

describe("solve_verify_split._internal", function()
    lust.after(reset)

    it("cost_of (4,3,1) = 16", function()
        local svs = require("solve_verify_split")
        expect(svs._internal.cost_of(4, 3, 1.0)).to.equal(16)
    end)

    it("power_law_raw(100, 0.57, 0.39, 1, 1) ≈ (13.80, 6.03)", function()
        local svs = require("solve_verify_split")
        local s_raw, v_raw = svs._internal.power_law_raw(100, 0.57, 0.39, 1.0, 1.0)
        expect(approx_eq(s_raw, 100 ^ 0.57, 1e-6)).to.equal(true)
        expect(approx_eq(v_raw, 100 ^ 0.39, 1e-6)).to.equal(true)
    end)

    it("round_with_method(13.8, 'round') = 14", function()
        local svs = require("solve_verify_split")
        expect(svs._internal.round_with_method(13.8, "round")).to.equal(14)
        expect(svs._internal.round_with_method(13.8, "floor")).to.equal(13)
        expect(svs._internal.round_with_method(13.8, "ceil")).to.equal(14)
    end)

    it("apply_rescale shrinks (14,6) at B=100,λ=2 to fit", function()
        local svs = require("solve_verify_split")
        -- raw cost 14·(1+2·6) = 14·13 = 182 > 100 → rescale fires
        local s, v, rescaled = svs._internal.apply_rescale(14, 6, 100, 2.0, "scale_proportional")
        expect(rescaled).to.equal(true)
        expect(svs._internal.cost_of(s, v, 2.0) <= 100).to.equal(true)
    end)

    it("apply_rescale no-op when already within budget", function()
        local svs = require("solve_verify_split")
        local s, v, rescaled = svs._internal.apply_rescale(4, 1, 100, 2.0, "scale_proportional")
        expect(rescaled).to.equal(false)
        expect(s).to.equal(4)
        expect(v).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- math-strict review hardening (a718ecc → next)
-- ═══════════════════════════════════════════════════════════════════

local function default_params()
    return {
        lambda           = 1.0,
        exponent_solve   = 0.57,
        exponent_verify  = 0.39,
        prefactor_solve  = 1.0,
        prefactor_verify = 0.5,
    }
end

describe("solve_verify_split.optimal_split cap domain checks (H1)", function()
    lust.after(reset)

    it("rejects v_cap = -1", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, 100, default_params(), { v_cap = -1 })
        expect(ok).to.equal(false)
        expect(err:match("v_cap") ~= nil).to.equal(true)
        expect(err:match(">= 0") ~= nil).to.equal(true)
    end)

    it("rejects s_cap = 0", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, 100, default_params(), { s_cap = 0 })
        expect(ok).to.equal(false)
        expect(err:match("s_cap") ~= nil).to.equal(true)
        expect(err:match(">= 1") ~= nil).to.equal(true)
    end)

    it("rejects s_cap = 0.5 (non-integer)", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, 100, default_params(), { s_cap = 0.5 })
        expect(ok).to.equal(false)
        expect(err:match("integer") ~= nil).to.equal(true)
    end)

    it("rejects v_cap = 0.5 (non-integer)", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, 100, default_params(), { v_cap = 0.5 })
        expect(ok).to.equal(false)
        expect(err:match("integer") ~= nil).to.equal(true)
    end)

    it("accepts v_cap = 0 (valid: forces SC fallback path)", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, default_params(), { v_cap = 0 })
        expect(r.v_opt).to.equal(0)
        expect(r.is_sc_fallback).to.equal(true)
    end)

    it("accepts s_cap = 1 (paper minimum)", function()
        local svs = require("solve_verify_split")
        local r = svs.optimal_split(100, default_params(), { s_cap = 1 })
        expect(r.s_opt).to.equal(1)
    end)
end)

describe("solve_verify_split NaN/Inf rejection (H3)", function()
    lust.after(reset)
    local nan = 0 / 0
    local pos_inf = math.huge
    local neg_inf = -math.huge

    it("rejects NaN budget", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, nan, default_params())
        expect(ok).to.equal(false)
        expect(err:match("NaN") ~= nil).to.equal(true)
    end)

    it("rejects +Inf budget", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.optimal_split, pos_inf, default_params())
        expect(ok).to.equal(false)
        expect(err:match("finite") ~= nil).to.equal(true)
    end)

    it("rejects NaN lambda", function()
        local svs = require("solve_verify_split")
        local p = default_params()
        p.lambda = nan
        local ok, err = pcall(svs.optimal_split, 100, p)
        expect(ok).to.equal(false)
        expect(err:match("NaN") ~= nil).to.equal(true)
    end)

    it("rejects -Inf lambda via cost entry", function()
        local svs = require("solve_verify_split")
        local ok, err = pcall(svs.cost, 4, 1, neg_inf)
        expect(ok).to.equal(false)
        expect(err:match("finite") ~= nil).to.equal(true)
    end)

    it("rejects NaN exponent_solve", function()
        local svs = require("solve_verify_split")
        local p = default_params()
        p.exponent_solve = nan
        local ok, err = pcall(svs.optimal_split, 100, p)
        expect(ok).to.equal(false)
        expect(err:match("NaN") ~= nil).to.equal(true)
    end)

    it("rejects NaN prefactor_solve", function()
        local svs = require("solve_verify_split")
        local p = default_params()
        p.prefactor_solve = nan
        local ok, err = pcall(svs.optimal_split, 100, p)
        expect(ok).to.equal(false)
        expect(err:match("prefactor_solve") ~= nil).to.equal(true)
    end)
end)

describe("solve_verify_split is_sc_fallback semantic consistency (H2)", function()
    lust.after(reset)

    it("v_cap=0 forces SC takeover at any budget", function()
        local svs = require("solve_verify_split")
        for _, B in ipairs({ 1, 3, 10, 100 }) do
            local r = svs.optimal_split(B, default_params(), { v_cap = 0 })
            expect(r.v_opt).to.equal(0)
            expect(r.is_sc_fallback).to.equal(true)
        end
    end)

    it("V_int=0 short-circuit sets is_sc_fallback=true (Path 1)", function()
        local svs = require("solve_verify_split")
        local p = default_params()
        p.prefactor_verify = 0.0001       -- V_raw → ~0 → V_int = 0
        local r = svs.optimal_split(2, p)
        expect(r.v_opt).to.equal(0)
        expect(r.is_sc_fallback).to.equal(true)
    end)
end)

describe("solve_verify_split.score_split proxy symmetry (M1)", function()
    lust.after(reset)

    it("S=0 returns nil (not 0) — symmetric with V=0", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(0, 4, default_params())
        expect(r.power_law_score_proxy).to.equal(nil)
    end)

    it("V=0 returns nil — SC pure path proxy undefined", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(8, 0, default_params())
        expect(r.power_law_score_proxy).to.equal(nil)
    end)

    it("S>0 and V>0 returns numeric proxy", function()
        local svs = require("solve_verify_split")
        local r = svs.score_split(8, 4, default_params())
        expect(type(r.power_law_score_proxy)).to.equal("number")
        expect(r.power_law_score_proxy > 0).to.equal(true)
    end)
end)
