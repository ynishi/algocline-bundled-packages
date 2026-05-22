--- Tests for ensemble_div.
--- Pure computation, no LLM mocking.
--- Extracted from tests/test_foundations.lua (Phase C decomposition).

local describe, it, expect = lust.describe, lust.it, lust.expect

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

describe("ensemble_div", function()
    local ed = require("ensemble_div")

    describe("decompose", function()
        it("satisfies E = E_bar - A_bar identity", function()
            local r = ed.decompose({0.8, 0.6, 0.9}, 1.0)
            expect(r.identity_holds).to.equal(true)
            expect(math.abs(r.E - (r.E_bar - r.A_bar)) < 1e-10).to.equal(true)
        end)

        it("identity holds for varied scores", function()
            local r = ed.decompose({0.1, 0.5, 0.9, 0.3, 0.7}, 0.6)
            expect(r.identity_holds).to.equal(true)
        end)

        it("identity holds with non-uniform weights", function()
            local r = ed.decompose({0.2, 0.8, 0.5}, 0.4, {0.5, 0.3, 0.2})
            expect(r.identity_holds).to.equal(true)
        end)

        it("A_bar = 0 when all scores equal", function()
            local r = ed.decompose({0.7, 0.7, 0.7}, 1.0)
            expect(math.abs(r.A_bar) < 1e-10).to.equal(true)
            expect(r.identity_holds).to.equal(true)
        end)

        it("A_bar > 0 implies E < E_bar", function()
            local r = ed.decompose({0.5, 0.8, 0.3}, 0.6)
            expect(r.A_bar > 0).to.equal(true)
            expect(r.E < r.E_bar).to.equal(true)
        end)
    end)

    describe("ensemble", function()
        it("computes weighted average", function()
            local v = ed.ensemble({0.2, 0.8}, {0.5, 0.5})
            expect(math.abs(v - 0.5) < 1e-10).to.equal(true)
        end)

        it("computes uniform average by default", function()
            local v = ed.ensemble({0.3, 0.6, 0.9})
            expect(math.abs(v - 0.6) < 1e-10).to.equal(true)
        end)
    end)

    describe("ambiguity", function()
        it("is zero for identical scores", function()
            local a = ed.ambiguity({0.5, 0.5, 0.5})
            expect(math.abs(a) < 1e-10).to.equal(true)
        end)

        it("is positive for diverse scores", function()
            local a = ed.ambiguity({0.1, 0.5, 0.9})
            expect(a > 0).to.equal(true)
        end)
    end)

    describe("avg_error", function()
        it("computes correctly", function()
            -- scores = {1.0}, target = 0.0 => E_bar = 1.0
            local e = ed.avg_error({1.0}, 0.0)
            expect(math.abs(e - 1.0) < 1e-10).to.equal(true)
        end)
    end)

    describe("input validation", function()
        it("errors on empty scores", function()
            expect(function() ed.decompose({}, 1.0) end).to.fail()
        end)
        it("errors on mismatched weights", function()
            expect(function() ed.decompose({0.5, 0.5}, 1.0, {0.5}) end).to.fail()
        end)
    end)
end)
