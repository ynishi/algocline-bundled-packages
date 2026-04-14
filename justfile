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

# Run Pure-Lua structure tests via mlua-probe.
# [group('allow-agent')]
test:
    mlua-probe test tests/

# List installed/linked algocline packages.
# [group('allow-agent')]
pkg-list:
    alc pkg list
