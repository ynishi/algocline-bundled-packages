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
end)
