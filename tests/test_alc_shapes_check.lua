--- Tests for alc_shapes.check — validator.

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

package.loaded["alc_shapes"]         = nil
package.loaded["alc_shapes.t"]       = nil
package.loaded["alc_shapes.check"]   = nil
package.loaded["alc_shapes.reflect"] = nil
package.loaded["alc_shapes.luacats"] = nil

local S = require("alc_shapes")
local T = S.T

describe("alc_shapes.check basic types", function()
    it("passes matching primitives", function()
        local ok = S.check("hi", T.string)
        expect(ok).to.equal(true)
        expect(S.check(42, T.number)).to.equal(true)
        expect(S.check(true, T.boolean)).to.equal(true)
        expect(S.check({}, T.table)).to.equal(true)
    end)

    it("fails on type mismatch with expected/got reason", function()
        local ok, reason = S.check(42, T.string)
        expect(ok).to.equal(false)
        expect(reason:match("expected string")).to.exist()
        expect(reason:match("got number")).to.exist()
    end)

    it("reports JSONPath $ root on top-level violation", function()
        local _, reason = S.check(42, T.string)
        expect(reason:match("at %$:")).to.exist()
    end)
end)

describe("alc_shapes.check any / optional", function()
    it("any passes anything including nil", function()
        expect(S.check(nil, T.any)).to.equal(true)
        expect(S.check({}, T.any)).to.equal(true)
        expect(S.check("x", T.any)).to.equal(true)
    end)

    it("optional passes nil, validates non-nil", function()
        local sch = T.string:is_optional()
        expect(S.check(nil, sch)).to.equal(true)
        expect(S.check("x", sch)).to.equal(true)
        local ok, reason = S.check(42, sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected string")).to.exist()
    end)
end)

describe("alc_shapes.check shape", function()
    local sch = T.shape({
        answer = T.string,
        n      = T.number:is_optional(),
    })

    it("passes when required fields match", function()
        expect(S.check({ answer = "hi" }, sch)).to.equal(true)
        expect(S.check({ answer = "hi", n = 3 }, sch)).to.equal(true)
    end)

    it("ignores extra keys when open=true (default)", function()
        expect(S.check({ answer = "hi", extra = 1 }, sch)).to.equal(true)
    end)

    it("rejects extra keys when open=false", function()
        local strict = T.shape({ a = T.string }, { open = false })
        local ok, reason = S.check({ a = "x", extra = 1 }, strict)
        expect(ok).to.equal(false)
        expect(reason:match("unexpected field")).to.exist()
    end)

    it("fails when required field missing, with JSONPath", function()
        local ok, reason = S.check({}, sch)
        expect(ok).to.equal(false)
        expect(reason:match("%$%.answer")).to.exist()
    end)

    it("reports nested path for inner shape violation", function()
        local nested = T.shape({
            outer = T.shape({ inner = T.string }),
        })
        local ok, reason = S.check({ outer = { inner = 42 } }, nested)
        expect(ok).to.equal(false)
        expect(reason:match("%$%.outer%.inner")).to.exist()
    end)
end)

describe("alc_shapes.check array_of", function()
    it("passes matching array", function()
        expect(S.check({ "a", "b" }, T.array_of(T.string))).to.equal(true)
    end)

    it("uses 1-based index in path on element failure", function()
        local ok, reason = S.check({ "a", 2, "c" }, T.array_of(T.string))
        expect(ok).to.equal(false)
        -- second element (1-based index 2) fails
        expect(reason:match("%$%[2%]")).to.exist()
    end)

    it("fails when value is not a table", function()
        local ok, reason = S.check("notarray", T.array_of(T.string))
        expect(ok).to.equal(false)
        expect(reason:match("expected table")).to.exist()
    end)
end)

describe("alc_shapes.check one_of", function()
    local sch = T.one_of({ "a", "b" })

    it("passes exact literal match", function()
        expect(S.check("a", sch)).to.equal(true)
        expect(S.check("b", sch)).to.equal(true)
    end)

    it("fails on other values", function()
        local ok, reason = S.check("c", sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected one of")).to.exist()
    end)
end)

describe("alc_shapes.check described passthrough", function()
    it("passes if inner passes, fails if inner fails", function()
        local sch = T.string:describe("user name")
        expect(S.check("ok", sch)).to.equal(true)
        local ok = S.check(42, sch)
        expect(ok).to.equal(false)
    end)
end)

describe("alc_shapes.assert behavior", function()
    it("returns value on pass (chainable)", function()
        local v = S.assert({ answer = "hi" }, T.shape({ answer = T.string }))
        expect(v.answer).to.equal("hi")
    end)

    it("throws on fail with reason + ctx hint", function()
        local ok, err = pcall(S.assert, 42, T.string, "at caller")
        expect(ok).to.equal(false)
        expect(err:match("expected string")).to.exist()
        expect(err:match("ctx: at caller")).to.exist()
    end)

    it("pass-through for nil schema", function()
        expect(S.assert({ a = 1 }, nil)).to.exist()
    end)

    it("pass-through for 'any' string", function()
        local v = S.assert({ a = 1 }, "any")
        expect(type(v)).to.equal("table")
    end)

    it("loud-fails on unknown shape name", function()
        local ok, err = pcall(S.assert, {}, "totally_undefined_shape_xyz")
        expect(ok).to.equal(false)
        expect(err:match("unknown shape")).to.exist()
    end)
end)

describe("alc_shapes.is_dev_mode / assert_dev", function()
    it("is_dev_mode depends on ALC_SHAPE_CHECK env", function()
        local active = (os.getenv("ALC_SHAPE_CHECK") == "1")
        expect(S.is_dev_mode()).to.equal(active)
    end)

    it("assert_dev is no-op pass when dev mode is off", function()
        -- monkey-patch is_dev_mode to force dev OFF
        local check_mod = require("alc_shapes.check")
        local saved = check_mod.is_dev_mode
        check_mod.is_dev_mode = function() return false end
        -- would normally loud-fail on unknown shape name
        local v = check_mod.assert_dev({ x = 1 }, "totally_undefined_xyz", "h")
        expect(type(v)).to.equal("table")
        check_mod.is_dev_mode = saved
    end)

    it("assert_dev throws when dev mode is on and schema fails", function()
        local check_mod = require("alc_shapes.check")
        local saved = check_mod.is_dev_mode
        check_mod.is_dev_mode = function() return true end
        local ok = pcall(check_mod.assert_dev, 42, T.string, "h")
        check_mod.is_dev_mode = saved
        expect(ok).to.equal(false)
    end)
end)
