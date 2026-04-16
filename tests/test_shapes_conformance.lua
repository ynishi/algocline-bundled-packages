--- Shape conformance test — static validation of producer declarations.
--- Verifies meta.result_shape declarations match alc_shapes dictionary
--- entries without requiring live LLM calls.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

package.loaded["alc_shapes"]         = nil
package.loaded["alc_shapes.t"]       = nil
package.loaded["alc_shapes.check"]   = nil
package.loaded["alc_shapes.reflect"] = nil
package.loaded["alc_shapes.luacats"] = nil

local S = require("alc_shapes")
local T = S.T

local DECLARED_PACKAGES = {
    { name = "sc",        shape = "voted" },
    { name = "panel",     shape = "paneled" },
    { name = "calibrate", shape = "calibrated" },
}

describe("shape conformance: meta declarations", function()
    for _, entry in ipairs(DECLARED_PACKAGES) do
        describe(entry.name, function()
            package.loaded[entry.name] = nil
            local pkg = require(entry.name)

            it("declares result_shape in meta", function()
                expect(pkg.meta).to.exist()
                expect(pkg.meta.result_shape).to.equal(entry.shape)
            end)

            it("shape name exists in alc_shapes dictionary", function()
                local shape = S[entry.shape]
                expect(shape).to.exist()
                expect(type(shape)).to.equal("table")
                expect(rawget(shape, "kind")).to.equal("shape")
            end)

            it("shape has non-empty fields", function()
                local shape = S[entry.shape]
                local entries = S.fields(shape)
                expect(#entries > 0).to.equal(true)
            end)
        end)
    end
end)

describe("shape conformance: secondary entry points", function()
    it("calibrate.assess documents assessed shape", function()
        local shape = S.assessed
        expect(shape).to.exist()
        expect(rawget(shape, "kind")).to.equal("shape")
        local entries = S.fields(shape)
        local names = {}
        for _, e in ipairs(entries) do names[e.name] = true end
        expect(names.answer).to.equal(true)
        expect(names.confidence).to.equal(true)
        expect(names.total_llm_calls).to.equal(true)
    end)
end)

describe("shape conformance: shape validation against mock data", function()
    it("voted shape accepts well-formed sc result", function()
        local mock = {
            consensus = "Tokyo is the capital",
            answer = "Tokyo",
            answer_norm = "tokyo",
            paths = { { reasoning = "...", answer = "Tokyo" } },
            votes = { "tokyo" },
            vote_counts = { tokyo = 1 },
            n_sampled = 1,
            total_llm_calls = 3,
        }
        local ok, reason = S.check(mock, S.voted)
        expect(ok).to.equal(true)
    end)

    it("voted shape accepts result with nil answer (no convergence)", function()
        -- answer/answer_norm are optional at top level, but each path
        -- always has both reasoning and answer (extract_answer always
        -- returns a string even if unhelpful).
        local mock = {
            consensus = "No clear answer",
            paths = { { reasoning = "...", answer = "unclear" } },
            votes = { "" },
            vote_counts = {},
            n_sampled = 1,
            total_llm_calls = 3,
        }
        local ok = S.check(mock, S.voted)
        expect(ok).to.equal(true)
    end)

    it("voted shape rejects missing required field", function()
        local ok, reason = S.check({ consensus = "x" }, S.voted)
        expect(ok).to.equal(false)
        expect(reason:match("shape violation")).to.exist()
    end)

    it("paneled shape accepts well-formed panel result", function()
        local mock = {
            arguments = { { role = "advocate", text = "I argue..." } },
            synthesis = "The panel concludes...",
        }
        expect(S.check(mock, S.paneled)).to.equal(true)
    end)

    it("assessed shape accepts well-formed assess result", function()
        local mock = {
            answer = "42",
            confidence = 0.85,
            total_llm_calls = 1,
        }
        expect(S.check(mock, S.assessed)).to.equal(true)
    end)

    it("calibrated shape accepts direct (non-escalated) result", function()
        local mock = {
            answer = "42",
            confidence = 0.9,
            escalated = false,
            strategy = "direct",
            total_llm_calls = 1,
        }
        expect(S.check(mock, S.calibrated)).to.equal(true)
    end)

    it("calibrated shape accepts escalated result with fallback_detail", function()
        local mock = {
            answer = "Tokyo",
            confidence = 0.3,
            escalated = true,
            strategy = "ensemble",
            total_llm_calls = 12,
            fallback_detail = { consensus = "Tokyo" },
        }
        expect(S.check(mock, S.calibrated)).to.equal(true)
    end)

    it("calibrated shape rejects invalid strategy", function()
        local mock = {
            answer = "x",
            confidence = 0.5,
            escalated = true,
            strategy = "invalid_strategy",
            total_llm_calls = 2,
        }
        local ok, reason = S.check(mock, S.calibrated)
        expect(ok).to.equal(false)
        expect(reason:match("expected one of")).to.exist()
    end)

    it("all shapes tolerate extra fields (open=true)", function()
        local shapes = { S.voted, S.paneled, S.assessed, S.calibrated }
        for _, shape in ipairs(shapes) do
            expect(rawget(shape, "open")).to.equal(true)
        end
    end)
end)
