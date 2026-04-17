--- tools.docs.projections — PkgInfo → derived artifacts.
---
--- Pure functions. Each projection takes a PkgInfo (or a collection)
--- and returns the rendered artifact as a string. No I/O.
---
--- Rendering variants (future): `shape_type_string` is the default
--- human-readable form for the Parameters table and frontmatter.
--- Alternate variants (LLM-compressed, luacats annotation form,
--- JSON dump for hub_entry) live alongside as separate projections
--- so that the same `TypeExpr` entity can render into any target.

local M = {}

-- ── helpers ────────────────────────────────────────────────────────────

local function escape_md_table_cell(s)
    -- Escape pipe so it doesn't break the table row.
    return (s:gsub("|", "\\|"))
end

local function escape_yaml_string(s)
    -- Minimal: escape double-quote and backslash for a "..."-wrapped YAML value.
    local out = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return out
end

-- ── TypeExpr → string projection ──────────────────────────────────────

--- Pretty-print a TypeExpr in the default human-readable form.
---
--- Examples:
---   { kind="primitive", name="string" }          → "string"
---   { kind="array_of", of={primitive "string"} } → "array of string"
---   { kind="map_of", key=..., val=... }          → "map of <K> to <V>"
---   { kind="shape", shape={fields=...} }         → "shape { f: T, g?: T, ... }"
---   { kind="one_of", values={"a","b"} }          → 'one_of("a","b")'
---   { kind="discriminated", tag="name", ... }    → 'discriminated by "name"'
---   { kind="label", name="paneled.Result" }      → "paneled.Result"
---
--- Nested `shape` is expanded inline per pipeline-spec §7.1:
---   "shape { task: string, score: number }". Optional fields carry
---   a trailing `?` on the field name.
---
--- This is the only place that materialises a TypeExpr as a human
--- string. Every caller — Parameters table, frontmatter result_shape,
--- and downstream consumers — goes through this projection, so that
--- shape formatting stays monotonic across surfaces.
function M.shape_type_string(type_expr)
    local k = type_expr.kind
    if k == "primitive" then
        return type_expr.name
    elseif k == "array_of" then
        return "array of " .. M.shape_type_string(type_expr.of)
    elseif k == "map_of" then
        return string.format("map of %s to %s",
            M.shape_type_string(type_expr.key),
            M.shape_type_string(type_expr.val))
    elseif k == "one_of" then
        local parts = {}
        for i = 1, #type_expr.values do
            local v = type_expr.values[i]
            if type(v) == "string" then
                parts[i] = string.format("%q", v)
            else
                parts[i] = tostring(v)
            end
        end
        return "one_of(" .. table.concat(parts, ", ") .. ")"
    elseif k == "shape" then
        local s = type_expr.shape
        if not s or not s.fields or #s.fields == 0 then
            return "shape { }"
        end
        local parts = {}
        for i = 1, #s.fields do
            local f = s.fields[i]
            local mark = f.optional and "?" or ""
            parts[i] = string.format(
                "%s%s: %s", f.name, mark, M.shape_type_string(f.type))
        end
        return "shape { " .. table.concat(parts, ", ") .. " }"
    elseif k == "discriminated" then
        return string.format('discriminated by "%s"', type_expr.tag)
    elseif k == "label" then
        return type_expr.name
    else
        return "?"
    end
end

--- YAML flow-plain scalars forbid a leading indicator (`-`, `?`, `:`,
--- `,`, `[`, `]`, `{`, `}`, `#`, `&`, `*`, `!`, `|`, `>`, `'`, `"`, `%`,
--- `@`, `` ` ``) and forbid `: ` / ` #` anywhere. Emit a quoted scalar
--- whenever any of these would break the plain form.
local function yaml_scalar(s)
    if s == "" then return '""' end
    local first = s:sub(1, 1)
    local needs_quote =
        first:match("[%-%?:,%[%]{}#&%*!|>'\"%%@`]") ~= nil
        or s:find(": ", 1, true) ~= nil
        or s:find(" #", 1, true) ~= nil
        or s:find("\n", 1, true) ~= nil
    if needs_quote then
        return '"' .. escape_yaml_string(s) .. '"'
    end
    return s
end

-- ── per-pkg narrative.md ───────────────────────────────────────────────

local function build_frontmatter(pkg_info)
    local id = pkg_info.identity
    local shape = pkg_info.shape
    local lines = { "---" }
    lines[#lines + 1] = "name: " .. yaml_scalar(id.name)
    if id.version and id.version ~= "" then
        lines[#lines + 1] = "version: " .. yaml_scalar(id.version)
    end
    if id.category and id.category ~= "" then
        lines[#lines + 1] = "category: " .. yaml_scalar(id.category)
    end
    if shape.result ~= nil then
        local result_str = M.shape_type_string(shape.result)
        if result_str ~= "" then
            lines[#lines + 1] = "result_shape: " .. yaml_scalar(result_str)
        end
    end
    if id.description and id.description ~= "" then
        -- description is always quoted: it's human prose and likely to
        -- contain `:` (em dash phrasing, package references, etc.)
        lines[#lines + 1] = string.format('description: "%s"',
                                          escape_yaml_string(id.description))
    end
    lines[#lines + 1] = "source: " .. yaml_scalar(id.source_path)
    lines[#lines + 1] = "generated: gen_docs (V0)"
    lines[#lines + 1] = "---"
    return table.concat(lines, "\n")
end

local function render_parameters_table(shape_input)
    local lines = {
        "## Parameters {#parameters}",
        "",
        "| key | type | required | description |",
        "|---|---|---|---|",
    }
    for i = 1, #shape_input.fields do
        local f = shape_input.fields[i]
        local req = f.optional and "optional" or "**required**"
        local type_str = M.shape_type_string(f.type)
        local doc = escape_md_table_cell(f.doc or "")
        lines[#lines + 1] = string.format(
            "| `ctx.%s` | %s | %s | %s |",
            f.name, type_str, req, doc)
    end
    return table.concat(lines, "\n")
end

local function render_toc(sections, has_parameters)
    if #sections == 0 and not has_parameters then
        return ""
    end
    local lines = { "## Contents", "" }
    for i = 1, #sections do
        local s = sections[i]
        local indent = string.rep("  ", s.level - 2)
        lines[#lines + 1] = string.format("%s- [%s](#%s)", indent, s.heading, s.anchor)
    end
    if has_parameters then
        lines[#lines + 1] = "- [Parameters](#parameters)"
    end
    return table.concat(lines, "\n")
end

function M.narrative_md(pkg_info)
    local id = pkg_info.identity
    local nar = pkg_info.narrative
    local shape = pkg_info.shape
    local has_params = shape.input ~= nil

    local parts = {}
    parts[#parts + 1] = build_frontmatter(pkg_info)
    parts[#parts + 1] = ""
    parts[#parts + 1] = "# " .. nar.title

    if nar.summary and nar.summary ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = "> " .. nar.summary
    end

    local toc = render_toc(nar.sections, has_params)
    if toc ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = toc
    end

    for i = 1, #nar.sections do
        local s = nar.sections[i]
        local hashes = string.rep("#", s.level)
        parts[#parts + 1] = ""
        parts[#parts + 1] = string.format("%s %s {#%s}", hashes, s.heading, s.anchor)
        if s.body_md and s.body_md ~= "" then
            parts[#parts + 1] = ""
            parts[#parts + 1] = s.body_md
        end
    end

    if #nar.sections == 0 and nar.summary == "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = "_(no additional narrative found)_"
    end

    if has_params then
        parts[#parts + 1] = ""
        parts[#parts + 1] = render_parameters_table(shape.input)
    end

    return table.concat(parts, "\n") .. "\n"
end

-- ── JSON encoder (minimal, pure Lua) ──────────────────────────────────
--
-- Only types produced by our PkgInfo entity are supported:
--   string / number / boolean / nil / table (as array or object).
-- An empty table serialises as `{}` (object) per spec §7.4 — PkgInfo
-- never produces empty arrays at the hub_entry boundary.
--
-- Output is deterministic: object keys are sorted alphabetically so
-- the hub_entry bytes are stable across runs (necessary for hub_index
-- caching / content-addressed storage).

local JSON_ESCAPES = {
    ['"']  = '\\"',  ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n',  ['\r'] = '\\r',  ['\t'] = '\\t',
}

local function json_escape_string(s)
    local out = s:gsub('[%z\1-\31\\"]', function(c)
        return JSON_ESCAPES[c] or string.format('\\u%04x', c:byte())
    end)
    return '"' .. out .. '"'
end

local function is_array(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return n > 0, n
end

local json_encode_value  -- forward

local function json_encode_array(t, n)
    local parts = {}
    for i = 1, n do
        parts[i] = json_encode_value(t[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function json_encode_object(t)
    local keys = {}
    for k, _ in pairs(t) do
        if type(k) ~= "string" then
            error("json_encode: object key must be a string, got " .. type(k))
        end
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[i] = json_escape_string(k) .. ":" .. json_encode_value(t[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function json_encode_value(v)
    local ty = type(v)
    if v == nil then
        return "null"
    elseif ty == "string" then
        return json_escape_string(v)
    elseif ty == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("json_encode: non-finite number is not JSON-representable")
        end
        return tostring(v)
    elseif ty == "boolean" then
        return v and "true" or "false"
    elseif ty == "table" then
        local arr, n = is_array(v)
        if arr then
            return json_encode_array(v, n)
        end
        return json_encode_object(v)
    else
        error("json_encode: unsupported type '" .. ty .. "'")
    end
end

local function json_encode(v)
    return json_encode_value(v)
end

-- ── TypeExpr / Shape → JSON form ──────────────────────────────────────

--- Convert a TypeExpr to a JSON-ready Lua table.
---
--- The hub_entry schema exposes TypeExpr structurally so that consumers
--- can walk the type tree without re-parsing the human string form.
--- Mirror the internal TypeExpr shape 1:1 — each `kind` becomes a JSON
--- object with its variant-specific fields.
local function type_expr_to_json(te)
    local k = te.kind
    if k == "primitive" then
        return { kind = "primitive", name = te.name }
    elseif k == "array_of" then
        return { kind = "array_of", of = type_expr_to_json(te.of) }
    elseif k == "map_of" then
        return {
            kind = "map_of",
            key  = type_expr_to_json(te.key),
            val  = type_expr_to_json(te.val),
        }
    elseif k == "one_of" then
        local values = {}
        for i = 1, #te.values do values[i] = te.values[i] end
        return { kind = "one_of", values = values }
    elseif k == "shape" then
        return { kind = "shape", shape = M.shape_to_json(te.shape) }
    elseif k == "discriminated" then
        local variants = {}
        for name, shape in pairs(te.variants) do
            variants[name] = M.shape_to_json(shape)
        end
        return { kind = "discriminated", tag = te.tag, variants = variants }
    elseif k == "label" then
        return { kind = "label", name = te.name }
    else
        error("type_expr_to_json: unknown kind '" .. tostring(k) .. "'")
    end
end

--- Convert a Shape to a JSON-ready Lua table.
function M.shape_to_json(shape)
    local fields = {}
    for i = 1, #shape.fields do
        local f = shape.fields[i]
        fields[i] = {
            name     = f.name,
            type     = type_expr_to_json(f.type),
            optional = f.optional and true or false,
            doc      = f.doc or "",
        }
    end
    return { fields = fields, open = shape.open and true or false }
end

-- ── hub_entry JSON projection (pipeline-spec §7.4) ────────────────────

--- Build the hub_entry JSON for one PkgInfo.
---
--- Schema (per pipeline-spec.md §7.4):
---   {
---     "name": str, "version": str, "category": str, "description": str,
---     "narrative_md": str,       -- full narrative.md (frontmatter included)
---     "input_shape":  Shape|null,
---     "result_shape": str|null   -- human-readable form via shape_type_string
---   }
---
--- The bytes are deterministic (keys sorted) so downstream hub_index
--- caching can content-address the JSON.
function M.hub_entry(pkg_info)
    local id  = pkg_info.identity
    local shp = pkg_info.shape
    local entry = {
        name         = id.name,
        version      = id.version or "",
        category     = id.category or "",
        description  = id.description or "",
        narrative_md = M.narrative_md(pkg_info),
    }
    if shp.input ~= nil then
        entry.input_shape = M.shape_to_json(shp.input)
    end
    if shp.result ~= nil then
        entry.result_shape = M.shape_type_string(shp.result)
    end
    return json_encode(entry)
end

-- ── llms.txt / llms-full.txt ──────────────────────────────────────────

--- Build the llms.txt index from a list of PkgInfo.
function M.llms_index(pkg_infos, opts)
    opts = opts or {}
    local header = opts.header or "# algocline"
    local tagline = opts.tagline or
        ("LLM amplification engine. Pure Lua strategies executed via " ..
         "`alc.run(ctx)`; this index lists every installed strategy " ..
         "package with a one-liner and a link to its full narrative.")

    local lines = { header, "", "> " .. tagline, "" }

    -- group by category
    local by_category = {}
    local categories = {}
    for i = 1, #pkg_infos do
        local p = pkg_infos[i]
        local cat = p.identity.category
        if cat == nil or cat == "" then cat = "uncategorized" end
        if not by_category[cat] then
            by_category[cat] = {}
            categories[#categories + 1] = cat
        end
        local bucket = by_category[cat]
        bucket[#bucket + 1] = p
    end
    table.sort(categories)

    for _, cat in ipairs(categories) do
        lines[#lines + 1] = "## " .. cat
        lines[#lines + 1] = ""
        local bucket = by_category[cat]
        table.sort(bucket, function(a, b) return a.identity.name < b.identity.name end)
        for _, p in ipairs(bucket) do
            local desc = p.identity.description or ""
            if #desc > 200 then desc = desc:sub(1, 197) .. "..." end
            lines[#lines + 1] = string.format(
                "- [%s](narrative/%s.md): %s",
                p.identity.name, p.identity.name, desc)
        end
        lines[#lines + 1] = ""
    end

    -- Trim trailing blank lines, add single final newline.
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    return table.concat(lines, "\n") .. "\n"
end

--- Concat all narrative.md bodies (frontmatter-free) into llms-full.txt.
---
--- Input: list of { name = "...", narrative_md = "..." }
function M.llms_full(entries, opts)
    opts = opts or {}
    local header = opts.header or "# algocline — full narrative index"
    local tagline = opts.tagline or
        ("Concatenation of every package narrative. Intended for bulk AI " ..
         "context injection; for selective access see `llms.txt`.")

    local lines = { header, "", "> " .. tagline, "" }

    -- stable order by pkg name
    table.sort(entries, function(a, b) return a.name < b.name end)
    for i = 1, #entries do
        local e = entries[i]
        lines[#lines + 1] = string.format("<!-- ── %s.md ── -->", e.name)
        lines[#lines + 1] = ""
        -- strip frontmatter block
        local body = e.narrative_md
        if body:sub(1, 4) == "---\n" then
            local _, close_idx = body:find("\n---\n", 5, true)
            if close_idx then
                body = body:sub(close_idx + 1)
            end
        end
        -- trim trailing newlines for concatenation
        body = body:gsub("%s+$", "")
        lines[#lines + 1] = body
        lines[#lines + 1] = ""
        lines[#lines + 1] = "---"
        lines[#lines + 1] = ""
    end

    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    return table.concat(lines, "\n") .. "\n"
end

M._internal = {
    build_frontmatter        = build_frontmatter,
    render_parameters_table  = render_parameters_table,
    render_toc               = render_toc,
    escape_yaml_string       = escape_yaml_string,
    escape_md_table_cell     = escape_md_table_cell,
    yaml_scalar              = yaml_scalar,
    json_encode              = json_encode,
    type_expr_to_json        = type_expr_to_json,
}

return M
