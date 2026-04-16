--- Tests for alc_shapes.reflect — fields / walk.

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
package.loaded["alc_shapes.reflect"] = nil

local S = require("alc_shapes")
local T = S.T

describe("alc_shapes.reflect.fields", function()
    it("returns entries sorted by field name", function()
        local sch = T.shape({
            zulu  = T.string,
            alpha = T.number,
            mike  = T.boolean,
        })
        local entries = S.fields(sch)
        expect(#entries).to.equal(3)
        expect(entries[1].name).to.equal("alpha")
        expect(entries[2].name).to.equal("mike")
        expect(entries[3].name).to.equal("zulu")
    end)

    it("unwraps optional and reports optional=true", function()
        local sch = T.shape({
            name = T.string,
            age  = T.number:is_optional(),
        })
        local entries = S.fields(sch)
        local by = {}
        for _, e in ipairs(entries) do by[e.name] = e end
        expect(by.name.optional).to.equal(false)
        expect(by.age.optional).to.equal(true)
        -- inner type preserved
        expect(by.age.type.kind).to.equal("prim")
        expect(by.age.type.prim).to.equal("number")
    end)

    it("extracts doc from described wrap", function()
        local sch = T.shape({
            n = T.number:describe("count"),
        })
        local entries = S.fields(sch)
        expect(entries[1].doc).to.equal("count")
    end)

    it("handles described wrapping optional", function()
        local sch = T.shape({
            n = T.number:is_optional():describe("maybe count"),
        })
        local entries = S.fields(sch)
        expect(entries[1].optional).to.equal(true)
        expect(entries[1].doc).to.equal("maybe count")
        expect(entries[1].type.kind).to.equal("prim")
    end)

    it("errors when schema is not kind='shape'", function()
        local ok, err = pcall(S.fields, T.string)
        expect(ok).to.equal(false)
        expect(err:match("kind='shape'")).to.exist()
    end)

    it("works on a plain-table schema without combinator metatable", function()
        -- build a schema manually, no metatable — validates rawget-based impl.
        local raw = {
            kind   = "shape",
            fields = {
                name = { kind = "prim", prim = "string" },
            },
            open   = true,
        }
        local entries = S.fields(raw)
        expect(#entries).to.equal(1)
        expect(entries[1].name).to.equal("name")
        expect(entries[1].type.prim).to.equal("string")
    end)
end)

describe("alc_shapes.reflect.walk", function()
    it("visits every node in the tree", function()
        local sch = T.shape({
            a = T.string,
            b = T.array_of(T.number),
        })
        local kinds = {}
        S.walk(sch, function(node)
            kinds[#kinds + 1] = rawget(node, "kind")
        end)
        -- root shape + a:prim + b:array_of + b.elem:prim
        expect(#kinds >= 4).to.equal(true)
        -- root first
        expect(kinds[1]).to.equal("shape")
    end)

    it("descends into optional and described wrappers", function()
        local sch = T.shape({
            x = T.string:is_optional():describe("note"),
        })
        local seen_prim = false
        S.walk(sch, function(node)
            if rawget(node, "kind") == "prim" then seen_prim = true end
        end)
        expect(seen_prim).to.equal(true)
    end)

    it("errors on non-function visitor", function()
        local ok = pcall(S.walk, T.shape({ a = T.string }), "not a func")
        expect(ok).to.equal(false)
    end)
end)
