--- Tests for tools.docs.* — Core Entity / Projections / end-to-end golden.
---
--- Coverage:
---   1. tools.docs.pkg_info    — constructor contract (make_section /
---                               make_pkg_info)
---   2. tools.docs.extract     — docstring + section split + slugify +
---                               build_pkg_info result_shape handling
---   3. tools.docs.projections — shape_type_string, frontmatter,
---                               Parameters table, narrative_md,
---                               shape_to_json, hub_entry, llms_index,
---                               llms_full, context7, devin_wiki
---   4. tools.docs.lint        — V0 convention gate
---   5. end-to-end golden      — build_pkg_info("cot") → narrative_md
---                               equals the checked-in expected text

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Derive REPO from the first `?.lua` entry already prepended to
-- `package.path` by `mlua-probe-mcp`'s `search_paths`.
-- Using `os.getenv("PWD")` is unreliable under mlua-probe-mcp because the
-- server's startup CWD may differ from the worktree root; the `debug`
-- library is also unavailable in the sandbox.
local function repo_root_from_package_path()
    -- Look for the first "/?.lua" suffixed entry; its prefix is the repo.
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()

-- Force fresh load of every module under test.
for _, name in ipairs({
    "tools.docs.pkg_info",
    "tools.docs.extract",
    "tools.docs.projections",
    "tools.docs.lint",
    "alc_shapes",
    "alc_shapes.t",
    "alc_shapes.check",
    "alc_shapes.reflect",
    "cot",
}) do
    package.loaded[name] = nil
end

local PI          = require("tools.docs.pkg_info")
local Extract     = require("tools.docs.extract")
local Projections = require("tools.docs.projections")
local Lint        = require("tools.docs.lint")
local S           = require("alc_shapes")
local T           = S.T

-- ─────────────────────────────────────────────────────────────────────
-- 1. pkg_info — constructor contract
-- ─────────────────────────────────────────────────────────────────────

describe("tools.docs.pkg_info", function()
    it("make_section stores all four fields verbatim", function()
        local s = PI.make_section(2, "Heading", "heading", "body")
        expect(s.level).to.equal(2)
        expect(s.heading).to.equal("Heading")
        expect(s.anchor).to.equal("heading")
        expect(s.body_md).to.equal("body")
    end)

    it("make_pkg_info stores identity/narrative/shape", function()
        local id  = { name = "x", version = "1", category = "c",
                      description = "d", source_path = "x/init.lua" }
        local nar = { title = "T", summary = "", sections = {} }
        local shp = { input = nil, result = nil }
        local info = PI.make_pkg_info(id, nar, shp)
        expect(info.identity).to.equal(id)
        expect(info.narrative).to.equal(nar)
        expect(info.shape).to.equal(shp)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 2. extract
-- ─────────────────────────────────────────────────────────────────────

describe("tools.docs.extract.slugify", function()
    it("lowercases and hyphenates non-alnum runs", function()
        expect(Extract.slugify("Hello World")).to.equal("hello-world")
        expect(Extract.slugify("alc.llm() call")).to.equal("alc-llm-call")
    end)

    it("strips leading and trailing hyphens", function()
        expect(Extract.slugify("  foo  ")).to.equal("foo")
        expect(Extract.slugify("-bar-")).to.equal("bar")
    end)
end)

describe("tools.docs.extract.split_sections", function()
    it("returns empty structure on empty input", function()
        local title, summary, sections = Extract.split_sections("")
        expect(title).to.equal("")
        expect(summary).to.equal("")
        expect(#sections).to.equal(0)
    end)

    it("joins summary lines until blank or heading", function()
        local doc = table.concat({
            "Title line",
            "",
            "First summary line.",
            "Second summary line.",
            "",
            "## Details",
            "",
            "body content",
        }, "\n")
        local title, summary, sections = Extract.split_sections(doc)
        expect(title).to.equal("Title line")
        expect(summary).to.equal("First summary line. Second summary line.")
        expect(#sections).to.equal(1)
        expect(sections[1].level).to.equal(2)
        expect(sections[1].heading).to.equal("Details")
        expect(sections[1].anchor).to.equal("details")
        expect(sections[1].body_md).to.equal("body content")
    end)

    it("splits H2 and H3 sections, preserves body Markdown verbatim", function()
        local doc = table.concat({
            "T",
            "",
            "S",
            "",
            "## A",
            "",
            "a-body line 1",
            "",
            "a-body line 2",
            "",
            "### B",
            "",
            "b-body",
        }, "\n")
        local _, _, sections = Extract.split_sections(doc)
        expect(#sections).to.equal(2)
        expect(sections[1].heading).to.equal("A")
        expect(sections[1].body_md).to.equal("a-body line 1\n\na-body line 2")
        expect(sections[2].level).to.equal(3)
        expect(sections[2].heading).to.equal("B")
        expect(sections[2].body_md).to.equal("b-body")
    end)

    it("stops summary collection at a heading without a blank line", function()
        local doc = "Title\nsummary\n## Sec\nbody"
        local title, summary, sections = Extract.split_sections(doc)
        expect(title).to.equal("Title")
        expect(summary).to.equal("summary")
        expect(#sections).to.equal(1)
        expect(sections[1].heading).to.equal("Sec")
    end)

    it("disambiguates duplicate anchors deterministically", function()
        local doc = table.concat({
            "T", "", "S", "",
            "## References", "", "first",
            "", "## Other", "", "other body",
            "", "## References", "", "second",
            "", "## References", "", "third",
        }, "\n")
        local _, _, sections = Extract.split_sections(doc)
        expect(#sections).to.equal(4)
        expect(sections[1].heading).to.equal("References")
        expect(sections[1].anchor).to.equal("references")
        expect(sections[2].heading).to.equal("Other")
        expect(sections[2].anchor).to.equal("other")
        expect(sections[3].heading).to.equal("References")
        expect(sections[3].anchor).to.equal("references-2")
        expect(sections[4].heading).to.equal("References")
        expect(sections[4].anchor).to.equal("references-3")
    end)
end)

describe("tools.docs.extract.extract_docstring", function()
    it("terminates on ---@luadoc annotations", function()
        -- Write a temp file with a mixed docstring + luadoc + code.
        local tmp = os.tmpname()
        local f = io.open(tmp, "w")
        f:write("--- Title\n")
        f:write("--- body\n")
        f:write("---@param x string\n")
        f:write("--- should not be included\n")
        f:write("\n")
        f:write("local M = {}\n")
        f:close()
        local ds = Extract.extract_docstring(tmp)
        os.remove(tmp)
        expect(ds).to.equal("Title\nbody")
    end)
end)

describe("tools.docs.extract.build_pkg_info (result_shape)", function()
    it("wraps a string result_shape as a T.ref schema", function()
        -- Write a temp pkg with result_shape = "my.Result"
        local dir = os.tmpname()
        os.remove(dir); os.execute("mkdir -p " .. dir .. "/rs_str")
        local f = io.open(dir .. "/rs_str/init.lua", "w")
        f:write('local S = require("alc_shapes"); local T = S.T\n')
        f:write('local M = {}\n')
        f:write('M.meta = { name="rs_str", version="1", description="d", ')
        f:write('category="c", result_shape = "my.Result" }\n')
        f:write('function M.run(c) return c end\nreturn M\n')
        f:close()
        local saved = package.path
        package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. saved
        package.loaded["rs_str"] = nil
        local info = Extract.build_pkg_info(
            "rs_str", dir .. "/rs_str/init.lua", "rs_str/init.lua")
        package.path = saved
        os.execute("rm -rf " .. dir)
        expect(info.shape.result.kind).to.equal("ref")
        expect(info.shape.result.name).to.equal("my.Result")
        -- Projection renders it back verbatim.
        expect(Projections.shape_type_string(info.shape.result))
            .to.equal("my.Result")
    end)

    it("passes a T.shape result_shape through as-is", function()
        local dir = os.tmpname()
        os.remove(dir); os.execute("mkdir -p " .. dir .. "/rs_shape")
        local f = io.open(dir .. "/rs_shape/init.lua", "w")
        f:write('local S = require("alc_shapes"); local T = S.T\n')
        f:write('local M = {}\n')
        f:write('M.meta = { name="rs_shape", version="1", description="d", ')
        f:write('category="c", result_shape = T.shape({')
        f:write('chain = T.array_of(T.string),')
        f:write('conclusion = T.string,')
        f:write('}) }\n')
        f:write('function M.run(c) return c end\nreturn M\n')
        f:close()
        local saved = package.path
        package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. saved
        package.loaded["rs_shape"] = nil
        local info = Extract.build_pkg_info(
            "rs_shape", dir .. "/rs_shape/init.lua", "rs_shape/init.lua")
        package.path = saved
        os.execute("rm -rf " .. dir)
        expect(info.shape.result.kind).to.equal("shape")
        -- fields are alphabetically sorted: chain, conclusion
        expect(Projections.shape_type_string(info.shape.result)).to.equal(
            "shape { chain: array of string, conclusion: string }")
    end)

    it("rejects a non-string, non-schema result_shape", function()
        local dir = os.tmpname()
        os.remove(dir); os.execute("mkdir -p " .. dir .. "/rs_bad")
        local f = io.open(dir .. "/rs_bad/init.lua", "w")
        f:write('local M = {}\n')
        f:write('M.meta = { name="rs_bad", version="1", description="d", ')
        f:write('category="c", result_shape = 42 }\n')
        f:write('function M.run(c) return c end\nreturn M\n')
        f:close()
        local saved = package.path
        package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. saved
        package.loaded["rs_bad"] = nil
        local ok = pcall(Extract.build_pkg_info,
            "rs_bad", dir .. "/rs_bad/init.lua", "rs_bad/init.lua")
        package.path = saved
        os.execute("rm -rf " .. dir)
        expect(ok).to.equal(false)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 3. projections — shape_type_string
-- ─────────────────────────────────────────────────────────────────────

describe("tools.docs.projections.shape_type_string", function()
    it("prints primitives by their alc_shapes prim name", function()
        expect(Projections.shape_type_string(T.string)).to.equal("string")
        expect(Projections.shape_type_string(T.number)).to.equal("number")
        expect(Projections.shape_type_string(T.boolean)).to.equal("boolean")
        expect(Projections.shape_type_string(T.table)).to.equal("table")
    end)

    it("prints T.any as 'any'", function()
        expect(Projections.shape_type_string(T.any)).to.equal("any")
    end)

    it("prints array_of as 'array of <elem>'", function()
        expect(Projections.shape_type_string(T.array_of(T.number)))
            .to.equal("array of number")
    end)

    it("prints map_of with both key and val", function()
        expect(Projections.shape_type_string(T.map_of(T.string, T.number)))
            .to.equal("map of string to number")
    end)

    it("prints one_of with quoted string literals", function()
        expect(Projections.shape_type_string(T.one_of({ "a", "b" })))
            .to.equal('one_of("a", "b")')
    end)

    it("prints discriminated by its tag", function()
        local d = T.discriminated("kind", {
            a = T.shape({ kind = T.one_of({ "a" }) }),
        })
        expect(Projections.shape_type_string(d))
            .to.equal('discriminated by "kind"')
    end)

    it("prints T.ref verbatim by its name", function()
        expect(Projections.shape_type_string(T.ref("paneled.Result")))
            .to.equal("paneled.Result")
    end)

    it("expands nested shape inline with alphabetical field order", function()
        local nested = T.shape({
            task  = T.string,
            score = T.number,
        })
        -- alc_shapes fields are map-keyed and `reflect.fields` sorts by
        -- name: score, task.
        expect(Projections.shape_type_string(nested))
            .to.equal("shape { score: number, task: string }")
    end)

    it("marks optional fields with '?' in nested shape", function()
        local nested = T.shape({
            name = T.string,
            note = T.string:is_optional(),
        })
        expect(Projections.shape_type_string(nested))
            .to.equal("shape { name: string, note?: string }")
    end)

    it("peels described wrapper transparently when rendering", function()
        local sch = T.shape({
            criterion = T.string:describe("criterion text"),
            name      = T.string,
        })
        expect(Projections.shape_type_string(sch))
            .to.equal("shape { criterion: string, name: string }")
    end)

    it("peels optional/described at the entry point (top-level)", function()
        expect(Projections.shape_type_string(T.number:is_optional()))
            .to.equal("number")
        expect(Projections.shape_type_string(T.string:describe("d")))
            .to.equal("string")
        expect(Projections.shape_type_string(T.string:describe("d"):is_optional()))
            .to.equal("string")
    end)

    it("returns 'shape { }' for empty shape", function()
        expect(Projections.shape_type_string(T.shape({})))
            .to.equal("shape { }")
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 4. projections — narrative_md / parameters table / llms / json
-- ─────────────────────────────────────────────────────────────────────

local function sample_pkg_info()
    return PI.make_pkg_info(
        { name = "x", version = "1.0", category = "cat",
          description = "d", source_path = "x/init.lua" },
        { title = "X — title", summary = "sum",
          sections = {
              PI.make_section(2, "A", "a", "a-body"),
              PI.make_section(3, "B", "b", "b-body"),
          } },
        { input  = T.shape({ k = T.string:describe("the k") },
                           { open = false }),
          result = nil }
    )
end

describe("tools.docs.projections.narrative_md", function()
    it("emits frontmatter / title / summary / TOC / sections / Parameters", function()
        local md = Projections.narrative_md(sample_pkg_info())
        expect(md:find("name: x", 1, true) ~= nil).to.equal(true)
        expect(md:find("# X — title", 1, true) ~= nil).to.equal(true)
        expect(md:find("> sum", 1, true) ~= nil).to.equal(true)
        expect(md:find("## Contents", 1, true) ~= nil).to.equal(true)
        expect(md:find("- [A](#a)", 1, true) ~= nil).to.equal(true)
        expect(md:find("  - [B](#b)", 1, true) ~= nil).to.equal(true)
        expect(md:find("- [Parameters](#parameters)", 1, true) ~= nil).to.equal(true)
        expect(md:find("## A {#a}", 1, true) ~= nil).to.equal(true)
        expect(md:find("### B {#b}", 1, true) ~= nil).to.equal(true)
        expect(md:find("| `ctx.k` | string | **required** | the k |", 1, true) ~= nil)
            .to.equal(true)
    end)

    it("renders nested-shape field types inline in Parameters table", function()
        local info = PI.make_pkg_info(
            { name = "z", version = "1", category = "c",
              description = "d", source_path = "z/init.lua" },
            { title = "Z", summary = "s", sections = {} },
            { input  = T.shape({
                  rubric = T.array_of(T.shape({
                      criterion = T.string,
                      name      = T.string,
                  })):is_optional():describe("rubric dimensions"),
                  task = T.string:describe("the task"),
              }, { open = false }),
              result = nil }
        )
        local md = Projections.narrative_md(info)
        -- nested shape should be expanded, not collapsed to bare "shape".
        -- alc_shapes `fields` is a map: inner fields sort alphabetically.
        expect(md:find(
            "array of shape { criterion: string, name: string }",
            1, true) ~= nil).to.equal(true)
    end)

    it("skips TOC and Parameters when neither sections nor input exist", function()
        local info = PI.make_pkg_info(
            { name = "y", version = "0", category = "c",
              description = "d", source_path = "y/init.lua" },
            { title = "Y", summary = "s", sections = {} },
            { input = nil, result = nil }
        )
        local md = Projections.narrative_md(info)
        expect(md:find("## Contents", 1, true) == nil).to.equal(true)
        expect(md:find("## Parameters", 1, true) == nil).to.equal(true)
    end)
end)

describe("tools.docs.projections.llms_index_line", function()
    it("renders `- [name](narrative/name.md): description`", function()
        local info = PI.make_pkg_info(
            { name = "p", version = "1", category = "c",
              description = "a short description",
              source_path = "p/init.lua" },
            { title = "T", summary = "", sections = {} },
            { input = nil, result = nil })
        expect(Projections.llms_index_line(info))
            .to.equal("- [p](narrative/p.md): a short description")
    end)

    it("truncates descriptions longer than the max length", function()
        local max  = Projections._internal.LLMS_INDEX_DESC_MAX
        local long = string.rep("x", max + 50)
        local info = PI.make_pkg_info(
            { name = "p", version = "", category = "c",
              description = long, source_path = "p/init.lua" },
            { title = "T", summary = "", sections = {} },
            { input = nil, result = nil })
        local line = Projections.llms_index_line(info)
        -- tail must be "..." (truncation marker)
        expect(line:sub(-3)).to.equal("...")
        -- total desc segment is exactly max chars
        local _, colon_idx = line:find(": ", 1, true)
        local desc = line:sub(colon_idx + 1)
        expect(#desc).to.equal(max)
    end)

    it("honors href_prefix override", function()
        local info = PI.make_pkg_info(
            { name = "p", version = "", category = "c",
              description = "d", source_path = "p/init.lua" },
            { title = "T", summary = "", sections = {} },
            { input = nil, result = nil })
        expect(Projections.llms_index_line(info, { href_prefix = "pkg/" }))
            .to.equal("- [p](pkg/p.md): d")
    end)
end)

describe("tools.docs.projections.llms_full_chunk", function()
    it("wraps narrative_md body with the pkg marker and --- separator", function()
        local info = PI.make_pkg_info(
            { name = "q", version = "", category = "c",
              description = "d", source_path = "q/init.lua" },
            { title = "Q", summary = "s", sections = {} },
            { input = nil, result = nil })
        local md = "---\nname: q\n---\n\n# Q\n\n> s\n"
        local chunk = Projections.llms_full_chunk(info, md)
        expect(chunk:find("<!-- ── q.md ── -->", 1, true) ~= nil).to.equal(true)
        expect(chunk:find("# Q", 1, true) ~= nil).to.equal(true)
        -- frontmatter gone
        expect(chunk:find("name: q", 1, true) == nil).to.equal(true)
        -- ends with separator (no trailing newline — aggregator owns spacing)
        expect(chunk:sub(-3)).to.equal("---")
    end)

    it("renders narrative_md from PkgInfo when body omitted", function()
        local info = PI.make_pkg_info(
            { name = "r", version = "0", category = "c",
              description = "d", source_path = "r/init.lua" },
            { title = "R", summary = "s", sections = {} },
            { input = nil, result = nil })
        local chunk = Projections.llms_full_chunk(info)
        expect(chunk:find("<!-- ── r.md ── -->", 1, true) ~= nil).to.equal(true)
        expect(chunk:find("# R", 1, true) ~= nil).to.equal(true)
    end)
end)

describe("tools.docs.projections.strip_frontmatter", function()
    local strip = Projections._internal.strip_frontmatter

    it("removes a leading --- / --- block", function()
        expect(strip("---\nname: a\n---\n\n# A\n"))
            .to.equal("\n# A\n")
    end)

    it("is a no-op when no frontmatter", function()
        expect(strip("# A\n\n> s\n")).to.equal("# A\n\n> s\n")
    end)

    it("is a no-op when the closing fence is missing", function()
        local malformed = "---\nname: a\n# A\n"
        expect(strip(malformed)).to.equal(malformed)
    end)
end)

describe("tools.docs.projections.llms_index", function()
    it("groups pkg by category alphabetically via llms_index_line", function()
        local infos = {
            PI.make_pkg_info(
                { name = "p1", version = "", category = "zeta",
                  description = "d1", source_path = "p1/init.lua" },
                { title = "T", summary = "", sections = {} },
                { input = nil, result = nil }),
            PI.make_pkg_info(
                { name = "p2", version = "", category = "alpha",
                  description = "d2", source_path = "p2/init.lua" },
                { title = "T", summary = "", sections = {} },
                { input = nil, result = nil }),
        }
        local idx = Projections.llms_index(infos)
        local a = idx:find("## alpha", 1, true)
        local z = idx:find("## zeta", 1, true)
        expect(a ~= nil and z ~= nil).to.equal(true)
        expect(a < z).to.equal(true)
        expect(idx:find("- [p2](narrative/p2.md): d2", 1, true) ~= nil).to.equal(true)
    end)

    it("accepts PkgInfo directly in llms_full (sans pre-render)", function()
        local info = PI.make_pkg_info(
            { name = "p", version = "", category = "c",
              description = "d", source_path = "p/init.lua" },
            { title = "P", summary = "s", sections = {} },
            { input = nil, result = nil })
        local full = Projections.llms_full({ info })
        expect(full:find("<!-- ── p.md ── -->", 1, true) ~= nil).to.equal(true)
        expect(full:find("# P", 1, true) ~= nil).to.equal(true)
    end)
end)

describe("tools.docs.projections.json_encode", function()
    local json_encode = Projections._internal.json_encode

    it("encodes primitives", function()
        expect(json_encode("a")).to.equal('"a"')
        expect(json_encode(42)).to.equal("42")
        expect(json_encode(true)).to.equal("true")
        expect(json_encode(false)).to.equal("false")
        expect(json_encode(nil)).to.equal("null")
    end)

    it("escapes quote / backslash / control chars", function()
        expect(json_encode('a"b\\c')).to.equal([["a\"b\\c"]])
        expect(json_encode("a\nb\tc")).to.equal('"a\\nb\\tc"')
    end)

    it("sorts object keys alphabetically (deterministic output)", function()
        -- Same input under different insertion orders must hash equal.
        local a = json_encode({ z = 1, a = 2, m = 3 })
        local b = json_encode({ a = 2, m = 3, z = 1 })
        expect(a).to.equal(b)
        expect(a).to.equal('{"a":2,"m":3,"z":1}')
    end)

    it("encodes arrays 1..n preserving order", function()
        expect(json_encode({ "a", "b", "c" })).to.equal('["a","b","c"]')
    end)

    it("rejects mixed-key tables", function()
        local threw = pcall(json_encode, { [1] = "a", foo = "b" })
        expect(threw).to.equal(false)
    end)
end)

describe("tools.docs.projections.shape_to_json", function()
    it("dumps a flat T.shape with Field metadata (sorted)", function()
        local schema = T.shape({
            task  = T.string:describe("the task"),
            depth = T.number:is_optional():describe("optional"),
        }, { open = false })
        local got = Projections.shape_to_json(schema)
        expect(got.open).to.equal(false)
        expect(#got.fields).to.equal(2)
        -- alphabetical: depth < task
        expect(got.fields[1].name).to.equal("depth")
        expect(got.fields[1].optional).to.equal(true)
        expect(got.fields[1].doc).to.equal("optional")
        expect(got.fields[1].type.kind).to.equal("primitive")
        expect(got.fields[1].type.name).to.equal("number")
        expect(got.fields[2].name).to.equal("task")
        expect(got.fields[2].optional).to.equal(false)
        expect(got.fields[2].doc).to.equal("the task")
        expect(got.fields[2].type.kind).to.equal("primitive")
        expect(got.fields[2].type.name).to.equal("string")
    end)

    it("dumps a nested shape TypeExpr recursively", function()
        local schema = T.shape({
            nested = T.shape({ x = T.number }),
        }, { open = false })
        local got = Projections.shape_to_json(schema)
        expect(got.fields[1].type.kind).to.equal("shape")
        expect(got.fields[1].type.shape.fields[1].name).to.equal("x")
    end)

    it("dumps array_of / map_of / one_of / ref (as label)", function()
        local schema = T.shape({
            a = T.array_of(T.string),
            m = T.map_of(T.string, T.number),
            o = T.one_of({ "x", "y" }),
            l = T.ref("pkg.Result"),
        }, { open = false })
        local got = Projections.shape_to_json(schema)
        -- alphabetical: a, l, m, o
        expect(got.fields[1].name).to.equal("a")
        expect(got.fields[1].type.kind).to.equal("array_of")
        expect(got.fields[1].type.of.name).to.equal("string")
        expect(got.fields[2].name).to.equal("l")
        expect(got.fields[2].type.kind).to.equal("label")
        expect(got.fields[2].type.name).to.equal("pkg.Result")
        expect(got.fields[3].name).to.equal("m")
        expect(got.fields[3].type.kind).to.equal("map_of")
        expect(got.fields[3].type.key.name).to.equal("string")
        expect(got.fields[3].type.val.name).to.equal("number")
        expect(got.fields[4].name).to.equal("o")
        expect(got.fields[4].type.kind).to.equal("one_of")
        expect(got.fields[4].type.values[1]).to.equal("x")
    end)

    it("projects T.any as kind=primitive, name='any'", function()
        local schema = T.shape({ v = T.any })
        local got = Projections.shape_to_json(schema)
        expect(got.fields[1].type.kind).to.equal("primitive")
        expect(got.fields[1].type.name).to.equal("any")
    end)
end)

describe("tools.docs.projections.hub_entry", function()
    it("emits all required fields per spec §7.4", function()
        local info = PI.make_pkg_info(
            { name = "h", version = "1.2.3", category = "cat",
              description = "d", source_path = "h/init.lua" },
            { title = "H", summary = "sum", sections = {
                PI.make_section(2, "Usage", "usage", "body"),
              } },
            { input  = T.shape({ k = T.string:describe("the k") },
                               { open = false }),
              result = T.ref("h.Result") }
        )
        local json = Projections.hub_entry(info)
        -- Structural spot-checks (deterministic key order lets us grep).
        expect(json:find('"name":"h"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"version":"1.2.3"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"category":"cat"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"description":"d"', 1, true) ~= nil).to.equal(true)
        -- result_shape is now a kind-tagged JSON object (EE4). T.ref
        -- emits {kind:"label", name:"..."} — consumers dispatch on kind
        -- and look up `name` in the shape registry.
        expect(json:find(
            '"result_shape":{"kind":"label","name":"h.Result"}', 1, true) ~= nil)
            .to.equal(true)
        -- input_shape is a nested Shape JSON.
        expect(json:find('"input_shape":', 1, true) ~= nil).to.equal(true)
        expect(json:find('"kind":"primitive"', 1, true) ~= nil).to.equal(true)
        -- narrative_md escapes newlines as \n (embedded verbatim string).
        expect(json:find('"narrative_md":"', 1, true) ~= nil).to.equal(true)
        expect(json:find("\\n# H", 1, true) ~= nil).to.equal(true)
    end)

    it("emits result_shape as label JSON for T.ref (registry case)", function()
        local info = PI.make_pkg_info(
            { name = "r", version = "1", category = "c",
              description = "d", source_path = "r/init.lua" },
            { title = "R", summary = "s", sections = {} },
            { input = nil, result = T.ref("voted") }
        )
        local json = Projections.hub_entry(info)
        expect(json:find(
            '"result_shape":{"kind":"label","name":"voted"}', 1, true) ~= nil)
            .to.equal(true)
    end)

    it("emits result_shape as structured JSON for inline T.shape", function()
        local info = PI.make_pkg_info(
            { name = "i", version = "1", category = "c",
              description = "d", source_path = "i/init.lua" },
            { title = "I", summary = "s", sections = {} },
            { input = nil,
              result = T.shape({ chain = T.array_of(T.string) }) }
        )
        local json = Projections.hub_entry(info)
        -- result_shape must be a kind-tagged dict, not a string
        expect(json:find('"result_shape":{"kind":"shape"', 1, true) ~= nil)
            .to.equal(true)
        -- Inner structural visibility (arrays, primitives) must be walkable
        expect(json:find('"kind":"array_of"', 1, true) ~= nil).to.equal(true)
    end)

    it("omits input_shape / result_shape when nil", function()
        local info = PI.make_pkg_info(
            { name = "m", version = "0", category = "c",
              description = "d", source_path = "m/init.lua" },
            { title = "M", summary = "s", sections = {} },
            { input = nil, result = nil }
        )
        local json = Projections.hub_entry(info)
        expect(json:find('"input_shape"', 1, true) == nil).to.equal(true)
        expect(json:find('"result_shape"', 1, true) == nil).to.equal(true)
    end)

    it("is byte-deterministic across runs", function()
        local info = PI.make_pkg_info(
            { name = "d", version = "1", category = "c",
              description = "x", source_path = "d/init.lua" },
            { title = "D", summary = "s", sections = {} },
            { input = T.shape({
                z = T.string,
                a = T.number,
              }, { open = false }),
              result = nil }
        )
        local j1 = Projections.hub_entry(info)
        local j2 = Projections.hub_entry(info)
        expect(j1).to.equal(j2)
    end)
end)

describe("tools.docs.projections.context7_config", function()
    it("emits the fixed $schema and folders regardless of input", function()
        local json = Projections.context7_config({})
        expect(json:find(
            '"$schema":"https://context7.com/schema/context7.json"',
            1, true) ~= nil).to.equal(true)
        expect(json:find('"folders":["docs/narrative"]', 1, true) ~= nil)
            .to.equal(true)
    end)

    it("omits every optional field when not provided", function()
        local json = Projections.context7_config({})
        for _, k in ipairs({
            "projectTitle", "description", "branch", "excludeFolders",
            "excludeFiles", "rules", "previousVersions", "branchVersions",
        }) do
            expect(json:find('"' .. k .. '"', 1, true) == nil).to.equal(true)
        end
    end)

    it("preserves all human-curated fields", function()
        local json = Projections.context7_config({
            projectTitle     = "algocline",
            description      = "LLM amp",
            branch           = "main",
            excludeFolders   = { "tests", "tools" },
            excludeFiles     = { "CHANGELOG.md" },
            rules            = { "r1", "r2" },
            previousVersions = { { tag = "v0.13.0" } },
            branchVersions   = { { branch = "legacy" } },
        })
        expect(json:find('"projectTitle":"algocline"', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"description":"LLM amp"', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"branch":"main"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"excludeFolders":["tests","tools"]', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"excludeFiles":["CHANGELOG.md"]', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"rules":["r1","r2"]', 1, true) ~= nil).to.equal(true)
        expect(json:find('"previousVersions":[{"tag":"v0.13.0"}]', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"branchVersions":[{"branch":"legacy"}]', 1, true) ~= nil)
            .to.equal(true)
    end)

    it("is byte-deterministic across runs", function()
        local config = {
            projectTitle = "algocline",
            description  = "x",
            rules        = { "b", "a" },
        }
        expect(Projections.context7_config(config))
            .to.equal(Projections.context7_config(config))
    end)

    it("rejects non-table input", function()
        local ok = pcall(Projections.context7_config, "not a table")
        expect(ok).to.equal(false)
    end)

    it("rejects malformed previousVersions entries", function()
        local ok = pcall(Projections.context7_config, {
            previousVersions = { { branch = "wrong" } },
        })
        expect(ok).to.equal(false)
    end)

    it("rejects empty strings as if unset", function()
        local json = Projections.context7_config({
            projectTitle = "",
            description  = "",
            branch       = "",
        })
        expect(json:find('"projectTitle"', 1, true) == nil).to.equal(true)
        expect(json:find('"description"', 1, true) == nil).to.equal(true)
        expect(json:find('"branch"', 1, true) == nil).to.equal(true)
    end)

    it("tools/docs/context7_config.lua produces valid context7.json", function()
        package.loaded["tools.docs.context7_config"] = nil
        local config = require("tools.docs.context7_config")
        local json = Projections.context7_config(config)
        -- Smoke: the result is non-empty and contains the fixed fields.
        expect(type(json) == "string" and #json > 0).to.equal(true)
        expect(json:find(
            '"$schema":"https://context7.com/schema/context7.json"',
            1, true) ~= nil).to.equal(true)
        expect(json:find('"folders":["docs/narrative"]', 1, true) ~= nil)
            .to.equal(true)
        expect(json:find('"projectTitle":"algocline"', 1, true) ~= nil)
            .to.equal(true)
    end)
end)

describe("tools.docs.projections.devin_wiki", function()
    it("returns '{}' when config is empty", function()
        local json = Projections.devin_wiki({})
        expect(json).to.equal("{}")
    end)

    it("emits repo_notes with content (and optional author)", function()
        local json = Projections.devin_wiki({
            repo_notes = {
                { content = "hello" },
                { content = "world", author = "me" },
            },
        })
        expect(json:find('"repo_notes":', 1, true) ~= nil).to.equal(true)
        expect(json:find('"content":"hello"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"author":"me"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"content":"world"', 1, true) ~= nil).to.equal(true)
    end)

    it("emits pages with title / purpose / parent / page_notes", function()
        local json = Projections.devin_wiki({
            pages = {
                { title = "Arch",   purpose = "overview" },
                { title = "FE",     purpose = "frontend", parent = "Arch",
                  page_notes = { { content = "note-1" } } },
            },
        })
        expect(json:find('"title":"Arch"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"purpose":"overview"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"title":"FE"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"parent":"Arch"', 1, true) ~= nil).to.equal(true)
        expect(json:find('"page_notes":', 1, true) ~= nil).to.equal(true)
        expect(json:find('"content":"note-1"', 1, true) ~= nil).to.equal(true)
    end)

    it("is byte-deterministic across runs", function()
        local config = {
            repo_notes = { { content = "z" }, { content = "a" } },
            pages      = {
                { title = "B", purpose = "b" },
                { title = "A", purpose = "a" },
            },
        }
        expect(Projections.devin_wiki(config))
            .to.equal(Projections.devin_wiki(config))
    end)

    it("rejects non-table input", function()
        expect(pcall(Projections.devin_wiki, "x")).to.equal(false)
    end)

    it("rejects a repo_note missing content", function()
        expect(pcall(Projections.devin_wiki, {
            repo_notes = { { author = "me" } },
        })).to.equal(false)
    end)

    it("rejects a repo_note whose content exceeds the 10,000 char cap",
        function()
            expect(pcall(Projections.devin_wiki, {
                repo_notes = { { content = string.rep("x", 10001) } },
            })).to.equal(false)
        end)

    it("rejects a page missing title or purpose", function()
        expect(pcall(Projections.devin_wiki, {
            pages = { { title = "",  purpose = "p" } },
        })).to.equal(false)
        expect(pcall(Projections.devin_wiki, {
            pages = { { title = "T", purpose = "" } },
        })).to.equal(false)
    end)

    it("rejects duplicate page titles", function()
        expect(pcall(Projections.devin_wiki, {
            pages = {
                { title = "X", purpose = "a" },
                { title = "X", purpose = "b" },
            },
        })).to.equal(false)
    end)

    it("rejects pages over the 30-page cap", function()
        local pages = {}
        for i = 1, 31 do
            pages[i] = { title = "P" .. i, purpose = "p" }
        end
        expect(pcall(Projections.devin_wiki, { pages = pages })).to.equal(false)
    end)

    it("rejects combined notes over 100", function()
        local notes = {}
        for i = 1, 101 do notes[i] = { content = "n" } end
        expect(pcall(Projections.devin_wiki, { repo_notes = notes }))
            .to.equal(false)
    end)

    it("tools/docs/devin_wiki_config.lua produces valid .devin/wiki.json",
        function()
            package.loaded["tools.docs.devin_wiki_config"] = nil
            local config = require("tools.docs.devin_wiki_config")
            local json = Projections.devin_wiki(config)
            expect(type(json) == "string" and #json > 0).to.equal(true)
            expect(json:find('"repo_notes":', 1, true) ~= nil).to.equal(true)
            expect(json:find("docs/narrative", 1, true) ~= nil).to.equal(true)
            expect(json:find('"pages":', 1, true) == nil).to.equal(true)
        end)
end)

describe("tools.docs.projections.llms_full", function()
    it("concatenates entries with frontmatter stripped and pkg markers", function()
        local full = Projections.llms_full({
            { name = "a", narrative_md = "---\nname: a\n---\n\n# A\n\n> s\n" },
            { name = "b", narrative_md = "---\nname: b\n---\n\n# B\n\n> t\n" },
        })
        expect(full:find("<!-- ── a.md ── -->", 1, true) ~= nil).to.equal(true)
        expect(full:find("<!-- ── b.md ── -->", 1, true) ~= nil).to.equal(true)
        expect(full:find("# A", 1, true) ~= nil).to.equal(true)
        expect(full:find("name: a", 1, true) == nil).to.equal(true)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 4b. lint
-- ─────────────────────────────────────────────────────────────────────

local function minimal_info(overrides)
    local id = {
        name = "p", version = "1.0", category = "c",
        description = "d", source_path = "p/init.lua",
    }
    for k, v in pairs(overrides.identity or {}) do id[k] = v end
    local nar = overrides.narrative or {
        title = "T", summary = "s", sections = {},
    }
    local shp = overrides.shape or { input = nil, result = nil }
    return PI.make_pkg_info(id, nar, shp)
end

describe("tools.docs.lint", function()
    it("flags H1 in docstring as error", function()
        local info = minimal_info({})
        local r = Lint.check(info, "Title\n\n# H1 in body\n", "p")
        local errors = Lint.errors(r.violations)
        expect(#errors).to.equal(1)
        expect(errors[1].code).to.equal("E_H1_IN_DOCSTRING")
    end)

    it("flags missing meta fields", function()
        local info = minimal_info({ identity = { description = "" } })
        local r = Lint.check(info, "Title\n\nsummary\n", "p")
        local codes = {}
        for _, v in ipairs(r.violations) do codes[v.code] = true end
        expect(codes["E_META_MISSING_DESCRIPTION"]).to.equal(true)
    end)

    it("flags name/directory mismatch", function()
        local info = minimal_info({ identity = { name = "x" } })
        local r = Lint.check(info, "Title\n", "y")
        local codes = {}
        for _, v in ipairs(r.violations) do codes[v.code] = true end
        expect(codes["E_NAME_MISMATCH"]).to.equal(true)
    end)

    it("flags input_shape + Parameters section conflict", function()
        local info = minimal_info({
            narrative = {
                title = "T", summary = "s",
                sections = {
                    PI.make_section(2, "Parameters", "parameters", "body"),
                },
            },
            shape = {
                input  = T.shape({ k = T.string }, { open = false }),
                result = nil,
            },
        })
        local r = Lint.check(info, "T\n\ns\n\n## Parameters\n\nbody\n", "p")
        local codes = {}
        for _, v in ipairs(r.violations) do codes[v.code] = true end
        expect(codes["E_PARAMETERS_CONFLICT"]).to.equal(true)
    end)

    it("warns on fake 'Usage:' label", function()
        local info = minimal_info({})
        local r = Lint.check(info, "T\n\ns\n\nUsage:\n  code\n", "p")
        local warn_codes = {}
        for _, v in ipairs(r.violations) do
            if v.severity == "warning" then warn_codes[v.code] = true end
        end
        expect(warn_codes["W_FAKE_LABEL"]).to.equal(true)
    end)

    it("does NOT flag labels inside a fenced code block", function()
        local info = minimal_info({})
        local r = Lint.check(info, "T\n\ns\n\n```\nUsage:\n```\n", "p")
        for _, v in ipairs(r.violations) do
            expect(v.code == "W_FAKE_LABEL").to.equal(false)
        end
    end)

    it("warns on empty narrative", function()
        local info = minimal_info({
            narrative = { title = "T", summary = "", sections = {} },
        })
        local r = Lint.check(info, "T\n", "p")
        local warn_codes = {}
        for _, v in ipairs(r.violations) do
            if v.severity == "warning" then warn_codes[v.code] = true end
        end
        expect(warn_codes["W_EMPTY_NARRATIVE"]).to.equal(true)
    end)

    it("produces zero violations for a V0-clean pkg", function()
        local info = Extract.build_pkg_info(
            "cot", REPO .. "/cot/init.lua", "cot/init.lua")
        local docstring = Extract.extract_docstring(REPO .. "/cot/init.lua")
        local r = Lint.check(info, docstring, "cot")
        -- expected: 0 error and 0 warning on cot (the golden V0 fixture).
        expect(#r.violations).to.equal(0)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 5. end-to-end golden: cot
-- ─────────────────────────────────────────────────────────────────────

describe("end-to-end: build_pkg_info(cot) + narrative_md", function()
    it("produces the expected V0 narrative.md", function()
        local info = Extract.build_pkg_info(
            "cot", REPO .. "/cot/init.lua", "cot/init.lua")
        expect(info.identity.name).to.equal("cot")
        expect(info.identity.category).to.equal("reasoning")
        expect(info.narrative.title).to.equal("CoT — iterative chain-of-thought reasoning")
        -- Sections: Usage + Behavior (docstring order).
        expect(#info.narrative.sections).to.equal(2)
        expect(info.narrative.sections[1].heading).to.equal("Usage")
        expect(info.narrative.sections[1].anchor).to.equal("usage")
        expect(info.narrative.sections[2].heading).to.equal("Behavior")
        -- Shape: alc_shapes schema. Use S.fields to enumerate.
        expect(info.shape.input ~= nil).to.equal(true)
        expect(info.shape.input.kind).to.equal("shape")
        local input_fields = S.fields(info.shape.input)
        expect(#input_fields).to.equal(2)
        -- alphabetical: depth, task
        expect(input_fields[1].name).to.equal("depth")
        expect(input_fields[1].optional).to.equal(true)
        expect(input_fields[2].name).to.equal("task")
        expect(input_fields[2].optional).to.equal(false)
        -- Result shape is an alc_shapes schema; projection renders it per §7.1.
        expect(info.shape.result.kind).to.equal("shape")
        expect(Projections.shape_type_string(info.shape.result)).to.equal(
            "shape { chain: array of string, conclusion: string }")
        -- Rendering should at least include the TOC anchor + Parameters row.
        local md = Projections.narrative_md(info)
        expect(md:find("## Usage {#usage}", 1, true) ~= nil).to.equal(true)
        expect(md:find("```lua", 1, true) ~= nil).to.equal(true)
        expect(md:find("| `ctx.task` | string | **required**", 1, true) ~= nil)
            .to.equal(true)
        expect(md:find("| `ctx.depth` | number | optional", 1, true) ~= nil)
            .to.equal(true)
        -- Frontmatter quotes the expanded result_shape so YAML stays valid.
        expect(md:find(
            'result_shape: "shape { chain: array of string, conclusion: string }"',
            1, true) ~= nil).to.equal(true)
    end)
end)
