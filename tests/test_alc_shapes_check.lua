--- Tests for alc_shapes.check — validator.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp),
-- which injects `lust` as a global and prepends `search_paths` to
-- package.path:
--   mcp__lua-debugger__test_launch(
--     code_file    = "tests/test_alc_shapes_check.lua",
--     search_paths = ["."],
--   )
-- Local opt-in (optional): with bjornbytes/lust on your LUA_PATH,
-- run `lua5.4 tests/test_alc_shapes_check.lua` from the repo root.

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

describe("alc_shapes.check map_of", function()
    local sch = T.map_of(T.string, T.number)

    it("passes valid string->number map", function()
        expect(S.check({ tokyo = 3, paris = 2 }, sch)).to.equal(true)
    end)

    it("passes empty table", function()
        expect(S.check({}, sch)).to.equal(true)
    end)

    it("fails when value is not a table", function()
        local ok, reason = S.check("notmap", sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected table")).to.exist()
    end)

    it("fails on wrong value type", function()
        local ok, reason = S.check({ a = "notnum" }, sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected number")).to.exist()
    end)

    it("fails on wrong key type (integer key)", function()
        local bad = {}
        bad[1] = 42
        local ok, reason = S.check(bad, sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected string")).to.exist()
    end)
end)

describe("alc_shapes.check discriminated", function()
    local sch = T.discriminated("name", {
        alpha = T.shape({ name = T.one_of({"alpha"}), x = T.number }),
        beta  = T.shape({ name = T.one_of({"beta"}),  y = T.string }),
    })

    it("passes correct variant (alpha)", function()
        expect(S.check({ name = "alpha", x = 42 }, sch)).to.equal(true)
    end)

    it("passes correct variant (beta)", function()
        expect(S.check({ name = "beta", y = "hi" }, sch)).to.equal(true)
    end)

    it("fails when discriminant field is missing", function()
        local ok, reason = S.check({ x = 42 }, sch)
        expect(ok).to.equal(false)
        expect(reason:match("missing discriminant")).to.exist()
    end)

    it("fails on unknown discriminant value", function()
        local ok, reason = S.check({ name = "gamma" }, sch)
        expect(ok).to.equal(false)
        expect(reason:match("not in")).to.exist()
    end)

    it("validates variant-specific fields", function()
        local ok, reason = S.check({ name = "alpha", x = "notnum" }, sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected number")).to.exist()
    end)

    it("fails when value is not a table", function()
        local ok, reason = S.check("notatable", sch)
        expect(ok).to.equal(false)
        expect(reason:match("expected table")).to.exist()
    end)

    it("works inside array_of", function()
        local arr_sch = T.array_of(sch)
        local ok = S.check({
            { name = "alpha", x = 1 },
            { name = "beta",  y = "z" },
        }, arr_sch)
        expect(ok).to.equal(true)
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

describe("alc_shapes.check determinism (Q1)", function()
    it("reports the alphabetically-first failing field across multiple violations", function()
        -- All three fields are non-strings; sorted iteration must report 'alpha' first.
        local sch = T.shape({
            zulu  = T.string,
            alpha = T.string,
            mike  = T.string,
        })
        local _, reason = S.check({ zulu = 1, alpha = 2, mike = 3 }, sch)
        expect(reason:match("%$%.alpha")).to.exist()
        expect(reason:match("%$%.zulu")).to_not.exist()
    end)

    it("reports alphabetically-first unexpected key under strict mode", function()
        local strict = T.shape({ a = T.string }, { open = false })
        local _, reason = S.check({ a = "x", zulu = 1, alpha = 2 }, strict)
        expect(reason:match("%$%.alpha")).to.exist()
        expect(reason:match("%$%.zulu")).to_not.exist()
    end)
end)

describe("alc_shapes reserved-name guard (Q3)", function()
    local internal = require("alc_shapes")._internal

    it("exposes the reserved-name list", function()
        expect(type(internal.RESERVED_SHAPE_NAMES)).to.equal("table")
        expect(internal.RESERVED_SHAPE_NAMES[1]).to.equal("any")
    end)

    it("rejects a module that registers 'any' as a shape", function()
        local fake = { any = T.shape({ x = T.string }) }
        local ok, err = pcall(internal.assert_no_reserved_shapes, fake)
        expect(ok).to.equal(false)
        expect(err:match("reserved")).to.exist()
        expect(err:match("'any'")).to.exist()
    end)

    it("tolerates non-shape values under reserved names (e.g. a function)", function()
        local fake = { any = function() end }
        local ok = pcall(internal.assert_no_reserved_shapes, fake)
        expect(ok).to.equal(true)
    end)

    it("tolerates the current module (P0 dict is empty)", function()
        local ok = pcall(internal.assert_no_reserved_shapes, require("alc_shapes"))
        expect(ok).to.equal(true)
    end)
end)

describe("alc_shapes.check ref", function()
    it("resolves ref against the alc_shapes registry", function()
        local r = T.ref("voted")
        local good = {
            consensus       = "majority answer",
            paths           = {},
            votes           = {},
            vote_counts     = {},
            n_sampled       = 3,
            total_llm_calls = 3,
        }
        expect(S.check(good, r)).to.equal(true)
    end)

    it("fails with ref path intact when the target shape rejects", function()
        local r = T.ref("voted")
        local bad = {
            consensus       = 42,  -- wrong type
            paths           = {},
            votes           = {},
            vote_counts     = {},
            n_sampled       = 3,
            total_llm_calls = 3,
        }
        local ok, reason = S.check(bad, r)
        expect(ok).to.equal(false)
        expect(reason:match("consensus")).to.exist()
    end)

    it("fails with 'unresolved ref' when name is not in the registry", function()
        local r = T.ref("does_not_exist_xyz")
        local ok, reason = S.check({}, r)
        expect(ok).to.equal(false)
        expect(reason:match("unresolved ref")).to.exist()
        expect(reason:match("does_not_exist_xyz")).to.exist()
    end)
end)

describe("alc_shapes.check opts.registry (Schema-as-Data registry)", function()
    -- A registry is a plain `{name → schema}` table. Closures NG.
    local entity_registry = {
        Identity = T.shape({
            name    = T.string,
            version = T.string,
        }, { open = false }),
        PkgInfo  = T.shape({
            identity = T.ref("Identity"),
        }, { open = false }),
    }

    it("resolves T.ref against a caller-supplied registry", function()
        local pi = {
            identity = { name = "cot", version = "0.1.0" },
        }
        local ok = S.check(pi, T.ref("PkgInfo"), { registry = entity_registry })
        expect(ok).to.equal(true)
    end)

    it("does not leak the alc_shapes registry into a custom one", function()
        -- 'voted' lives in alc_shapes default registry; entity_registry
        -- has no 'voted'. With opts.registry passed, the default must
        -- NOT be consulted as a fallback (otherwise registries are not
        -- truly isolated).
        local ok, reason = S.check({}, T.ref("voted"), { registry = entity_registry })
        expect(ok).to.equal(false)
        expect(reason:match("unresolved ref 'voted'")).to.exist()
    end)

    it("falls back to alc_shapes default when opts is omitted", function()
        local good = {
            consensus       = "x",
            paths           = {},
            votes           = {},
            vote_counts     = {},
            n_sampled       = 1,
            total_llm_calls = 1,
        }
        expect(S.check(good, T.ref("voted"))).to.equal(true)
    end)

    it("rejects a closure as opts.registry (Schema-as-Data invariant)", function()
        local closure_registry = function(name) return entity_registry[name] end
        local ok_call, err = pcall(function()
            S.check({}, T.ref("PkgInfo"), { registry = closure_registry })
        end)
        expect(ok_call).to.equal(false)
        expect(tostring(err):match("plain table")).to.exist()
    end)

    it("rejects opts itself if not a table", function()
        local ok_call, err = pcall(function()
            S.check({}, T.string, "not a table")
        end)
        expect(ok_call).to.equal(false)
        expect(tostring(err):match("opts must be a table")).to.exist()
    end)

    it("S.assert string-name lookup honors opts.registry", function()
        local ok_call, err = pcall(function()
            S.assert({ identity = { name = "x", version = "0" } },
                "PkgInfo", "ctx-hint", { registry = entity_registry })
        end)
        expect(ok_call).to.equal(true)
        expect(err).to.equal(nil)
    end)

    it("S.assert string-name with custom registry loud-fails on unknown", function()
        local ok_call, err = pcall(function()
            S.assert({}, "voted", "ctx-hint", { registry = entity_registry })
        end)
        expect(ok_call).to.equal(false)
        expect(tostring(err):match("unknown shape name 'voted'")).to.exist()
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
