--- alc_shapes — SSoT for the result shape convention.
---
--- Usage:
---   local S = require("alc_shapes")
---   local ok, reason = S.check(value, S.voted)
---   local x = S.assert(value, "voted", "where")
---
--- P0 note: the shape dictionary is intentionally empty. P1 adds
--- voted / assessed / paneled / etc. Adding a new shape is one line:
---   M.voted = T.shape({ answer = T.string, ... }, { open = true })
---
--- See workspace/tasks/shape-convention/design.md.

local T = require("alc_shapes.t")
local check = require("alc_shapes.check")
local reflect = require("alc_shapes.reflect")
local luacats = require("alc_shapes.luacats")

local M = {}

-- ── shape dictionary (P0: empty) ─────────────────────────────────────
-- P1 will add entries such as:
--   M.voted = T.shape({
--       answer      = T.string:describe("Majority answer"),
--       answer_norm = T.string:describe("Normalized vote key"),
--       vote_counts = T.table,
--       paths       = T.array_of(T.table),
--       ...
--   }, { open = true })

-- ── public API re-export ─────────────────────────────────────────────
M.check        = check.check
M.assert       = check.assert
M.assert_dev   = check.assert_dev
M.is_dev_mode  = check.is_dev_mode
M.fields       = reflect.fields
M.walk         = reflect.walk

-- Combinator namespace (so callers can write `S.T.string` without a
-- separate require).
M.T = T

-- Codegen namespace (used by scripts/gen_shapes_luacats.lua).
M.LuaCats = luacats

-- ── reserved-name guard ──────────────────────────────────────────────
-- Certain names collide with `check.assert` shortcut semantics:
--   `M.assert(v, "any")` is always a no-op pass-through. Registering a
-- shape under such a name would silently shadow the shortcut (check.lua).
-- tableshape / Zod avoid this by namespace-separating built-ins from user
-- schemas; we enforce the same invariant via a load-time loud-fail.
-- Re-exported functions / combinator namespaces (M.T, M.LuaCats, etc.)
-- are not shape-kind and therefore never trip this check.
-- See workspace/tasks/shape-convention/design.md §P0 修正メモ Q3.
local RESERVED_SHAPE_NAMES = { "any" }

local function assert_no_reserved_shapes(mod)
    for i = 1, #RESERVED_SHAPE_NAMES do
        local name = RESERVED_SHAPE_NAMES[i]
        local v = rawget(mod, name)
        if type(v) == "table" and rawget(v, "kind") == "shape" then
            error(string.format(
                "alc_shapes: '%s' is reserved (assert shortcut); cannot register a shape under this name",
                name), 2)
        end
    end
end

assert_no_reserved_shapes(M)

M._internal = {
    assert_no_reserved_shapes = assert_no_reserved_shapes,
    RESERVED_SHAPE_NAMES      = RESERVED_SHAPE_NAMES,
}

return M
