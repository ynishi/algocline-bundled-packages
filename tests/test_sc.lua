--- Tests for sc package — covers pure helper additions.
--- M.run() requires alc.llm (LLM-dependent) so is not tested here.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Dual-mode header: works via both
--   (a) `mlua-probe test tests/` CLI            — PWD fallback below
--   (b) `mcp__lua-debugger__test_launch(search_paths=[REPO])` — MCP prepend
-- Both paths (a) and (b) end up prepending the worktree to package.path,
-- so the worktree copy wins over any installed same-named package.
-- Direct `lua tests/*.lua` is NOT supported — `lust` global is only
-- injected by mlua-probe (CLI or MCP).
local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

package.loaded["sc"] = nil
local sc = require("sc")

describe("sc.meta", function()
    it("has correct name", function()
        expect(sc.meta.name).to.equal("sc")
    end)
end)

describe("sc._internal.clean_answer", function()
    local clean = sc._internal.clean_answer

    it("strips leading/trailing whitespace", function()
        expect(clean("  hello  ")).to.equal("hello")
    end)

    it("strips trailing punctuation", function()
        expect(clean("Tokyo.")).to.equal("Tokyo")
        expect(clean("Yes!")).to.equal("Yes")
        expect(clean("Tokyo,")).to.equal("Tokyo")
        expect(clean("a?")).to.equal("a")
    end)

    it("collapses internal whitespace runs", function()
        expect(clean("the   quick\tbrown")).to.equal("the quick brown")
    end)

    it("preserves internal punctuation", function()
        expect(clean("6:30 am")).to.equal("6:30 am")
        expect(clean("U.S.A")).to.equal("U.S.A")
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

describe("sc._internal.normalize_for_vote", function()
    local norm = sc._internal.normalize_for_vote

    it("lowercases", function()
        expect(norm("Tokyo")).to.equal("tokyo")
    end)

    it("strips punctuation + lowercases", function()
        expect(norm("Tokyo.")).to.equal("tokyo")
        expect(norm("TOKYO!")).to.equal("tokyo")
    end)

    it("Tokyo and Tokyo. collide under normalization", function()
        expect(norm("Tokyo")).to.equal(norm("Tokyo."))
    end)

    it("empty / non-string → empty", function()
        expect(norm("")).to.equal("")
        expect(norm(nil)).to.equal("")
    end)
end)
