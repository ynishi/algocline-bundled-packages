--- Tests for bft.
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

describe("bft", function()
    local bft = require("bft")

    describe("validate", function()
        it("accepts n=4, f=1 (3*1+1=4)", function()
            local ok, _ = bft.validate(4, 1)
            expect(ok).to.equal(true)
        end)

        it("rejects n=3, f=1 (3*1+1=4 > 3)", function()
            local ok, _ = bft.validate(3, 1)
            expect(ok).to.equal(false)
        end)

        it("accepts n=7, f=2 (3*2+1=7)", function()
            local ok, _ = bft.validate(7, 2)
            expect(ok).to.equal(true)
        end)

        it("accepts f=0 for any n>=1", function()
            local ok, _ = bft.validate(1, 0)
            expect(ok).to.equal(true)
        end)
    end)

    describe("threshold", function()
        it("returns 2f+1 for valid configs", function()
            expect(bft.threshold(4, 1)).to.equal(3)
            expect(bft.threshold(7, 2)).to.equal(5)
            expect(bft.threshold(10, 3)).to.equal(7)
        end)

        it("returns 1 for f=0", function()
            expect(bft.threshold(3, 0)).to.equal(1)
        end)

        it("errors on invalid config", function()
            expect(function() bft.threshold(3, 1) end).to.fail()
        end)
    end)

    describe("max_faults", function()
        it("computes floor((n-1)/3)", function()
            expect(bft.max_faults(1)).to.equal(0)
            expect(bft.max_faults(3)).to.equal(0)
            expect(bft.max_faults(4)).to.equal(1)
            expect(bft.max_faults(7)).to.equal(2)
            expect(bft.max_faults(10)).to.equal(3)
        end)
    end)

    describe("signed messages", function()
        it("validate_signed accepts n=3, f=1 (f+2=3)", function()
            local ok, _ = bft.validate_signed(3, 1)
            expect(ok).to.equal(true)
        end)

        it("validate_signed rejects n=2, f=1 (f+2=3 > 2)", function()
            local ok, _ = bft.validate_signed(2, 1)
            expect(ok).to.equal(false)
        end)

        it("signed_threshold returns f+1", function()
            expect(bft.signed_threshold(3, 1)).to.equal(2)
            expect(bft.signed_threshold(5, 2)).to.equal(3)
        end)

        it("max_faults_signed returns n-2", function()
            expect(bft.max_faults_signed(5)).to.equal(3)
            expect(bft.max_faults_signed(2)).to.equal(0)
        end)
    end)

    describe("summary", function()
        it("returns all fields for n=7, f=2", function()
            local s = bft.summary(7, 2)
            expect(s.n).to.equal(7)
            expect(s.f).to.equal(2)
            expect(s.oral_ok).to.equal(true)
            expect(s.oral_quorum).to.equal(5)
            expect(s.signed_ok).to.equal(true)
            expect(s.signed_quorum).to.equal(3)
            expect(s.max_f_oral).to.equal(2)
            expect(s.max_f_signed).to.equal(5)
        end)
    end)

    describe("input validation", function()
        it("errors on non-integer n", function()
            expect(function() bft.validate(3.5, 1) end).to.fail()
        end)
        it("errors on negative f", function()
            expect(function() bft.validate(4, -1) end).to.fail()
        end)
    end)
end)
