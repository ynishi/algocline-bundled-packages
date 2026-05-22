#!/usr/bin/env lua5.4
-- tools/test_audit.lua — bundled-packages coverage matrix generator
--
-- Pure Lua CLI. Enumerate pkgs (<name>/init.lua at repo root) and tests
-- (<pkg>/spec/*_spec.lua + tests/test_*.lua), build coverage matrix,
-- emit markdown or JSON.
--
-- Usage:
--   lua5.4 tools/test_audit.lua [--format=md|json] [--top=N] [--root=PATH]

local M = {}

-- ─── arg parsing ──────────────────────────────────────────
local function parse_args(argv)
  local opts = { format = "md", top = 50, root = "." }
  for _, a in ipairs(argv) do
    local k, v = a:match("^%-%-([%w_]+)=(.*)$")
    if k == "format" then opts.format = v
    elseif k == "top" then opts.top = tonumber(v) or 50
    elseif k == "root" then opts.root = v
    elseif a == "--help" or a == "-h" then
      io.write("Usage: lua5.4 tools/test_audit.lua [--format=md|json] [--top=N] [--root=PATH]\n")
      os.exit(0)
    end
  end
  return opts
end

-- ─── filesystem (lfs preferred, find(1) fallback) ─────────
local has_lfs, lfs = pcall(require, "lfs")

local function popen_lines(cmd)
  local out, fh = {}, io.popen(cmd)
  if not fh then return out end
  for line in fh:lines() do out[#out + 1] = line end
  fh:close()
  return out
end

local function list_dirs(root)
  if has_lfs then
    local dirs = {}
    for name in lfs.dir(root) do
      if name ~= "." and name ~= ".." then
        local p = root .. "/" .. name
        local attr = lfs.attributes(p)
        if attr and attr.mode == "directory" then dirs[#dirs + 1] = name end
      end
    end
    return dirs
  else
    local lines = popen_lines(
      string.format("find %q -maxdepth 1 -mindepth 1 -type d 2>/dev/null", root))
    local dirs = {}
    for _, l in ipairs(lines) do
      dirs[#dirs + 1] = l:match("([^/]+)$")
    end
    return dirs
  end
end

local function file_exists(p)
  local f = io.open(p, "r")
  if f then f:close(); return true end
  return false
end

local function list_files(dir, pattern)
  if has_lfs then
    local out = {}
    local attr = lfs.attributes(dir)
    if not attr or attr.mode ~= "directory" then return out end
    for name in lfs.dir(dir) do
      if name:match(pattern) then out[#out + 1] = dir .. "/" .. name end
    end
    return out
  else
    local cmd = string.format("find %q -maxdepth 1 -type f -name '*.lua' 2>/dev/null", dir)
    local out = {}
    for _, l in ipairs(popen_lines(cmd)) do
      local base = l:match("([^/]+)$")
      if base and base:match(pattern) then out[#out + 1] = l end
    end
    return out
  end
end

local function read_file(p)
  local f = io.open(p, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ─── pkg / test enumerate ─────────────────────────────────
local SKIP_DIRS = {
  tests = true, tools = true, docs = true, scripts = true,
  workspace = true, types = true, node_modules = true,
  [".worktrees"] = true, [".claude"] = true, [".git"] = true,
  [".ryo"] = true, target = true,
}

local function enumerate_pkgs(root)
  local pkgs = {}
  for _, dname in ipairs(list_dirs(root)) do
    if dname:sub(1, 1) ~= "." and not SKIP_DIRS[dname] then
      local init = root .. "/" .. dname .. "/init.lua"
      if file_exists(init) then
        pkgs[#pkgs + 1] = { name = dname, path = init, dir = root .. "/" .. dname }
      end
    end
  end
  table.sort(pkgs, function(a, b) return a.name < b.name end)
  return pkgs
end

local function enumerate_tests(root, pkgs)
  local tests = {}
  for _, p in ipairs(pkgs) do
    for _, f in ipairs(list_files(p.dir .. "/spec", "_spec%.lua$")) do
      tests[#tests + 1] = { path = f, kind = "spec", home_pkg = p.name }
    end
  end
  for _, f in ipairs(list_files(root .. "/tests", "^test_.+%.lua$")) do
    tests[#tests + 1] = { path = f, kind = "cross", home_pkg = nil }
  end
  return tests
end

-- ─── analysis ─────────────────────────────────────────────
local function extract_requires(src)
  local refs = {}
  if not src then return refs end
  for name in src:gmatch([[require%s*%(?%s*["']([%w_%.]+)["']%s*%)?]]) do
    refs[name] = true
  end
  return refs
end

local PAPER_TOKENS = { "arXiv", "arxiv", " §", "Algorithm ", "Eq%.", "Eq ",
                      "Theorem ", "Lemma ", "doi:", "DOI:" }
local function has_paper_citation(src)
  if not src then return 0 end
  local head = src:sub(1, 4096)
  for _, tok in ipairs(PAPER_TOKENS) do
    if head:find(tok, 1, false) then return 1 end
  end
  return 0
end

local function analyze(opts)
  local root = opts.root
  local pkgs = enumerate_pkgs(root)
  local pkg_set = {}
  for _, p in ipairs(pkgs) do pkg_set[p.name] = p end

  for _, p in ipairs(pkgs) do
    local src = read_file(p.path)
    p.requires = extract_requires(src)
    p.paper_explicit = has_paper_citation(src)
  end

  local invocation_freq = {}
  for _, p in ipairs(pkgs) do invocation_freq[p.name] = 0 end
  for _, p in ipairs(pkgs) do
    for r, _ in pairs(p.requires) do
      if invocation_freq[r] ~= nil and r ~= p.name then
        invocation_freq[r] = invocation_freq[r] + 1
      end
    end
  end

  local tests = enumerate_tests(root, pkgs)
  local coverage = {}
  for _, p in ipairs(pkgs) do coverage[p.name] = {} end

  for _, t in ipairs(tests) do
    local src = read_file(t.path)
    t.requires = extract_requires(src)
    if t.kind == "spec" and t.home_pkg and pkg_set[t.home_pkg] then
      t.requires[t.home_pkg] = true
    end
    for r, _ in pairs(t.requires) do
      if coverage[r] then
        coverage[r][#coverage[r] + 1] = t.path
      end
    end
  end

  local untested = {}
  for _, p in ipairs(pkgs) do
    if #coverage[p.name] == 0 then
      local score = (invocation_freq[p.name] or 0) * 1.0 + p.paper_explicit * 5.0
      untested[#untested + 1] = {
        name = p.name,
        score = score,
        invocation_freq = invocation_freq[p.name] or 0,
        paper_explicit = p.paper_explicit,
      }
    end
  end
  table.sort(untested, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.name < b.name
  end)

  local tested_count = 0
  for _, p in ipairs(pkgs) do
    if #coverage[p.name] > 0 then tested_count = tested_count + 1 end
  end

  return {
    pkgs = pkgs,
    tests = tests,
    coverage = coverage,
    untested = untested,
    invocation_freq = invocation_freq,
    stats = {
      pkg_total = #pkgs,
      test_total = #tests,
      tested = tested_count,
      untested = #pkgs - tested_count,
      coverage_pct = #pkgs > 0
        and math.floor((tested_count / #pkgs) * 1000 + 0.5) / 10 or 0,
    },
  }
end

-- ─── emit: markdown ───────────────────────────────────────
local function emit_md(report, opts)
  local s = report.stats
  io.write("# bundled-packages test coverage audit\n\n")
  io.write(string.format(
    "- Packages: %d\n- Tests: %d\n- Tested: %d (%.1f%%)\n- Untested: %d\n\n",
    s.pkg_total, s.test_total, s.tested, s.coverage_pct, s.untested))

  io.write(string.format("## Untested packages — top %d by priority\n\n", opts.top))
  io.write("| rank | pkg | score | invoc_freq | paper |\n")
  io.write("|---:|---|---:|---:|:---:|\n")
  local n = math.min(opts.top, #report.untested)
  for i = 1, n do
    local u = report.untested[i]
    io.write(string.format("| %d | `%s` | %.1f | %d | %s |\n",
      i, u.name, u.score, u.invocation_freq, u.paper_explicit == 1 and "Y" or ""))
  end
  io.write("\n")
end

-- ─── emit: json (minimal encoder) ─────────────────────────
local function json_encode(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then return tostring(v)
  elseif t == "string" then
    return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"')
                  :gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
  elseif t == "table" then
    local n, is_arr = 0, true
    for k, _ in pairs(v) do
      n = n + 1
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_arr = false end
    end
    if is_arr and n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = json_encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, val in pairs(v) do
        parts[#parts + 1] = json_encode(tostring(k)) .. ":" .. json_encode(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

local function emit_json(report, opts)
  local pkgs_out = {}
  for _, p in ipairs(report.pkgs) do
    pkgs_out[#pkgs_out + 1] = {
      name = p.name,
      paper_explicit = p.paper_explicit,
      invocation_freq = report.invocation_freq[p.name] or 0,
      tests = report.coverage[p.name],
    }
  end
  local tests_out = {}
  for _, t in ipairs(report.tests) do
    tests_out[#tests_out + 1] = { path = t.path, kind = t.kind, home_pkg = t.home_pkg }
  end
  local untested_sorted = {}
  local n = math.min(opts.top, #report.untested)
  for i = 1, n do untested_sorted[i] = report.untested[i] end

  io.write(json_encode({
    packages = pkgs_out,
    tests = tests_out,
    untested_sorted = untested_sorted,
    stats = report.stats,
  }))
  io.write("\n")
end

-- ─── main ─────────────────────────────────────────────────
local function main(argv)
  local opts = parse_args(argv)
  local report = analyze(opts)
  if opts.format == "json" then emit_json(report, opts)
  else emit_md(report, opts) end
end

main(arg or {})
return M
