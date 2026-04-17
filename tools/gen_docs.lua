#!/usr/bin/env lua
--- tools/gen_docs.lua — docs pipeline CLI.
---
--- Iterates every pkg (top-level directory with init.lua + M.meta) and
--- writes:
---   {out_dir}/narrative/{pkg}.md
---   {out_dir}/llms.txt
---   {out_dir}/llms-full.txt
---
--- Usage:
---   lua tools/gen_docs.lua [options] [repo_root] [out_dir]
---
--- Options:
---   --lint         Run the V0 lint pass and print violations. Errors are
---                  counted but do not block output unless --strict.
---   --strict       Treat lint errors as build failures (exit 2 when any
---                  pkg reports an error-level violation).
---   --lint-only    Run lint, skip file generation.
---
--- Defaults: repo_root = ".", out_dir = "{repo_root}/docs"

local function setup_package_path(repo_root)
    package.path = table.concat({
        repo_root .. "/?.lua",
        repo_root .. "/?/init.lua",
        package.path,
    }, ";")
end

-- ── argv parsing ──────────────────────────────────────────────────────

local function parse_argv(argv)
    local opts = { lint = false, strict = false, lint_only = false }
    local positional = {}
    for i = 1, #argv do
        local a = argv[i]
        if a == "--lint" then
            opts.lint = true
        elseif a == "--strict" then
            opts.strict = true
            opts.lint   = true
        elseif a == "--lint-only" then
            opts.lint_only = true
            opts.lint      = true
        elseif a:sub(1, 2) == "--" then
            io.stderr:write("gen_docs: unknown option '" .. a .. "'\n")
            os.exit(2)
        else
            positional[#positional + 1] = a
        end
    end
    return opts, positional
end

-- ── directory listing ─────────────────────────────────────────────────

local function list_pkgs(repo_root)
    local cmd = string.format("ls -d %s/*/init.lua 2>/dev/null", repo_root)
    local handle = io.popen(cmd)
    if not handle then
        error("gen_docs: io.popen failed for " .. cmd)
    end
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

-- ── file I/O ──────────────────────────────────────────────────────────

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then
        error(string.format("gen_docs: cannot write '%s': %s",
                            path, tostring(err)))
    end
    f:write(content)
    f:close()
end

local function ensure_dir(path)
    local ok = os.execute(string.format("mkdir -p %q", path))
    if not ok then
        error("gen_docs: mkdir -p failed for " .. path)
    end
end

-- ── main ──────────────────────────────────────────────────────────────

local function main(argv)
    local opts, positional = parse_argv(argv or {})
    local repo_root = positional[1] or "."
    local out_dir   = positional[2] or (repo_root .. "/docs")

    setup_package_path(repo_root)

    local Extract     = require("tools.docs.extract")
    local Projections = require("tools.docs.projections")
    local Lint        = opts.lint and require("tools.docs.lint") or nil

    local pkgs = list_pkgs(repo_root)
    if #pkgs == 0 then
        io.stderr:write("gen_docs: no pkg found under " .. repo_root .. "\n")
        os.exit(1)
    end

    if not opts.lint_only then
        ensure_dir(out_dir)
        ensure_dir(out_dir .. "/narrative")
    end

    local infos         = {}
    local entries       = {}
    local failures      = {}
    local skipped       = {}
    local lint_errors   = 0
    local lint_warnings = 0

    for i = 1, #pkgs do
        local p = pkgs[i]
        local ok, info_or_err = pcall(
            Extract.build_pkg_info, p.name, p.init_path, p.source_path)
        if ok then
            local info = info_or_err
            local md   = Projections.narrative_md(info)
            if not opts.lint_only then
                write_file(string.format("%s/narrative/%s.md", out_dir, p.name), md)
            end
            infos[#infos + 1]   = info
            entries[#entries + 1] = { name = p.name, narrative_md = md }

            if Lint then
                local docstring = Extract.extract_docstring(p.init_path)
                local result = Lint.check(info, docstring, p.name)
                if #result.violations > 0 then
                    for _, v in ipairs(result.violations) do
                        if v.severity == "error" then
                            lint_errors = lint_errors + 1
                        else
                            lint_warnings = lint_warnings + 1
                        end
                    end
                    io.stderr:write(Lint.format(p.name, result.violations) .. "\n")
                end
            end

            io.stdout:write(string.format("  [ok]   %s\n", p.name))
        else
            local msg = tostring(info_or_err)
            if msg:find("no M.meta table", 1, true) then
                skipped[#skipped + 1] = p.name
                io.stdout:write(string.format("  [skip] %s (no M.meta)\n", p.name))
            else
                failures[#failures + 1] = { name = p.name, err = msg }
                io.stderr:write(string.format("  [FAIL] %s: %s\n", p.name, msg))
            end
        end
    end

    if not opts.lint_only then
        write_file(out_dir .. "/llms.txt",      Projections.llms_index(infos))
        write_file(out_dir .. "/llms-full.txt", Projections.llms_full(entries))
    end

    io.stdout:write(string.format(
        "\ngen_docs: %d generated, %d skipped, %d failed",
        #infos, #skipped, #failures))
    if Lint then
        io.stdout:write(string.format(
            ", lint: %d error(s) / %d warning(s)",
            lint_errors, lint_warnings))
    end
    io.stdout:write("\n")

    if #failures > 0 then os.exit(1) end
    if opts.strict and lint_errors > 0 then os.exit(2) end
end

main(arg)
