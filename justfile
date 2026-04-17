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

# Regenerate types/alc_shapes.d.lua from alc_shapes/init.lua (SSoT).
# [group('allow-agent')]
gen-shapes:
    lua scripts/gen_shapes_luacats.lua > types/alc_shapes.d.lua

# Verify types/alc_shapes.d.lua matches the current alc_shapes/init.lua (drift check).
# [group('allow-agent')]
verify-shapes:
    lua scripts/gen_shapes_luacats.lua | diff - types/alc_shapes.d.lua
