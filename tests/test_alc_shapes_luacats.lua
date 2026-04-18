--- Tests for alc_shapes.luacats — LuaCATS codegen.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp),
-- which injects `lust` as a global and prepends `search_paths` to
-- package.path:
--   mcp__lua-debugger__test_launch(
--     code_file    = "tests/test_alc_shapes_luacats.lua",
--     search_paths = ["."],
--   )
-- Local opt-in (optional): with bjornbytes/lust on your LUA_PATH,
-- run `lua5.4 tests/test_alc_shapes_luacats.lua` from the repo root.

package.loaded["alc_shapes"]         = nil
package.loaded["alc_shapes.t"]       = nil
package.loaded["alc_shapes.reflect"] = nil
package.loaded["alc_shapes.luacats"] = nil

local S = require("alc_shapes")
local T = S.T

describe("alc_shapes.LuaCats.class_for", function()
    it("emits @class header and @field lines", function()
        local sch = T.shape({
            answer = T.string,
            n      = T.number:is_optional(),
        })
        local out = S.LuaCats.class_for("AlcResultVoted", sch)
        expect(out:match("---@class AlcResultVoted")).to.exist()
        expect(out:match("---@field answer string")).to.exist()
        expect(out:match("---@field n%? number")).to.exist()
    end)

    it("sorts fields alphabetically (diff stability)", function()
        local sch = T.shape({
            zulu  = T.string,
            alpha = T.string,
        })
        local out = S.LuaCats.class_for("C", sch)
        local alpha_pos = out:find("alpha")
        local zulu_pos  = out:find("zulu")
        expect(alpha_pos and zulu_pos and alpha_pos < zulu_pos).to.equal(true)
    end)

    it("maps array_of(T) to T[]", function()
        local sch = T.shape({ items = T.array_of(T.string) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field items string%[%]")).to.exist()
    end)

    it("maps nested array_of(array_of(...))", function()
        local sch = T.shape({ grid = T.array_of(T.array_of(T.number)) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field grid number%[%]%[%]")).to.exist()
    end)

    it("renders plain-data array_of(optional) as (T|nil)[] for JSON round-trip (C1)", function()
        -- C1: the DSL rejects array_of(optional(T)) (see t.lua). But the
        -- codegen still has to handle a plain-data schema that bypasses
        -- the DSL (Schema-as-Data JSON round-trip from an external source).
        -- Construct the shape by hand to simulate that path.
        local sch = {
            kind = "shape",
            open = true,
            fields = {
                items = {
                    kind = "array_of",
                    elem = { kind = "optional", inner = { kind = "prim", prim = "number" } },
                },
            },
        }
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field items %(number|nil%)%[%]")).to.exist()
    end)

    it("optional-array (outer optional) renders as `items?` with T[] (C1)", function()
        local a = T.shape({ items = T.array_of(T.number):is_optional() })
        local out_a = S.LuaCats.class_for("C", a)
        expect(out_a:match("---@field items%? number%[%]")).to.exist()
    end)

    it("maps one_of(strings) to quoted literal union", function()
        local sch = T.shape({ mode = T.one_of({ "a", "b" }) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match('---@field mode "a"|"b"')).to.exist()
    end)

    it("maps map_of to table<K, V>", function()
        local sch = T.shape({ counts = T.map_of(T.string, T.number) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field counts table<string, number>")).to.exist()
    end)

    it("C2: renders single-variant discriminated as a single inline table", function()
        -- A 1-variant discriminated has no `|` at the top level, so the
        -- enclosing array_of must NOT wrap in parens.
        local sch = T.shape({
            stages = T.array_of(T.discriminated("name", {
                a = T.shape({ name = T.string }),
            })),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field stages { name: string }%[%]")).to.exist()
    end)

    it("C2: renders multi-variant discriminated as union of inline tables", function()
        local sch = T.shape({
            stages = T.discriminated("name", {
                b = T.shape({ name = T.one_of({ "b" }), y = T.number }),
                a = T.shape({ name = T.one_of({ "a" }), x = T.string }),
            }),
        })
        local out = S.LuaCats.class_for("C", sch)
        -- Variants sorted alphabetically (a then b) for diff stability.
        expect(out:match('---@field stages { name: "a", x: string }|{ name: "b", y: number }')).to.exist()
    end)

    it("C2: array_of(multi-variant discriminated) parenthesizes the union", function()
        -- Without parens LuaLS would parse `A|B[]` as `A|(B[])`.
        local sch = T.shape({
            stages = T.array_of(T.discriminated("name", {
                b = T.shape({ name = T.one_of({ "b" }), y = T.number }),
                a = T.shape({ name = T.one_of({ "a" }), x = T.string }),
            })),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match('---@field stages %({ name: "a", x: string }|{ name: "b", y: number }%)%[%]')).to.exist()
    end)

    it("C2: array_of(multi-value one_of) also parenthesizes the union", function()
        -- Same precedence issue as array_of(discriminated). `"a"|"b"[]`
        -- parses as `"a"|("b"[])`, not `("a"|"b")[]`.
        local sch = T.shape({ modes = T.array_of(T.one_of({ "a", "b" })) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match('---@field modes %("a"|"b"%)%[%]')).to.exist()
    end)

    it("C2: array_of(single-value one_of) does NOT parenthesize", function()
        -- A 1-value one_of has no `|`, so no parens needed.
        local sch = T.shape({ mode = T.array_of(T.one_of({ "a" })) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match('---@field mode "a"%[%]')).to.exist()
    end)

    it("inline-expands nested shape as LuaLS table literal", function()
        local sch = T.shape({ inner = T.shape({ x = T.string }) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner { x: string }")).to.exist()
    end)

    it("inline-expands nested shape with alphabetical field order", function()
        local sch = T.shape({
            inner = T.shape({
                zulu  = T.string,
                alpha = T.number,
            }),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner { alpha: number, zulu: string }")).to.exist()
    end)

    it("marks optional fields in inline shape with ?", function()
        local sch = T.shape({
            inner = T.shape({
                required_f = T.string,
                optional_f = T.number:is_optional(),
            }),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner { optional_f%?: number, required_f: string }")).to.exist()
    end)

    it("renders array_of(shape(...)) as inline table array `{ ... }[]`", function()
        local sch = T.shape({
            paths = T.array_of(T.shape({
                answer    = T.string:is_optional(),
                reasoning = T.string,
            })),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field paths { answer%?: string, reasoning: string }%[%]")).to.exist()
    end)

    it("nests array inside inline shape: { xs: string[] }", function()
        local sch = T.shape({
            inner = T.shape({ xs = T.array_of(T.string) }),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner { xs: string%[%] }")).to.exist()
    end)

    it("renders empty inline shape as bare `table` (no empty braces)", function()
        local sch = T.shape({ inner = T.shape({}) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner table")).to.exist()
        expect(out:match("---@field inner { }")).to_not.exist()
    end)

    it("peels described wrapper inside inline shape", function()
        local sch = T.shape({
            inner = T.shape({ x = T.string:describe("inner doc") }),
        })
        local out = S.LuaCats.class_for("C", sch)
        -- inner-field describe() text is intentionally dropped (LuaLS inline
        -- table literal syntax does not support per-field doc suffixes).
        expect(out:match("---@field inner { x: string }")).to.exist()
    end)

    it("appends described doc as @ suffix on the line", function()
        local sch = T.shape({ name = T.string:describe("user name") })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field name string @user name")).to.exist()
    end)

    it("ends with a newline", function()
        local out = S.LuaCats.class_for("C", T.shape({ a = T.string }))
        expect(out:sub(-1)).to.equal("\n")
    end)

    it("errors when schema is not kind='shape'", function()
        local ok = pcall(S.LuaCats.class_for, "C", T.string)
        expect(ok).to.equal(false)
    end)
end)

describe("alc_shapes.LuaCats.gen", function()
    it("emits only ---@meta header when dictionary is empty", function()
        local out = S.LuaCats.gen({}, "AlcResult")
        expect(out).to.equal("---@meta\n")
    end)

    it("handles nil shapes_table as empty", function()
        local out = S.LuaCats.gen(nil, "AlcResult")
        expect(out).to.equal("---@meta\n")
    end)

    it("emits one class per shape entry, pascal-cased", function()
        local shapes = {
            voted     = T.shape({ answer = T.string }),
            safe_out  = T.shape({ ok     = T.boolean }),
        }
        local out = S.LuaCats.gen(shapes, "AlcResult")
        expect(out:match("---@class AlcResultVoted")).to.exist()
        expect(out:match("---@class AlcResultSafeOut")).to.exist()
    end)

    it("emits classes in sorted name order", function()
        local shapes = {
            zulu  = T.shape({ a = T.string }),
            alpha = T.shape({ a = T.string }),
        }
        local out = S.LuaCats.gen(shapes, "AlcResult")
        local alpha_pos = out:find("AlcResultAlpha")
        local zulu_pos  = out:find("AlcResultZulu")
        expect(alpha_pos and zulu_pos and alpha_pos < zulu_pos).to.equal(true)
    end)

    it("ends output with a single newline", function()
        local shapes = { voted = T.shape({ a = T.string }) }
        local out = S.LuaCats.gen(shapes, "AlcResult")
        expect(out:sub(-1)).to.equal("\n")
        -- not terminated with blank line
        expect(out:sub(-2, -2) == "\n").to.equal(false)
    end)

    it("skips non-shape entries in the table silently", function()
        local shapes = {
            voted = T.shape({ a = T.string }),
            check = function() end,  -- e.g. a re-exported function
            T     = T,                -- combinator namespace
        }
        local ok, out = pcall(S.LuaCats.gen, shapes, "AlcResult")
        expect(ok).to.equal(true)
        expect(out:match("AlcResultVoted")).to.exist()
    end)

    it("renders ref(name) as <prefix><PascalCase(name)>", function()
        local shapes = {
            voted    = T.shape({ a = T.string }),
            wrapper  = T.shape({ inner = T.ref("voted") }),
        }
        local out = S.LuaCats.gen(shapes, "AlcResult")
        expect(out:match("---@field inner AlcResultVoted")).to.exist()
    end)

    it("honours class_prefix for ref resolution", function()
        local shapes = {
            voted   = T.shape({ a = T.string }),
            wrapper = T.shape({ inner = T.ref("voted") }),
        }
        local out = S.LuaCats.gen(shapes, "MyPkg")
        expect(out:match("---@field inner MyPkgVoted")).to.exist()
    end)
end)
