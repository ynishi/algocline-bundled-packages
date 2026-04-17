--- Tests for tools.docs.* — Core Entity / Projections / end-to-end golden.
---
--- Coverage:
---   1. tools.docs.pkg_info  — constructor contract
---   2. tools.docs.extract   — docstring + section split + slugify
---   3. tools.docs.shape     — DSL → TypeExpr walker (peel, convert_shape)
---   4. tools.docs.projections — shape_type_string, frontmatter, Parameters
---                              table, narrative_md, llms_index, llms_full
---   5. end-to-end golden    — build_pkg_info("cot") → narrative_md equals
---                             the checked-in expected text

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
    "tools.docs.shape",
    "tools.docs.projections",
    "tools.docs.lint",
    "alc_shapes",
    "alc_shapes.t",
    "cot",
}) do
    package.loaded[name] = nil
end

local PI          = require("tools.docs.pkg_info")
local Extract     = require("tools.docs.extract")
local Shape       = require("tools.docs.shape")
local Projections = require("tools.docs.projections")
local Lint        = require("tools.docs.lint")
local S           = require("alc_shapes")
local T           = S.T

-- ─────────────────────────────────────────────────────────────────────
-- 1. pkg_info
-- ─────────────────────────────────────────────────────────────────────

describe("tools.docs.pkg_info", function()
    it("primitive() returns { kind='primitive', name=... }", function()
        local p = PI.primitive("string")
        expect(p.kind).to.equal("primitive")
        expect(p.name).to.equal("string")
    end)

    it("array_of() wraps an element TypeExpr", function()
        local a = PI.array_of(PI.primitive("number"))
        expect(a.kind).to.equal("array_of")
        expect(a.of.kind).to.equal("primitive")
        expect(a.of.name).to.equal("number")
    end)

    it("make_field() normalizes optional/doc to safe defaults", function()
        local f = PI.make_field("x", PI.primitive("string"))
        expect(f.name).to.equal("x")
        expect(f.optional).to.equal(false)
        expect(f.doc).to.equal("")
    end)

    it("make_shape() normalizes open to boolean", function()
        local s1 = PI.make_shape({}, nil)
        local s2 = PI.make_shape({}, true)
        expect(s1.open).to.equal(false)
        expect(s2.open).to.equal(true)
    end)

    it("one_of() copies the values array", function()
        local src = { "a", "b" }
        local got = PI.one_of(src)
        src[1] = "MUTATED"
        expect(got.values[1]).to.equal("a")
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

-- ─────────────────────────────────────────────────────────────────────
-- 3. shape
-- ─────────────────────────────────────────────────────────────────────

describe("tools.docs.shape.convert_shape", function()
    it("flattens T.shape into Field array sorted by name", function()
        local schema = T.shape({
            zeta = T.number,
            alpha = T.string,
        })
        local s = Shape.convert_shape(schema)
        expect(#s.fields).to.equal(2)
        expect(s.fields[1].name).to.equal("alpha")
        expect(s.fields[2].name).to.equal("zeta")
    end)

    it("peels optional wrapper into Field.optional=true", function()
        local schema = T.shape({
            x = T.string:is_optional(),
        })
        local s = Shape.convert_shape(schema)
        expect(s.fields[1].optional).to.equal(true)
    end)

    it("peels described wrapper into Field.doc", function()
        local schema = T.shape({
            x = T.number:describe("desc text"),
        })
        local s = Shape.convert_shape(schema)
        expect(s.fields[1].doc).to.equal("desc text")
    end)

    it("handles optional + described in either order", function()
        local schema = T.shape({
            a = T.string:is_optional():describe("A"),
            b = T.string:describe("B"):is_optional(),
        })
        local s = Shape.convert_shape(schema)
        expect(s.fields[1].optional).to.equal(true)
        expect(s.fields[1].doc).to.equal("A")
        expect(s.fields[2].optional).to.equal(true)
        expect(s.fields[2].doc).to.equal("B")
    end)

    it("preserves open flag", function()
        -- DSL default: open=true. Explicit { open=false } closes.
        local default_open = Shape.convert_shape(T.shape({ x = T.string }))
        local closed       = Shape.convert_shape(T.shape({ x = T.string }, { open = false }))
        expect(default_open.open).to.equal(true)
        expect(closed.open).to.equal(false)
    end)
end)

describe("tools.docs.extract.build_pkg_info (result_shape)", function()
    it("wraps a string result_shape as a `label` TypeExpr", function()
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
        expect(info.shape.result.kind).to.equal("label")
        expect(info.shape.result.name).to.equal("my.Result")
        -- Projection renders it back verbatim.
        expect(Projections.shape_type_string(info.shape.result))
            .to.equal("my.Result")
    end)

    it("converts a T.shape result_shape into a TypeExpr", function()
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
end)

describe("tools.docs.projections.shape_type_string", function()
    it("prints primitives by name", function()
        expect(Projections.shape_type_string(PI.primitive("string")))
            .to.equal("string")
    end)

    it("prints array_of as 'array of <elem>'", function()
        expect(Projections.shape_type_string(
            PI.array_of(PI.primitive("number"))))
            .to.equal("array of number")
    end)

    it("prints map_of with both key and val", function()
        local t = PI.map_of(PI.primitive("string"), PI.primitive("number"))
        expect(Projections.shape_type_string(t))
            .to.equal("map of string to number")
    end)

    it("prints one_of with quoted string literals", function()
        local t = PI.one_of({ "a", "b" })
        expect(Projections.shape_type_string(t)).to.equal('one_of("a", "b")')
    end)

    it("prints discriminated by its tag", function()
        local t = PI.discriminated("kind", {})
        expect(Projections.shape_type_string(t))
            .to.equal('discriminated by "kind"')
    end)

    it("prints label TypeExpr verbatim", function()
        expect(Projections.shape_type_string(PI.label("paneled.Result")))
            .to.equal("paneled.Result")
    end)

    it("expands nested shape inline per spec §7.1", function()
        local nested = PI.shape_ref(PI.make_shape({
            PI.make_field("task", PI.primitive("string"), false, ""),
            PI.make_field("score", PI.primitive("number"), false, ""),
        }, false))
        expect(Projections.shape_type_string(nested))
            .to.equal("shape { task: string, score: number }")
    end)

    it("marks optional fields with '?' in nested shape", function()
        local nested = PI.shape_ref(PI.make_shape({
            PI.make_field("name", PI.primitive("string"), false, ""),
            PI.make_field("note", PI.primitive("string"), true, ""),
        }, false))
        expect(Projections.shape_type_string(nested))
            .to.equal("shape { name: string, note?: string }")
    end)

    it("expands nested shape via convert_shape (DSL roundtrip)", function()
        local schema = T.shape({
            criterion = T.string:describe("criterion text"),
            name      = T.string,
        })
        local field_type = {
            kind = "shape", shape = Shape.convert_shape(schema),
        }
        -- fields are alphabetically sorted: criterion, name
        expect(Projections.shape_type_string(field_type))
            .to.equal("shape { criterion: string, name: string }")
    end)

    it("returns 'shape { }' for empty shape", function()
        local empty = PI.shape_ref(PI.make_shape({}, false))
        expect(Projections.shape_type_string(empty)).to.equal("shape { }")
    end)
end)

-- ─────────────────────────────────────────────────────────────────────
-- 4. projections
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
        { input = PI.make_shape({
              PI.make_field("k", PI.primitive("string"), false, "the k"),
          }, false),
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
        local nested_shape = PI.make_shape({
            PI.make_field("name", PI.primitive("string"), false, ""),
            PI.make_field("criterion", PI.primitive("string"), false, ""),
        }, false)
        local info = PI.make_pkg_info(
            { name = "z", version = "1", category = "c",
              description = "d", source_path = "z/init.lua" },
            { title = "Z", summary = "s", sections = {} },
            { input = PI.make_shape({
                PI.make_field("rubric",
                    PI.array_of({ kind = "shape", shape = nested_shape }),
                    true, "rubric dimensions"),
                PI.make_field("task", PI.primitive("string"), false, "the task"),
              }, false),
              result = nil }
        )
        local md = Projections.narrative_md(info)
        -- nested shape should be expanded, not collapsed to bare "shape".
        expect(md:find(
            "array of shape { name: string, criterion: string }",
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

describe("tools.docs.projections.llms_index", function()
    it("groups pkg by category alphabetically", function()
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
                input = PI.make_shape({
                    PI.make_field("k", PI.primitive("string"), false, ""),
                }, false),
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
        -- Shape: 2 fields, sorted (depth, task). depth is optional.
        expect(info.shape.input ~= nil).to.equal(true)
        expect(#info.shape.input.fields).to.equal(2)
        expect(info.shape.input.fields[1].name).to.equal("depth")
        expect(info.shape.input.fields[1].optional).to.equal(true)
        expect(info.shape.input.fields[2].name).to.equal("task")
        expect(info.shape.input.fields[2].optional).to.equal(false)
        -- Result shape is a TypeExpr; the projection renders it per §7.1.
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
