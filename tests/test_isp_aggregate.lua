--- Tests for isp_aggregate package — covers pure helper functions.
--- M.run() requires alc.llm (LLM-dependent) so is not tested here.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp),
-- which injects `lust` as a global and prepends `search_paths` to
-- package.path:
--   mcp__lua-debugger__test_launch(
--     code_file    = "<worktree>/tests/test_isp_aggregate.lua",
--     search_paths = ["<worktree>"],
--   )

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

    it("has version", function()
        expect(type(isp.meta.version)).to.equal("string")
    end)
end)

-- ─── clean_answer ──────────────────────────────────────────────────────────

describe("isp_aggregate._internal.clean_answer", function()
    local clean = isp._internal.clean_answer

    it("strips leading/trailing whitespace", function()
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

-- ─── normalize ─────────────────────────────────────────────────────────────

describe("isp_aggregate._internal.normalize", function()
    local norm = isp._internal.normalize

    it("lowercases", function()
        expect(norm("Tokyo")).to.equal("tokyo")
    end)

    it("strips punctuation + lowercases", function()
        expect(norm("Tokyo.")).to.equal("tokyo")
        expect(norm("TOKYO!")).to.equal("tokyo")
    end)

    it("returns empty string for non-string input", function()
        expect(norm(nil)).to.equal("")
        expect(norm("")).to.equal("")
    end)
end)

-- ─── parse_probabilities ───────────────────────────────────────────────────

describe("isp_aggregate._internal.parse_probabilities", function()
    local parse = isp._internal.parse_probabilities

    it("parses valid <probs> block", function()
        local raw = "<probs>\nA: 0.5\nB: 0.3\nC: 0.2\n</probs>"
        local result = parse(raw, { "A", "B", "C" })
        expect(result).to.exist()
        expect(result["A"]).to.equal(0.5)
        expect(result["B"]).to.equal(0.3)
        expect(result["C"]).to.equal(0.2)
    end)

    it("handles case-insensitive label matching", function()
        local raw = "<probs>\na: 0.5\nb: 0.5\n</probs>"
        local result = parse(raw, { "A", "B" })
        expect(result).to.exist()
        expect(result["A"]).to.equal(0.5)
        expect(result["B"]).to.equal(0.5)
    end)

    it("returns nil when total probability is below 0.1", function()
        local raw = "<probs>\nA: 0.01\nB: 0.02\n</probs>"
        local result = parse(raw, { "A", "B" })
        expect(result).to_not.exist()
    end)

    it("returns nil when no <probs> tag found", function()
        local raw = "A: 0.5\nB: 0.5"
        local result = parse(raw, { "A", "B" })
        expect(result).to_not.exist()
    end)

    it("returns nil when no option matches found", function()
        local raw = "<probs>\nX: 0.5\nY: 0.5\n</probs>"
        local result = parse(raw, { "A", "B" })
        expect(result).to_not.exist()
    end)

    it("ignores lines for options not in the options array", function()
        local raw = "<probs>\nA: 0.6\nB: 0.3\nZ: 0.1\n</probs>"
        local result = parse(raw, { "A", "B" })
        expect(result).to.exist()
        expect(result["A"]).to.equal(0.6)
        expect(result["B"]).to.equal(0.3)
        expect(result["Z"]).to_not.exist()
    end)

    it("returns nil on non-string input", function()
        local result = parse(nil, { "A", "B" })
        expect(result).to_not.exist()
    end)
end)

-- ─── score_isp ─────────────────────────────────────────────────────────────

describe("isp_aggregate._internal.score_isp", function()
    local score_isp = isp._internal.score_isp

    it("computes c1/c2_hat ratio correctly", function()
        local c1     = { A = 3, B = 2 }
        local c2_hat = { A = 0.6, B = 0.4 }
        local opts   = { "A", "B" }
        local scores = score_isp(c1, c2_hat, opts)
        -- 3/0.6 = 5, 2/0.4 = 5
        expect(math.abs(scores["A"] - 5.0) < 1e-6).to.equal(true)
        expect(math.abs(scores["B"] - 5.0) < 1e-6).to.equal(true)
    end)

    it("surprising popularity: lower predicted but more actual votes wins", function()
        -- c1: B=3 > A=2, but c2_hat: B=0.7 >> A=0.1 → ISP: A=2/0.1=20, B=3/0.7≈4.3 → A wins
        local c1     = { A = 2, B = 3 }
        local c2_hat = { A = 0.1, B = 0.7 }
        local opts   = { "A", "B" }
        local scores = score_isp(c1, c2_hat, opts)
        expect(scores["A"] > scores["B"]).to.equal(true)
    end)

    it("handles c2_hat=0 without division by zero (epsilon guard)", function()
        local c1     = { A = 3, B = 0 }
        local c2_hat = { A = 0, B = 0 }
        local opts   = { "A", "B" }
        -- Should not throw; scores should be finite
        local ok, scores = pcall(score_isp, c1, c2_hat, opts)
        expect(ok).to.equal(true)
        expect(type(scores["A"])).to.equal("number")
        expect(scores["A"] < math.huge).to.equal(true)
    end)

    it("missing options default to zero count", function()
        local c1     = {}
        local c2_hat = { A = 0.5 }
        local opts   = { "A" }
        local scores = score_isp(c1, c2_hat, opts)
        -- c1["A"] = nil → 0, 0/0.5 = 0
        expect(scores["A"]).to.equal(0)
    end)
end)

-- ─── score_ow ──────────────────────────────────────────────────────────────

describe("isp_aggregate._internal.score_ow", function()
    local score_ow = isp._internal.score_ow

    it("computes c1 - n*c2_hat correctly", function()
        local c1     = { A = 3, B = 2 }
        local c2_hat = { A = 0.6, B = 0.4 }
        local opts   = { "A", "B" }
        local n      = 5
        local scores = score_ow(c1, c2_hat, opts, n)
        -- A: 3 - 5*0.6 = 3 - 3 = 0
        -- B: 2 - 5*0.4 = 2 - 2 = 0
        expect(math.abs(scores["A"]) < 1e-6).to.equal(true)
        expect(math.abs(scores["B"]) < 1e-6).to.equal(true)
    end)

    it("surprising popularity example: minority in 1st-order wins with OW", function()
        -- A: c1=2 (minority), but c2_hat=0.3 (predicted less) → OW: A=2-5*0.3=0.5
        -- B: c1=3 (majority), but c2_hat=0.7 (predicted well) → OW: B=3-5*0.7=-0.5
        -- A wins!
        local c1     = { A = 2, B = 3 }
        local c2_hat = { A = 0.3, B = 0.7 }
        local opts   = { "A", "B" }
        local n      = 5
        local scores = score_ow(c1, c2_hat, opts, n)
        expect(math.abs(scores["A"] - 0.5) < 1e-6).to.equal(true)
        expect(math.abs(scores["B"] - (-0.5)) < 1e-6).to.equal(true)
        expect(scores["A"] > scores["B"]).to.equal(true)
    end)

    it("handles missing entries gracefully", function()
        local c1     = {}
        local c2_hat = {}
        local opts   = { "A" }
        local scores = score_ow(c1, c2_hat, opts, 5)
        -- 0 - 5*0 = 0
        expect(scores["A"]).to.equal(0)
    end)
end)
