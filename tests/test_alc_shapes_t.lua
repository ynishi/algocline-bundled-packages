--- Tests for alc_shapes.t — DSL combinators and schema internal structure.

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

package.loaded["alc_shapes.t"] = nil
local T = require("alc_shapes.t")

describe("alc_shapes.t primitives", function()
    it("exposes primitive singletons with kind='prim'", function()
        expect(T.string.kind).to.equal("prim")
        expect(T.string.prim).to.equal("string")
        expect(T.number.kind).to.equal("prim")
        expect(T.number.prim).to.equal("number")
        expect(T.boolean.kind).to.equal("prim")
        expect(T.boolean.prim).to.equal("boolean")
        expect(T.table.kind).to.equal("prim")
        expect(T.table.prim).to.equal("table")
    end)

    it("exposes any as kind='any'", function()
        expect(T.any.kind).to.equal("any")
    end)

    it("reuses the same singleton object across accesses", function()
        expect(T.string == T.string).to.equal(true)
        expect(T.number == T.number).to.equal(true)
    end)

    it("has all fields reachable via rawget (no metatable-__index delegation)", function()
        expect(rawget(T.string, "kind")).to.equal("prim")
        expect(rawget(T.string, "prim")).to.equal("string")
        expect(rawget(T.any, "kind")).to.equal("any")
    end)
end)

describe("alc_shapes.t.shape", function()
    it("stores fields and open flag as plain fields", function()
        local s = T.shape({ a = T.string, b = T.number })
        expect(rawget(s, "kind")).to.equal("shape")
        expect(type(rawget(s, "fields"))).to.equal("table")
        expect(rawget(s, "fields").a).to.equal(T.string)
        expect(rawget(s, "fields").b).to.equal(T.number)
        expect(rawget(s, "open")).to.equal(true)
    end)

    it("defaults open=true when opts absent", function()
        local s = T.shape({ a = T.string })
        expect(s.open).to.equal(true)
    end)

    it("honors opts.open=false when provided", function()
        local s = T.shape({ a = T.string }, { open = false })
        expect(s.open).to.equal(false)
    end)

    it("supports nested shapes", function()
        local inner = T.shape({ x = T.number })
        local outer = T.shape({ inner = inner })
        expect(outer.fields.inner).to.equal(inner)
        expect(outer.fields.inner.kind).to.equal("shape")
    end)

    it("fails on nil fields", function()
        local ok, err = pcall(T.shape, nil)
        expect(ok).to.equal(false)
        expect(err:match("alc_shapes%.t")).to.exist()
    end)

    it("fails on non-schema field value", function()
        local ok, err = pcall(T.shape, { bad = "not a schema" })
        expect(ok).to.equal(false)
        expect(err:match("must be a schema")).to.exist()
    end)

    it("fails on non-string field name", function()
        local ok = pcall(T.shape, { [1] = T.string })
        expect(ok).to.equal(false)
    end)
end)

describe("alc_shapes.t.array_of", function()
    it("wraps elem as plain field", function()
        local s = T.array_of(T.string)
        expect(rawget(s, "kind")).to.equal("array_of")
        expect(rawget(s, "elem")).to.equal(T.string)
    end)

    it("fails on non-schema elem", function()
        local ok, err = pcall(T.array_of, "not a schema")
        expect(ok).to.equal(false)
        expect(err:match("alc_shapes%.t")).to.exist()
    end)

    it("fails on nil elem", function()
        local ok = pcall(T.array_of, nil)
        expect(ok).to.equal(false)
    end)
end)

describe("alc_shapes.t.one_of", function()
    it("stores values as plain field array", function()
        local s = T.one_of({ "a", "b", "c" })
        expect(rawget(s, "kind")).to.equal("one_of")
        local vs = rawget(s, "values")
        expect(vs[1]).to.equal("a")
        expect(vs[2]).to.equal("b")
        expect(vs[3]).to.equal("c")
    end)

    it("accepts number and boolean literals", function()
        local s = T.one_of({ 1, 2, true })
        expect(s.values[1]).to.equal(1)
        expect(s.values[3]).to.equal(true)
    end)

    it("fails on nil values", function()
        local ok = pcall(T.one_of, nil)
        expect(ok).to.equal(false)
    end)

    it("fails on empty values table", function()
        local ok, err = pcall(T.one_of, {})
        expect(ok).to.equal(false)
        expect(err:match("at least one")).to.exist()
    end)

    it("fails on non-literal value", function()
        local ok, err = pcall(T.one_of, { {} })
        expect(ok).to.equal(false)
        expect(err:match("string/number/boolean")).to.exist()
    end)
end)

describe("alc_shapes.t :is_optional combinator", function()
    it("returns a new schema with kind='optional' wrapping inner", function()
        local opt = T.string:is_optional()
        expect(opt.kind).to.equal("optional")
        expect(opt.inner).to.equal(T.string)
    end)

    it("chains with array_of", function()
        local s = T.array_of(T.string):is_optional()
        expect(s.kind).to.equal("optional")
        expect(s.inner.kind).to.equal("array_of")
        expect(s.inner.elem).to.equal(T.string)
    end)

    it("does not mutate the underlying singleton", function()
        local before_kind = rawget(T.string, "kind")
        local _ = T.string:is_optional()
        expect(rawget(T.string, "kind")).to.equal(before_kind)
        expect(T.string.kind).to.equal("prim")
    end)
end)

describe("alc_shapes.t :describe combinator", function()
    it("returns a new schema with kind='described' carrying doc", function()
        local s = T.string:describe("user name")
        expect(s.kind).to.equal("described")
        expect(s.doc).to.equal("user name")
        expect(s.inner).to.equal(T.string)
    end)

    it("chains with is_optional", function()
        local s = T.string:is_optional():describe("opt name")
        expect(s.kind).to.equal("described")
        expect(s.doc).to.equal("opt name")
        expect(s.inner.kind).to.equal("optional")
    end)

    it("fails on non-string doc", function()
        local ok, err = pcall(function() return T.string:describe(42) end)
        expect(ok).to.equal(false)
        expect(err:match("string doc")).to.exist()
    end)
end)

describe("alc_shapes.t rawget invariants", function()
    it("all combinator outputs have rawget-accessible kind", function()
        expect(rawget(T.string:is_optional(), "kind")).to.equal("optional")
        expect(rawget(T.string:describe("d"), "kind")).to.equal("described")
        expect(rawget(T.array_of(T.number), "kind")).to.equal("array_of")
        expect(rawget(T.shape({ a = T.string }), "kind")).to.equal("shape")
        expect(rawget(T.one_of({ "a" }), "kind")).to.equal("one_of")
    end)
end)
