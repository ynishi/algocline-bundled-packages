--- tools.docs.extract — init.lua → PkgInfo.narrative + identity.
---
--- Responsibilities:
---   1. Read `{pkg}/init.lua` from disk.
---   2. Strip the leading `---` block → raw Markdown docstring.
---   3. Split the docstring by V0 convention:
---        * line 1        → narrative.title
---        * lines until the first blank → narrative.summary
---        * `## X` / `### X` → sections[] with body_md verbatim
---   4. Load the pkg via `require` to read `M.meta` (shape DSL
---      evaluated, no regex parsing).
---
--- Heuristic-free. V0 convention violations are detected separately
--- by `tools.docs.lint`; this module reports the literal structure.
---
--- Single-AST doctrine: `meta.input_shape` / `meta.result_shape` are
--- alc_shapes schemas and flow through unchanged. A string
--- `meta.result_shape` is wrapped as `T.ref(name)` so every downstream
--- consumer sees a uniform kind-tagged schema.

local PI = require("tools.docs.pkg_info")
local T  = require("alc_shapes.t")

local M = {}

-- ── low-level file I/O ─────────────────────────────────────────────────

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then
        error(string.format(
            "tools.docs.extract: cannot open '%s': %s", path, tostring(err)), 2)
    end
    local content = f:read("*a")
    f:close()
    return content
end

--- Split string by "\n" keeping lines (no trailing "\n" on each).
local function split_lines(s)
    local lines = {}
    local i = 1
    local len = #s
    while i <= len do
        local j = s:find("\n", i, true)
        if not j then
            lines[#lines + 1] = s:sub(i)
            break
        end
        lines[#lines + 1] = s:sub(i, j - 1)
        i = j + 1
    end
    return lines
end

-- ── docstring extraction ───────────────────────────────────────────────

--- Extract the leading `---` comment block.
---
--- Convention: a run of lines starting with `---` at the top of the file.
--- Stops at the first blank line or non-`---` line. Strips the `---`
--- prefix and a single leading space (luadoc convention).
--- Excludes `---@...` luadoc annotations (they are not narrative).
function M.extract_docstring(init_lua_path)
    local content = read_file(init_lua_path)
    local raw_lines = split_lines(content)
    local out = {}
    for i = 1, #raw_lines do
        local line = raw_lines[i]
        if line:sub(1, 3) == "---" then
            local rest = line:sub(4)
            -- skip luadoc annotations (---@param etc)
            if rest:sub(1, 1) == "@" then
                -- Pretend this terminates the docstring block: luadoc
                -- annotations are always placed AFTER narrative.
                break
            end
            if rest:sub(1, 1) == " " then
                rest = rest:sub(2)
            end
            out[#out + 1] = rest
        elseif line:match("^%s*$") then
            break
        else
            break
        end
    end
    -- Trim trailing blank lines.
    while #out > 0 and out[#out]:match("^%s*$") do
        out[#out] = nil
    end
    return table.concat(out, "\n")
end

-- ── slug / anchor ──────────────────────────────────────────────────────

--- GitHub-style anchor slug.
function M.slugify(text)
    local s = text:lower()
    -- Replace non-alnum with "-"
    s = s:gsub("[^a-z0-9]+", "-")
    s = s:gsub("^%-+", "")
    s = s:gsub("%-+$", "")
    return s
end

-- ── section split ──────────────────────────────────────────────────────

--- Allocate a unique anchor within a docstring.
---
--- First occurrence of a given slug keeps the base form; subsequent
--- occurrences get a `-2`, `-3`, ... suffix. This closes design point
--- §10 #3 (anchor collision) deterministically without changing the
--- author-visible heading text.
---
--- Stateful: pass a freshly-allocated `{}` table as `seen` per docstring.
local function alloc_anchor(seen, base)
    if not seen[base] then
        seen[base] = 1
        return base
    end
    local n = seen[base] + 1
    while seen[base .. "-" .. n] do
        n = n + 1
    end
    seen[base] = n
    local unique = base .. "-" .. n
    seen[unique] = 1
    return unique
end

--- Split docstring into (title, summary, sections[]).
---
--- Rules (V0):
---   * line 1          → title
---   * lines until next blank or "## ":
---                     → summary (joined with " ")
---   * Remaining split by "## " (H2) / "### " (H3). H4+ is part of
---     the preceding section's body.
---   * Each section's body_md is the verbatim Markdown between its
---     heading line and the next H2/H3 heading.
---   * Duplicate slugs are disambiguated with `-2`, `-3`, ... suffixes.
function M.split_sections(docstring)
    local lines = split_lines(docstring)
    if #lines == 0 then
        return "", "", {}
    end
    local title = lines[1]

    -- Skip blank lines between title and summary.
    local i = 2
    while i <= #lines and lines[i]:match("^%s*$") do
        i = i + 1
    end

    -- Summary: consecutive non-blank lines until blank or first "## "/"### ".
    local summary_parts = {}
    while i <= #lines do
        local line = lines[i]
        if line:match("^%s*$") then
            break
        end
        if line:sub(1, 3) == "## " or line:sub(1, 4) == "### " then
            break
        end
        summary_parts[#summary_parts + 1] = line
        i = i + 1
    end
    local summary = table.concat(summary_parts, " ")

    -- Skip blank lines to reach first section.
    while i <= #lines and lines[i]:match("^%s*$") do
        i = i + 1
    end

    -- Walk the rest, grouping by heading.
    local sections = {}
    local seen_anchors = {}
    local cur_level, cur_heading, cur_anchor = nil, nil, nil
    local cur_body = {}

    local function flush()
        if cur_heading then
            -- Trim leading and trailing blank lines; preserve internal blanks.
            local lo, hi = 1, #cur_body
            while lo <= hi and cur_body[lo]:match("^%s*$") do
                lo = lo + 1
            end
            while hi >= lo and cur_body[hi]:match("^%s*$") do
                hi = hi - 1
            end
            local body_lines = {}
            for j = lo, hi do
                body_lines[#body_lines + 1] = cur_body[j]
            end
            sections[#sections + 1] = PI.make_section(
                cur_level, cur_heading, cur_anchor,
                table.concat(body_lines, "\n"))
        end
    end

    while i <= #lines do
        local line = lines[i]
        local h2 = line:match("^## (.+)$")
        local h3 = line:match("^### (.+)$")
        if h2 and not line:match("^### ") then
            flush()
            cur_level   = 2
            cur_heading = h2
            cur_anchor  = alloc_anchor(seen_anchors, M.slugify(h2))
            cur_body    = {}
        elseif h3 then
            flush()
            cur_level   = 3
            cur_heading = h3
            cur_anchor  = alloc_anchor(seen_anchors, M.slugify(h3))
            cur_body    = {}
        else
            cur_body[#cur_body + 1] = line
        end
        i = i + 1
    end
    flush()

    return title, summary, sections
end

-- ── pkg loading (M.meta access) ────────────────────────────────────────

--- Load the pkg via `require` and return M.meta.
---
--- Resets `package.loaded[pkg_name]` first to ensure a fresh load
--- (multiple iterations in one run would otherwise see stale state).
function M.load_meta(pkg_name)
    package.loaded[pkg_name] = nil
    local ok, mod = pcall(require, pkg_name)
    if not ok then
        error(string.format(
            "tools.docs.extract: failed to require('%s'): %s",
            pkg_name, tostring(mod)), 2)
    end
    if type(mod) ~= "table" then
        error(string.format(
            "tools.docs.extract: require('%s') did not return a table",
            pkg_name), 2)
    end
    local meta = mod.meta
    if type(meta) ~= "table" then
        error(string.format(
            "tools.docs.extract: pkg '%s' has no M.meta table", pkg_name), 2)
    end
    return meta
end

-- ── assemble PkgInfo ───────────────────────────────────────────────────

local function is_schema(v)
    return type(v) == "table" and rawget(v, "kind") ~= nil
end

--- Build a PkgInfo for one package.
---
--- Args:
---   pkg_name  : string, e.g. "cot"
---   init_path : string, absolute path to {pkg}/init.lua
---   source_path : string, repo-relative path for the frontmatter
---                 (e.g. "cot/init.lua")
function M.build_pkg_info(pkg_name, init_path, source_path)
    local docstring = M.extract_docstring(init_path)
    local title, summary, sections = M.split_sections(docstring)
    local meta = M.load_meta(pkg_name)

    local identity = {
        name        = meta.name or pkg_name,
        version     = meta.version or "",
        category    = meta.category or "",
        description = meta.description or "",
        source_path = source_path,
    }

    local narrative = {
        title    = title,
        summary  = summary,
        sections = sections,
    }

    local shape = {
        input  = nil,
        result = nil,
    }
    if meta.input_shape ~= nil then
        if not is_schema(meta.input_shape) then
            error(string.format(
                "tools.docs.extract: pkg '%s' meta.input_shape must be an " ..
                "alc_shapes schema", pkg_name), 2)
        end
        shape.input = meta.input_shape
    end
    if meta.result_shape ~= nil then
        if type(meta.result_shape) == "string" then
            -- Named result type — wrap as `T.ref` so downstream sees a
            -- uniform kind-tagged schema (Malli `[:ref :name]` analogue).
            -- Projection renders it verbatim as the name.
            shape.result = T.ref(meta.result_shape)
        elseif is_schema(meta.result_shape) then
            shape.result = meta.result_shape
        else
            error(string.format(
                "tools.docs.extract: pkg '%s' meta.result_shape must be " ..
                "a string or an alc_shapes schema (got type '%s')",
                pkg_name, type(meta.result_shape)), 2)
        end
    end

    return PI.make_pkg_info(identity, narrative, shape)
end

M._internal = {
    read_file     = read_file,
    split_lines   = split_lines,
    alloc_anchor  = alloc_anchor,
    is_schema     = is_schema,
}

return M
