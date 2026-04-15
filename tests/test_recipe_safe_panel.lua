--- Tests for recipe_safe_panel package.
--- Structure validation + internal helper verification.
--- M.run() requires alc.llm (LLM-dependent) so is not tested here.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local safe_panel = require("recipe_safe_panel")

-- ═══════════════════════════════════════════════════════════════════
-- Meta structure
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_safe_panel.meta", function()
    it("has correct name", function()
        expect(safe_panel.meta.name).to.equal("recipe_safe_panel")
    end)

    it("has version", function()
        expect(safe_panel.meta.version).to.exist()
    end)

    it("has description", function()
        expect(type(safe_panel.meta.description)).to.equal("string")
        expect(#safe_panel.meta.description > 0).to.equal(true)
    end)

    it("has category = recipe", function()
        expect(safe_panel.meta.category).to.equal("recipe")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Recipe-specific fields
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_safe_panel.ingredients", function()
    it("is a non-empty list", function()
        expect(type(safe_panel.ingredients)).to.equal("table")
        expect(#safe_panel.ingredients > 0).to.equal(true)
    end)

    it("contains condorcet", function()
        local found = false
        for _, pkg in ipairs(safe_panel.ingredients) do
            if pkg == "condorcet" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("contains sc", function()
        local found = false
        for _, pkg in ipairs(safe_panel.ingredients) do
            if pkg == "sc" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("contains inverse_u", function()
        local found = false
        for _, pkg in ipairs(safe_panel.ingredients) do
            if pkg == "inverse_u" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("contains calibrate", function()
        local found = false
        for _, pkg in ipairs(safe_panel.ingredients) do
            if pkg == "calibrate" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("all ingredients are strings", function()
        for _, pkg in ipairs(safe_panel.ingredients) do
            expect(type(pkg)).to.equal("string")
        end
    end)

    it("all ingredients can be required", function()
        for _, pkg_name in ipairs(safe_panel.ingredients) do
            local ok, pkg = pcall(require, pkg_name)
            expect(ok).to.equal(true)
            expect(type(pkg)).to.equal("table")
            expect(pkg.meta).to.exist()
        end
    end)
end)

describe("recipe_safe_panel.caveats", function()
    it("is a non-empty list", function()
        expect(type(safe_panel.caveats)).to.equal("table")
        expect(#safe_panel.caveats > 0).to.equal(true)
    end)

    it("all entries are strings", function()
        for _, lm in ipairs(safe_panel.caveats) do
            expect(type(lm)).to.equal("string")
        end
    end)

    it("has at least 3 known failure modes", function()
        expect(#safe_panel.caveats >= 3).to.equal(true)
    end)

    it("mentions Anti-Jury", function()
        local found = false
        for _, lm in ipairs(safe_panel.caveats) do
            if lm:find("Anti%-Jury") or lm:find("anti_jury") then
                found = true
            end
        end
        expect(found).to.equal(true)
    end)

    it("mentions inverse-U", function()
        local found = false
        for _, lm in ipairs(safe_panel.caveats) do
            if lm:find("inverse") then found = true end
        end
        expect(found).to.equal(true)
    end)
end)

describe("recipe_safe_panel.verified", function()
    it("exists as a table", function()
        expect(type(safe_panel.verified)).to.equal("table")
    end)

    it("has theoretical_basis", function()
        expect(type(safe_panel.verified.theoretical_basis)).to.equal("table")
        expect(#safe_panel.verified.theoretical_basis > 0).to.equal(true)
    end)

    it("theoretical_basis mentions Condorcet", function()
        local found = false
        for _, ref in ipairs(safe_panel.verified.theoretical_basis) do
            if ref:find("Condorcet") then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("theoretical_basis mentions Chen/NeurIPS", function()
        local found = false
        for _, ref in ipairs(safe_panel.verified.theoretical_basis) do
            if ref:find("Chen") or ref:find("NeurIPS") then found = true end
        end
        expect(found).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- M.run interface
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_safe_panel.run", function()
    it("is a callable function", function()
        expect(type(safe_panel.run)).to.equal("function")
    end)

    it("errors on missing ctx.task", function()
        local ok, err = pcall(safe_panel.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task")).to.exist()
    end)

    it("errors on non-numeric max_n", function()
        local ok = pcall(safe_panel.run, { task = "t", max_n = "big" })
        expect(ok).to.equal(false)
    end)

    it("errors on max_n < 3", function()
        local ok, err = pcall(safe_panel.run, { task = "t", max_n = 2, p_estimate = 0.7 })
        expect(ok).to.equal(false)
        expect(err:find("max_n")).to.exist()
    end)

    it("errors on missing p_estimate (no silent default)", function()
        -- Previously ctx.p_estimate defaulted to 0.7, which silently
        -- bypassed the Anti-Jury gate on tasks where the real p < 0.5.
        -- The default has been removed; p_estimate is now REQUIRED.
        local ok, err = pcall(safe_panel.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err:find("p_estimate")).to.exist()
    end)

    it("errors on non-numeric p_estimate", function()
        local ok, err = pcall(safe_panel.run, {
            task = "t", p_estimate = "high"
        })
        expect(ok).to.equal(false)
        expect(err:find("p_estimate")).to.exist()
    end)

    it("errors on p_estimate out of (0, 1]", function()
        local ok1 = pcall(safe_panel.run, { task = "t", p_estimate = 0 })
        expect(ok1).to.equal(false)
        local ok2 = pcall(safe_panel.run, { task = "t", p_estimate = 1.5 })
        expect(ok2).to.equal(false)
        local ok3 = pcall(safe_panel.run, { task = "t", p_estimate = -0.1 })
        expect(ok3).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Internal helpers (pure, LLM-free) — unit tests
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_safe_panel._internal.analyze_votes", function()
    local analyze = safe_panel._internal.analyze_votes

    it("unanimous vote: plurality=1, gap=1, n_distinct=1", function()
        local r = analyze({ ["Tokyo"] = 5 }, 5)
        expect(r.plurality_fraction).to.equal(1.0)
        expect(r.margin_gap).to.equal(1.0)
        expect(r.n_distinct).to.equal(1)
        expect(r.unanimous).to.equal(true)
    end)

    it("clear majority: 3-2 → plurality=0.6, gap=0.2", function()
        local r = analyze({ a = 3, b = 2 }, 5)
        expect(math.abs(r.plurality_fraction - 0.6) < 1e-9).to.equal(true)
        expect(math.abs(r.margin_gap - 0.2) < 1e-9).to.equal(true)
        expect(r.n_distinct).to.equal(2)
        expect(r.unanimous).to.equal(false)
    end)

    it("top tie: margin_gap = 0", function()
        local r = analyze({ a = 3, b = 3, c = 1 }, 7)
        -- plurality_fraction is top share (3/7), NOT (6/7).
        expect(math.abs(r.plurality_fraction - 3/7) < 1e-9).to.equal(true)
        expect(r.margin_gap).to.equal(0)
    end)

    it("all distinct: max=1, gap=0", function()
        local r = analyze({ a = 1, b = 1, c = 1 }, 3)
        expect(r.max_count).to.equal(1)
        expect(r.runner_up_count).to.equal(1)
        expect(r.margin_gap).to.equal(0)
        expect(r.n_distinct).to.equal(3)
    end)

    it("unanimous has norm_entropy = 0", function()
        local r = analyze({ a = 3 }, 3)
        expect(r.norm_entropy).to.equal(0)
    end)

    it("all-distinct has norm_entropy = 1 (max uncertainty)", function()
        local r = analyze({ a = 1, b = 1, c = 1 }, 3)
        expect(math.abs(r.norm_entropy - 1) < 1e-9).to.equal(true)
    end)
end)

describe("recipe_safe_panel._internal.build_accuracy_proxy", function()
    local build = safe_panel._internal.build_accuracy_proxy

    it("empty series for n=3 votes (only i=3 sampled)", function()
        -- At i=3 we sample; any i < 3 is skipped, and at i=3 match-ratio
        -- is 2/3 if all three match.
        local s = build({ "a", "a", "a" }, "a")
        expect(#s).to.equal(1)
        expect(math.abs(s[1] - 1.0) < 1e-9).to.equal(true)
    end)

    it("n=5 votes → series length 2 (k=3,5)", function()
        local s = build({ "a", "a", "b", "a", "a" }, "a")
        expect(#s).to.equal(2)
        -- k=3: votes[1..3] = {a,a,b}, matches=2 → 2/3
        -- k=5: votes[1..5] = {a,a,b,a,a}, matches=4 → 4/5
        expect(math.abs(s[1] - 2/3) < 1e-9).to.equal(true)
        expect(math.abs(s[2] - 4/5) < 1e-9).to.equal(true)
    end)

    it("n=7 votes → series length 3 (k=3,5,7)", function()
        local s = build({ "a", "b", "a", "b", "a", "a", "a" }, "a")
        expect(#s).to.equal(3)
        -- k=3: {a,b,a} matches=2 → 2/3
        -- k=5: {a,b,a,b,a} matches=3 → 3/5
        -- k=7: all 7, matches=5 → 5/7
        expect(math.abs(s[1] - 2/3) < 1e-9).to.equal(true)
        expect(math.abs(s[2] - 3/5) < 1e-9).to.equal(true)
        expect(math.abs(s[3] - 5/7) < 1e-9).to.equal(true)
    end)

    it("n=2 votes → empty series (no odd k >= 3)", function()
        local s = build({ "a", "a" }, "a")
        expect(#s).to.equal(0)
    end)

    it("no matches at all → series of zeros", function()
        local s = build({ "a", "a", "a", "a", "a" }, "b")
        expect(#s).to.equal(2)
        expect(s[1]).to.equal(0)
        expect(s[2]).to.equal(0)
    end)
end)
