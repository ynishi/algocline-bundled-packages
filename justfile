# algocline-bundled-packages — task runner
#
# Usage:
#   just                 # list tasks
#   just e2e <name>      # run a single E2E (e.g. just e2e recipe_safe_panel)
#   just e2e-all         # run every E2E under scripts/e2e/
#
# Prereqs:
#   - `agent-block` installed (cargo install --path ../agent-block)
#   - `alc` MCP server available on PATH
#   - ANTHROPIC_API_KEY exported

default:
    @just --list

# Run a single E2E scenario. `name` is the filename stem under scripts/e2e/.
# [group('allow-agent')]
e2e name:
    agent-block -s scripts/e2e/{{name}}.lua -p .

# Run all E2E scenarios sequentially. Continues on individual failures.
# [group('allow-agent')]
e2e-all:
    #!/usr/bin/env bash
    set -u
    fail=0
    for f in scripts/e2e/*.lua; do
        name=$(basename "$f" .lua)
        if [[ "$name" == "common" ]]; then continue; fi
        echo "=== E2E: $name ==="
        if ! agent-block -s "$f" -p .; then
            echo "FAILED: $name"
            fail=$((fail + 1))
        fi
    done
    if [[ $fail -gt 0 ]]; then
        echo "=== $fail E2E(s) failed ==="
        exit 1
    fi
    echo "=== All E2Es passed ==="

# Pure-Lua structure tests run via the `lua-debugger` MCP server
# (binary: mlua-probe-mcp). See README §Testing for the canonical
# `mcp__lua-debugger__test_launch` invocation. There is no `just test`
# recipe — the upstream mlua-probe ships only the MCP server, not a CLI.

# List installed/linked algocline packages.
# [group('allow-agent')]
pkg-list:
    alc pkg list

# Publish reminder: regenerate hub_index.json + all doc projections
# (hub / narrative / llms / context7 / devin / luacats) in a single
# MCP call. This is the canonical pre-publish step.
#
# With algocline core >= 0.26, all docs / projection config is driven
# by `alc.toml` at the repository root (`[hub]` / `[hub.context7]` /
# `[hub.devin]`), so no `config_path` argument is required — the core
# auto-explores `alc.toml` and merges it with the embedded default
# rules / repo_notes. The previous `tools/gen_docs.lua` +
# `tools/docs/{context7_config,devin_wiki_config}.lua` were retired
# once the TOML-only path landed in core (Lua config files are rejected
# as a typed error).
#
# Invoke the MCP tool from a Claude Code / rmcp session:
#
#   alc_hub_dist(
#     source_dir   = ".",
#     output_path  = "hub_index.json",
#     out_dir      = "docs",
#     projections  = ["hub", "narrative", "llms", "context7", "devin", "luacats"],
#     lint_strict  = true,
#   )
#
# This recipe does nothing on its own — it just prints the reminder so
# publishing without running dist is harder to forget. Use `just
# dist-auto` to run it headlessly via agent-block.
# [group('allow-agent')]
dist:
    @echo "Run via MCP:  alc_hub_dist source_dir=. output_path=hub_index.json \\"
    @echo "               out_dir=docs \\"
    @echo "               projections=[hub,narrative,llms,context7,devin,luacats] \\"
    @echo "               lint_strict=true"
    @echo ""
    @echo "alc.toml at repo root is auto-explored for [hub] / [hub.context7] / [hub.devin]."
    @echo ""
    @echo "Or headless:  just dist-auto"

# Run `alc_hub_dist` headlessly by driving the `alc` MCP server through
# agent-block (same harness used by E2E recipes). Requires ANTHROPIC_API_KEY.
# [group('allow-agent')]
dist-auto:
    agent-block -s scripts/dist.lua -p .

# Audit test coverage across bundled packages. Emits a markdown summary
# (Untested top-N priority list + coverage stats). Pure Lua, no LLM call.
# [group('allow-agent')]
test-audit top="50":
    lua5.4 tools/test_audit.lua --format=md --top={{top}}

# JSON form of `test-audit` for piping into jq.
# [group('allow-agent')]
test-audit-json:
    lua5.4 tools/test_audit.lua --format=json

# Run a single Lua spec/test file via lua5.4 with `lust` globals injected.
# Locates mlua-lspec's lust.lua dynamically from the cargo registry so the
# recipe survives mlua-lspec version bumps. Use `just alc-pkg-test-file
# <pkg>/spec/<pkg>_spec.lua` or `just alc-pkg-test-file tests/test_X.lua`.
# [group('allow-agent')]
alc-pkg-test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    LUST_DIR=$(ls -d ~/.cargo/registry/src/*/mlua-lspec-*/lua 2>/dev/null | sort -V | tail -n 1)
    if [ -z "$LUST_DIR" ]; then
        echo "Error: mlua-lspec/lua not found under ~/.cargo/registry/src/" >&2
        echo "Run: cargo install mlua-probe-mcp" >&2
        exit 1
    fi
    LUA_PATH="./?.lua;./?/init.lua;$LUST_DIR/?.lua;;" \
        lua5.4 -e "lust = require('lust'); dofile('{{path}}')"
