--- Tests for recipe_ranking_funnel package.
--- Structure validation + internal helper verification.
--- M.run() requires alc.llm (LLM-dependent) so is not tested here.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local funnel = require("recipe_ranking_funnel")

-- ═══════════════════════════════════════════════════════════════════
-- Meta structure
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_ranking_funnel.meta", function()
    it("has correct name", function()
        expect(funnel.meta.name).to.equal("recipe_ranking_funnel")
    end)

    it("has version", function()
        expect(funnel.meta.version).to.exist()
    end)

    it("has description", function()
        expect(type(funnel.meta.description)).to.equal("string")
        expect(#funnel.meta.description > 0).to.equal(true)
    end)

    it("has category = recipe", function()
        expect(funnel.meta.category).to.equal("recipe")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Recipe-specific fields
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_ranking_funnel.ingredients", function()
    it("is a non-empty list", function()
        expect(type(funnel.ingredients)).to.equal("table")
        expect(#funnel.ingredients > 0).to.equal(true)
    end)

    it("contains listwise_rank", function()
        local found = false
        for _, pkg in ipairs(funnel.ingredients) do
            if pkg == "listwise_rank" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("contains pairwise_rank", function()
        local found = false
        for _, pkg in ipairs(funnel.ingredients) do
            if pkg == "pairwise_rank" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("all ingredients are strings", function()
        for _, pkg in ipairs(funnel.ingredients) do
            expect(type(pkg)).to.equal("string")
        end
    end)

    it("all ingredients can be required", function()
        for _, pkg_name in ipairs(funnel.ingredients) do
            local ok, pkg = pcall(require, pkg_name)
            expect(ok).to.equal(true)
            expect(type(pkg)).to.equal("table")
            expect(pkg.meta).to.exist()
        end
    end)
end)

describe("recipe_ranking_funnel.caveats", function()
    it("is a non-empty list", function()
        expect(type(funnel.caveats)).to.equal("table")
        expect(#funnel.caveats > 0).to.equal(true)
    end)

    it("all entries are strings", function()
        for _, lm in ipairs(funnel.caveats) do
            expect(type(lm)).to.equal("string")
        end
    end)

    it("has at least 3 known failure modes", function()
        expect(#funnel.caveats >= 3).to.equal(true)
    end)
end)

describe("recipe_ranking_funnel.verified", function()
    it("exists as a table", function()
        expect(type(funnel.verified)).to.equal("table")
    end)

    it("has theoretical_basis", function()
        expect(type(funnel.verified.theoretical_basis)).to.equal("table")
        expect(#funnel.verified.theoretical_basis > 0).to.equal(true)
    end)

    it("theoretical_basis mentions listwise or pairwise", function()
        local found = false
        for _, ref in ipairs(funnel.verified.theoretical_basis) do
            if ref:find("listwise") or ref:find("pairwise") then
                found = true
            end
        end
        expect(found).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- M.run interface
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_ranking_funnel.run", function()
    it("is a callable function", function()
        expect(type(funnel.run)).to.equal("function")
    end)

    it("errors on missing ctx.task", function()
        local ok, err = pcall(funnel.run, { candidates = { "a", "b" } })
        expect(ok).to.equal(false)
        expect(err:find("task")).to.exist()
    end)

    it("errors on missing ctx.candidates", function()
        local ok, err = pcall(funnel.run, { task = "rank" })
        expect(ok).to.equal(false)
        expect(err:find("candidates")).to.exist()
    end)

    it("errors on too few candidates", function()
        local ok, err = pcall(funnel.run, { task = "rank", candidates = { "a" } })
        expect(ok).to.equal(false)
    end)
end)
