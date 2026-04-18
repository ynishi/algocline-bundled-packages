--- Tests for alc_shapes.t — DSL combinators and schema internal structure.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp),
-- which injects `lust` as a global and prepends `search_paths` to
-- package.path:
--   mcp__lua-debugger__test_launch(
--     code_file    = "tests/test_alc_shapes_t.lua",
--     search_paths = ["."],
--   )
-- Local opt-in (optional): with bjornbytes/lust on your LUA_PATH,
-- run `lua5.4 tests/test_alc_shapes_t.lua` from the repo root.

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

    it("C3: shallow-copies fields table (post-construction mutation isolated)", function()
        local f = { a = T.string }
        local s = T.shape(f)
        -- Mutating the caller's table after construction must not
        -- leak into the schema. Schema-as-Data doctrine treats
        -- schemas as immutable plain data.
        f.b = T.number
        expect(rawget(s, "fields").a).to.equal(T.string)
        expect(rawget(s, "fields").b).to.equal(nil)
        -- And vice versa: mutating the caller table must not be
        -- observable via the schema's own fields reference.
        f.a = T.boolean
        expect(rawget(s, "fields").a).to.equal(T.string)
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

    it("C1: rejects array_of(optional(T)) at construction", function()
        local ok, err = pcall(T.array_of, T.number:is_optional())
        expect(ok).to.equal(false)
        expect(err:match("array_of%(optional%(T%)%)")).to.exist()
    end)

    it("C1: rejects array_of(described(optional(T))) — peels described", function()
        local elem = T.number:is_optional():describe("maybe count")
        local ok, err = pcall(T.array_of, elem)
        expect(ok).to.equal(false)
        expect(err:match("array_of%(optional%(T%)%)")).to.exist()
    end)

    it("C1: rejects array_of(optional(T):describe(...)) — describe-outside order", function()
        -- `T.number:is_optional():describe("doc")` produces described(optional(T)).
        -- The opposite order `T.number:describe("doc"):is_optional()` produces
        -- optional(described(T)) — the peel loop stops at optional at the top
        -- level, so both forms are rejected.
        local elem_a = T.number:is_optional():describe("doc")
        local ok_a = pcall(T.array_of, elem_a)
        expect(ok_a).to.equal(false)
        local elem_b = T.number:describe("doc"):is_optional()
        local ok_b = pcall(T.array_of, elem_b)
        expect(ok_b).to.equal(false)
    end)

    it("C1: array_of(T):is_optional() (outer optional) is still allowed", function()
        -- Nil-admission at the enclosing field is the recommended pattern.
        local s = T.array_of(T.number):is_optional()
        expect(rawget(s, "kind")).to.equal("optional")
        expect(rawget(rawget(s, "inner"), "kind")).to.equal("array_of")
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

    it("C5: rejects duplicate string values", function()
        local ok, err = pcall(T.one_of, { "a", "b", "a" })
        expect(ok).to.equal(false)
        expect(err:match("duplicate")).to.exist()
    end)

    it("C5: rejects duplicate number values", function()
        local ok, err = pcall(T.one_of, { 1, 2, 1 })
        expect(ok).to.equal(false)
        expect(err:match("duplicate")).to.exist()
    end)

    it("C5: distinguishes string \"1\" from number 1", function()
        -- Different Lua types at the same stringified form must not be
        -- flagged as duplicates. `one_of({"1", 1})` is legitimate even
        -- if unusual, since `check` uses `==` (type-sensitive) to match.
        local s = T.one_of({ "1", 1 })
        expect(rawget(s, "values")[1]).to.equal("1")
        expect(rawget(s, "values")[2]).to.equal(1)
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

describe("alc_shapes.t.map_of", function()
    it("stores key and val as plain fields", function()
        local s = T.map_of(T.string, T.number)
        expect(rawget(s, "kind")).to.equal("map_of")
        expect(rawget(s, "key")).to.equal(T.string)
        expect(rawget(s, "val")).to.equal(T.number)
    end)

    it("fails on non-schema key", function()
        local ok, err = pcall(T.map_of, "bad", T.number)
        expect(ok).to.equal(false)
        expect(err:match("key argument")).to.exist()
    end)

    it("fails on non-schema val", function()
        local ok, err = pcall(T.map_of, T.string, "bad")
        expect(ok).to.equal(false)
        expect(err:match("val argument")).to.exist()
    end)
end)

describe("alc_shapes.t.discriminated", function()
    it("stores tag and variants as plain fields", function()
        local s = T.discriminated("name", {
            a = T.shape({ name = T.string, x = T.number }),
        })
        expect(rawget(s, "kind")).to.equal("discriminated")
        expect(rawget(s, "tag")).to.equal("name")
        expect(type(rawget(s, "variants"))).to.equal("table")
    end)

    it("fails on empty tag", function()
        local ok, err = pcall(T.discriminated, "", { a = T.shape({ x = T.string }) })
        expect(ok).to.equal(false)
        expect(err:match("non%-empty string")).to.exist()
    end)

    it("fails on non-table variants", function()
        local ok = pcall(T.discriminated, "t", "bad")
        expect(ok).to.equal(false)
    end)

    it("fails on empty variants", function()
        local ok, err = pcall(T.discriminated, "t", {})
        expect(ok).to.equal(false)
        expect(err:match("at least one")).to.exist()
    end)

    it("fails when variant is not a shape", function()
        local ok, err = pcall(T.discriminated, "t", { a = T.string })
        expect(ok).to.equal(false)
        expect(err:match("must be a shape")).to.exist()
    end)

    it("C4: rejects variant missing the tag field", function()
        -- tag="name" but the variant shape has no `name` field. Before
        -- C4 this was silently accepted and the mismatch between the
        -- tag dispatch (by key) and the variant's own field set was
        -- invisible at construction.
        local ok, err = pcall(T.discriminated, "name", {
            a = T.shape({ x = T.number }),
        })
        expect(ok).to.equal(false)
        expect(err:match("must declare the tag field 'name'")).to.exist()
    end)

    it("C4: accepts variant with tag field as generic string", function()
        -- The enforcement is purely about presence. A variant that
        -- declares `name = T.string` (no literal constraint) still
        -- passes construction; runtime discriminant mismatch is caught
        -- by `handlers.discriminated` dispatch.
        local s = T.discriminated("name", {
            a = T.shape({ name = T.string, x = T.number }),
        })
        expect(rawget(s, "kind")).to.equal("discriminated")
    end)

    it("C3: shallow-copies variants table (post-construction mutation isolated)", function()
        local a_shape = T.shape({ name = T.string })
        local vs = { a = a_shape }
        local s = T.discriminated("name", vs)
        vs.b = T.shape({ name = T.string, x = T.number })
        expect(rawget(s, "variants").a).to.equal(a_shape)
        expect(rawget(s, "variants").b).to.equal(nil)
    end)
end)

describe("alc_shapes.t.ref", function()
    it("stores name as a plain field with kind='ref'", function()
        local r = T.ref("voted")
        expect(rawget(r, "kind")).to.equal("ref")
        expect(rawget(r, "name")).to.equal("voted")
    end)

    it("supports wrapper combinators (is_optional / describe)", function()
        local r = T.ref("voted"):is_optional()
        expect(rawget(r, "kind")).to.equal("optional")
        expect(rawget(rawget(r, "inner"), "kind")).to.equal("ref")
    end)

    it("fails on non-string name", function()
        local ok = pcall(T.ref, 42)
        expect(ok).to.equal(false)
    end)

    it("fails on empty name", function()
        local ok, err = pcall(T.ref, "")
        expect(ok).to.equal(false)
        expect(err:match("non%-empty string")).to.exist()
    end)
end)

describe("alc_shapes.t rawget invariants", function()
    it("all combinator outputs have rawget-accessible kind", function()
        expect(rawget(T.string:is_optional(), "kind")).to.equal("optional")
        expect(rawget(T.string:describe("d"), "kind")).to.equal("described")
        expect(rawget(T.array_of(T.number), "kind")).to.equal("array_of")
        expect(rawget(T.shape({ a = T.string }), "kind")).to.equal("shape")
        expect(rawget(T.one_of({ "a" }), "kind")).to.equal("one_of")
        expect(rawget(T.map_of(T.string, T.number), "kind")).to.equal("map_of")
        expect(rawget(T.discriminated("t", { a = T.shape({ t = T.string, x = T.string }) }), "kind")).to.equal("discriminated")
        expect(rawget(T.ref("voted"), "kind")).to.equal("ref")
    end)
end)
