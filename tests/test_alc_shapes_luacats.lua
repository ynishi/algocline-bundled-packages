--- Tests for alc_shapes.luacats — LuaCATS codegen.

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

    it("preserves array element optional as (T|nil)[] (Q2)", function()
        local sch = T.shape({ items = T.array_of(T.number:is_optional()) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field items %(number|nil%)%[%]")).to.exist()
    end)

    it("distinguishes optional-array from array-of-optional (Q2)", function()
        -- optional-outside: `items?` with inner number[]
        local a = T.shape({ items = T.array_of(T.number):is_optional() })
        local out_a = S.LuaCats.class_for("C", a)
        expect(out_a:match("---@field items%? number%[%]")).to.exist()
        -- optional-inside: `items` required but elements may be nil
        local b = T.shape({ items = T.array_of(T.number:is_optional()) })
        local out_b = S.LuaCats.class_for("C", b)
        expect(out_b:match("---@field items %(number|nil%)%[%]")).to.exist()
        -- and crucially, the optional-inside case must NOT carry `items?`
        expect(out_b:match("---@field items%?")).to_not.exist()
    end)

    it("treats described wrapper as transparent inside array_of (Q2)", function()
        local sch = T.shape({
            items = T.array_of(T.number:is_optional():describe("maybe count")),
        })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field items %(number|nil%)%[%]")).to.exist()
    end)

    it("maps one_of(strings) to quoted literal union", function()
        local sch = T.shape({ mode = T.one_of({ "a", "b" }) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match('---@field mode "a"|"b"')).to.exist()
    end)

    it("maps inline nested shape to bare table", function()
        local sch = T.shape({ inner = T.shape({ x = T.string }) })
        local out = S.LuaCats.class_for("C", sch)
        expect(out:match("---@field inner table")).to.exist()
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
end)
