--- Tests for the Schema-as-Data persistence invariant.
---
--- Proves that alc_shapes schemas are fully reflectable / validatable
--- without their combinator metatables attached. This is the property
--- that makes them serialisable (JSON / any table-transport format)
--- round-trippable without loss.
---
--- See alc_shapes/README.md §Core concept — Schema-as-Data §2 Persistable.

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp),
-- which injects `lust` as a global and prepends `search_paths` to
-- package.path:
--   mcp__lua-debugger__test_launch(
--     code_file    = "tests/test_alc_shapes_persist.lua",
--     search_paths = ["."],
--   )
-- Local opt-in (optional): with bjornbytes/lust on your LUA_PATH,
-- run `lua5.4 tests/test_alc_shapes_persist.lua` from the repo root.

package.loaded["alc_shapes"]         = nil
package.loaded["alc_shapes.t"]       = nil
package.loaded["alc_shapes.check"]   = nil
package.loaded["alc_shapes.reflect"] = nil
package.loaded["alc_shapes.luacats"] = nil

local S = require("alc_shapes")
local T = S.T

--- Deep-copy a schema stripping all metatables (simulates a
--- JSON-encode → decode round trip, where the decoded side has
--- no Lua metatables attached).
local function strip_metatables(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do
        out[k] = strip_metatables(sub)
    end
    return out  -- note: no setmetatable
end

describe("Schema-as-Data: persistence invariant", function()
    it("check still passes after stripping metatables (primitive)", function()
        local plain = strip_metatables(T.string)
        expect(getmetatable(plain)).to.equal(nil)
        expect(S.check("hi", plain)).to.equal(true)
        local ok, reason = S.check(42, plain)
        expect(ok).to.equal(false)
        expect(reason:match("expected string")).to.exist()
    end)

    it("check still passes after stripping metatables (nested shape)", function()
        local schema = T.shape({
            a = T.string,
            b = T.number:is_optional(),
            c = T.array_of(T.shape({ x = T.boolean })),
        })
        local plain = strip_metatables(schema)
        expect(getmetatable(plain)).to.equal(nil)
        expect(getmetatable(plain.fields.a)).to.equal(nil)
        expect(getmetatable(plain.fields.b)).to.equal(nil)

        expect(S.check({ a = "ok", c = {{ x = true }} }, plain)).to.equal(true)
        local ok, reason = S.check({ a = 1, c = {} }, plain)
        expect(ok).to.equal(false)
        expect(reason:match("%.a")).to.exist()
    end)

    it("check still passes for every registered shape after stripping", function()
        local registered = {
            "voted", "paneled", "assessed", "calibrated",
            "tournament", "listwise_ranked", "pairwise_ranked",
            "funnel_ranked", "safe_paneled",
        }
        for _, name in ipairs(registered) do
            local plain = strip_metatables(S[name])
            expect(getmetatable(plain)).to.equal(nil)
            -- The point is not that an empty table passes, but that
            -- `check` does not blow up on a metatable-less schema.
            local ok, reason = S.check({}, plain)
            -- result is expected to be false (shape has required fields),
            -- but it must be a clean schema-violation reason, not a
            -- Lua error about `__index` / missing method.
            expect(type(ok)).to.equal("boolean")
            expect(ok == false or ok == true).to.equal(true)
            if not ok then
                expect(reason:match("shape violation")).to.exist()
            end
        end
    end)

    it("reflect.fields still works after stripping metatables", function()
        local schema = T.shape({
            a = T.string:describe("first"),
            b = T.number:is_optional(),
        })
        local plain = strip_metatables(schema)
        local entries = S.fields(plain)
        expect(#entries).to.equal(2)
        expect(entries[1].name).to.equal("a")
        expect(entries[1].doc).to.equal("first")
        expect(entries[2].name).to.equal("b")
        expect(entries[2].optional).to.equal(true)
    end)

    it("reflect.walk still descends after stripping metatables", function()
        local schema = T.shape({
            a = T.array_of(T.map_of(T.string, T.number)),
        })
        local plain = strip_metatables(schema)
        local kinds = {}
        S.walk(plain, function(node) kinds[#kinds + 1] = node.kind end)
        -- Root shape + field a (array_of) + its elem (map_of) + map key + map val
        expect(#kinds >= 5).to.equal(true)
        expect(kinds[1]).to.equal("shape")
        local has_map = false
        for _, k in ipairs(kinds) do
            if k == "map_of" then has_map = true end
        end
        expect(has_map).to.equal(true)
    end)

    it("luacats.class_for still works after stripping metatables", function()
        local schema = T.shape({
            answer = T.string,
            votes  = T.array_of(T.string),
        })
        local plain = strip_metatables(schema)
        local out = S.LuaCats.class_for("TestVoted", plain)
        expect(out:match("---@class TestVoted")).to.exist()
        expect(out:match("---@field answer string")).to.exist()
        expect(out:match("---@field votes string%[%]")).to.exist()
    end)

    it("T.ref still resolves after stripping metatables", function()
        local r = strip_metatables(T.ref("voted"))
        expect(getmetatable(r)).to.equal(nil)
        -- registered voted schema has required fields; an empty table
        -- should fail the resolved check (not a Lua-level error).
        local ok, reason = S.check({}, r)
        expect(ok).to.equal(false)
        expect(reason:match("shape violation")).to.exist()
    end)
end)
