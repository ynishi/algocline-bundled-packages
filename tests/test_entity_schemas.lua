--- Tests for tools.docs.entity_schemas — Entity registry (Schema-as-Data).

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Run via the `lua-debugger` MCP server (binary: mlua-probe-mcp):
--   mcp__lua-debugger__test_launch(
--     code_file    = "tests/test_entity_schemas.lua",
--     search_paths = ["."],
--   )

package.loaded["alc_shapes"]              = nil
package.loaded["alc_shapes.t"]            = nil
package.loaded["alc_shapes.check"]        = nil
package.loaded["tools.docs.entity_schemas"] = nil
package.loaded["tools.docs.extract"]      = nil

local S  = require("alc_shapes")
local T  = S.T
local ES = require("tools.docs.entity_schemas")

-- Helpers ───────────────────────────────────────────────────────────────

local function ok_check(v, schema)
    return S.check(v, schema, { registry = ES })
end

local function valid_identity()
    return {
        name        = "cot",
        version     = "0.14.0",
        category    = "reasoning",
        description = "Chain-of-Thought strategy",
        source_path = "cot/init.lua",
    }
end

local function valid_section()
    return {
        level   = 2,
        heading = "Usage",
        anchor  = "usage",
        body_md = "some body",
    }
end

local function valid_narrative()
    return {
        title    = "cot",
        summary  = "Chain-of-Thought",
        sections = { valid_section() },
    }
end

local function valid_shape()
    return {
        input  = nil,
        result = T.ref("voted"),
    }
end

local function valid_pkg_info()
    return {
        identity  = valid_identity(),
        narrative = valid_narrative(),
        shape     = valid_shape(),
    }
end

-- Suites ────────────────────────────────────────────────────────────────

describe("entity_schemas: registry shape", function()
    it("is a plain table", function()
        expect(type(ES)).to.equal("table")
    end)

    it("exposes Identity / Section / Narrative / Shape / PkgInfo", function()
        expect(type(ES.Identity)).to.equal("table")
        expect(type(ES.Section)).to.equal("table")
        expect(type(ES.Narrative)).to.equal("table")
        expect(type(ES.Shape)).to.equal("table")
        expect(type(ES.PkgInfo)).to.equal("table")
    end)

    it("all entries are kind-tagged schemas", function()
        for _, name in ipairs({ "Identity", "Section", "Narrative", "Shape", "PkgInfo" }) do
            expect(S.is_schema(ES[name])).to.equal(true)
            expect(rawget(ES[name], "kind")).to.equal("shape")
        end
    end)
end)

describe("entity_schemas: Identity", function()
    it("accepts a well-formed identity", function()
        local ok, reason = ok_check(valid_identity(), ES.Identity)
        expect(ok).to.equal(true)
        expect(reason).to_not.exist()
    end)

    it("rejects missing description (EE1 regression guard)", function()
        local v = valid_identity()
        v.description = nil
        local ok, reason = ok_check(v, ES.Identity)
        expect(ok).to.equal(false)
        expect(reason:match("description")).to.exist()
    end)

    it("rejects extra fields (open=false)", function()
        local v = valid_identity()
        v.unexpected_field = "x"
        local ok, reason = ok_check(v, ES.Identity)
        expect(ok).to.equal(false)
        expect(reason:match("unexpected field")).to.exist()
    end)

    it("rejects non-string version", function()
        local v = valid_identity()
        v.version = 42
        local ok, reason = ok_check(v, ES.Identity)
        expect(ok).to.equal(false)
        expect(reason:match("version")).to.exist()
    end)
end)

describe("entity_schemas: Section", function()
    it("accepts level=2", function()
        local v = valid_section()
        v.level = 2
        expect(ok_check(v, ES.Section)).to.equal(true)
    end)

    it("accepts level=3", function()
        local v = valid_section()
        v.level = 3
        expect(ok_check(v, ES.Section)).to.equal(true)
    end)

    it("rejects level=1", function()
        local v = valid_section()
        v.level = 1
        local ok, reason = ok_check(v, ES.Section)
        expect(ok).to.equal(false)
        expect(reason:match("level")).to.exist()
    end)

    it("rejects level=4", function()
        local v = valid_section()
        v.level = 4
        local ok = ok_check(v, ES.Section)
        expect(ok).to.equal(false)
    end)

    it("rejects missing anchor", function()
        local v = valid_section()
        v.anchor = nil
        local ok, reason = ok_check(v, ES.Section)
        expect(ok).to.equal(false)
        expect(reason:match("anchor")).to.exist()
    end)
end)

describe("entity_schemas: Narrative", function()
    it("accepts empty sections array", function()
        local v = valid_narrative()
        v.sections = {}
        expect(ok_check(v, ES.Narrative)).to.equal(true)
    end)

    it("validates each section via T.ref('Section')", function()
        local v = valid_narrative()
        v.sections = { { level = 99, heading = "X", anchor = "x", body_md = "" } }
        local ok, reason = ok_check(v, ES.Narrative)
        expect(ok).to.equal(false)
        expect(reason:match("sections%[1%]%.level")).to.exist()
    end)

    it("rejects non-table sections", function()
        local v = valid_narrative()
        v.sections = "not a table"
        local ok = ok_check(v, ES.Narrative)
        expect(ok).to.equal(false)
    end)
end)

describe("entity_schemas: Shape", function()
    it("accepts nil input and nil result", function()
        expect(ok_check({ input = nil, result = nil }, ES.Shape)).to.equal(true)
    end)

    it("accepts T.shape value for input", function()
        local v = { input = T.shape({ x = T.string }), result = nil }
        expect(ok_check(v, ES.Shape)).to.equal(true)
    end)

    it("accepts T.ref value for result", function()
        local v = { input = nil, result = T.ref("voted") }
        expect(ok_check(v, ES.Shape)).to.equal(true)
    end)

    it("rejects a plain number as input (is_schema-ish guard)", function()
        local v = { input = 42, result = nil }
        local ok = ok_check(v, ES.Shape)
        expect(ok).to.equal(false)
    end)

    it("rejects a table without kind as input (is_schema-ish guard)", function()
        local v = { input = { not_a_schema = true }, result = nil }
        local ok, reason = ok_check(v, ES.Shape)
        expect(ok).to.equal(false)
        expect(reason:match("kind")).to.exist()
    end)

    it("rejects extra fields (open=false)", function()
        local v = { input = nil, result = nil, bogus = 1 }
        local ok, reason = ok_check(v, ES.Shape)
        expect(ok).to.equal(false)
        expect(reason:match("unexpected field")).to.exist()
    end)

    it("C6: rejects unknown kind at Entity boundary (no delayed fail)", function()
        -- Before C6, kind = T.string admitted `{kind = "garbage"}`, and
        -- the failure surfaced only later at check_node ("unknown kind").
        -- Entity strict policy requires the fail at the boundary itself.
        local v = { input = { kind = "garbage" }, result = nil }
        local ok, reason = ok_check(v, ES.Shape)
        expect(ok).to.equal(false)
        expect(reason:match("kind")).to.exist()
    end)

    it("C6: accepts every known alc_shapes kind", function()
        local known = {
            { kind = "prim", prim = "string" },
            { kind = "any" },
            { kind = "optional", inner = { kind = "prim", prim = "number" } },
            { kind = "described", doc = "x", inner = { kind = "prim", prim = "number" } },
            { kind = "shape", fields = {}, open = true },
            { kind = "array_of", elem = { kind = "prim", prim = "string" } },
            { kind = "one_of", values = { "a", "b" } },
            { kind = "map_of",
              key = { kind = "prim", prim = "string" },
              val = { kind = "prim", prim = "number" } },
            { kind = "discriminated", tag = "t", variants = {} },
            { kind = "ref", name = "foo" },
        }
        for _, sch in ipairs(known) do
            local ok = ok_check({ input = sch, result = nil }, ES.Shape)
            expect(ok).to.equal(true)
        end
    end)
end)

describe("entity_schemas: PkgInfo (composed)", function()
    it("accepts a well-formed PkgInfo", function()
        local ok, reason = ok_check(valid_pkg_info(), ES.PkgInfo)
        expect(ok).to.equal(true)
        expect(reason).to_not.exist()
    end)

    it("reports nested path on inner Identity violation", function()
        local v = valid_pkg_info()
        v.identity.description = nil
        local ok, reason = ok_check(v, ES.PkgInfo)
        expect(ok).to.equal(false)
        expect(reason:match("identity%.description")).to.exist()
    end)

    it("reports nested path on inner Section violation", function()
        local v = valid_pkg_info()
        v.narrative.sections[1].level = 9
        local ok, reason = ok_check(v, ES.PkgInfo)
        expect(ok).to.equal(false)
        expect(reason:match("narrative%.sections%[1%]%.level")).to.exist()
    end)

    it("uses the passed registry (does not leak into alc_shapes)", function()
        -- S.check with registry=ES must resolve "Identity" via ES, not
        -- via the alc_shapes module. Verify by checking that alc_shapes
        -- has no "Identity" key (this would shadow ES.Identity if it did).
        expect(S.Identity).to_not.exist()
    end)

    it("S.assert string-name honors registry=ES", function()
        expect(S.assert(valid_pkg_info(), "PkgInfo", "test-ctx",
            { registry = ES })).to.exist()
    end)

    it("S.assert loud-fails on unknown name in ES registry", function()
        local ok, err = pcall(S.assert, valid_pkg_info(), "NotAName",
            "test-ctx", { registry = ES })
        expect(ok).to.equal(false)
        expect(err:match("unknown shape name")).to.exist()
    end)
end)

-- Conformance ───────────────────────────────────────────────────────────
--
-- 全 pkg が extract.build_pkg_info を経由して EntitySchemas.PkgInfo に
-- 適合することを確認する。drift 再発防止が F-IF1 の核心。
--
-- pkg 列挙は `tools/gen_docs.lua:78` の list_pkgs ロジックを踏襲
-- (io.popen で {repo_root}/*/init.lua を走査)。

local function list_pkgs(repo_root)
    local cmd = string.format("ls -d %s/*/init.lua 2>/dev/null", repo_root)
    local handle = io.popen(cmd)
    if not handle then return {} end
    local pkgs = {}
    for line in handle:lines() do
        local pkg_name = line:match("([^/]+)/init%.lua$")
        if pkg_name then
            pkgs[#pkgs + 1] = {
                name        = pkg_name,
                init_path   = line,
                source_path = pkg_name .. "/init.lua",
            }
        end
    end
    handle:close()
    table.sort(pkgs, function(a, b) return a.name < b.name end)
    return pkgs
end

describe("conformance: every pkg produces a valid PkgInfo", function()
    local repo_root = os.getenv("PWD") or "."
    package.loaded["tools.docs.extract"] = nil
    local Extract = require("tools.docs.extract")
    local pkgs = list_pkgs(repo_root)

    it("list_pkgs finds at least one pkg", function()
        expect(#pkgs > 0).to.equal(true)
    end)

    for _, p in ipairs(pkgs) do
        it("PkgInfo for '" .. p.name .. "' conforms to EntitySchemas.PkgInfo",
            function()
                local ok_build, info_or_err = pcall(
                    Extract.build_pkg_info, p.name, p.init_path, p.source_path)
                if not ok_build then
                    local msg = tostring(info_or_err)
                    -- Same skip policy as gen_docs.lua:189 — library dirs
                    -- (alc_shapes 等) that lack M.meta are not pkgs.
                    if msg:find("no M.meta table", 1, true) then
                        return
                    end
                    error("build_pkg_info failed for '" .. p.name .. "': " .. msg, 0)
                end
                local pi = info_or_err
                local ok, reason = S.check(pi, ES.PkgInfo, { registry = ES })
                if not ok then
                    error("conformance violation for '" .. p.name .. "': " ..
                        tostring(reason), 0)
                end
                expect(ok).to.equal(true)
            end)
    end
end)
