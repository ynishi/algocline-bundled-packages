---@module 'flow.ir.compile'
-- Def → IR validation (Compile stage of Def→Compile→Exec).
--
-- Single recursive walk per node: alc_shapes shallow check (catches
-- kind/op typos and the top-level field set) + a per-kind validator
-- that enforces local invariants (path prefixes, registry membership,
-- nested-counter / nested-bind rules) and descends into structural
-- children via `flow.ir.walk.children_of`. The same child-enumeration
-- function backs the public §3.A introspect surface, so compile and
-- introspect cannot drift on what counts as a child.
--
-- ## Static guarantees after compile
--
--   - every kind is in NODE_KINDS, every op is in EXPR_OPS
--   - step.out / let.at / loop.counter / call.out / fanout.bind /
--     fanout.out start with "ctx."
--   - Expr.path.at starts with "$.ctx." (other roots reserved)
--   - step.in_, if present, is a valid Expr (recursively)
--   - seq.children / branch.then_/else_ / loop.body / fanout.body
--     are all valid Nodes (recursively)
--   - branch.cond / loop.cond / let.value / call.args[*] / fanout.items
--     are all valid Exprs (recursively)
--   - nested loop sharing the same `counter` path is rejected
--   - nested fanout sharing the same `bind` path is rejected
--   - when opts.flows is provided, every `call.flow` must be a key
--   - when opts.refs is provided, every `step.ref` must be a key
--
-- compile() returns the same IR table on success (Def *is* the IR — no
-- separate transformation), or (nil, reason) on failure.
--
-- ## Error format
--
-- Errors are JSONPath-ish strings with `$` as the IR root, e.g.
--   "compile: at $.children[2].cond.lhs: Expr.path.at must start with '$.ctx.'"
-- This mirrors lshape / alc_shapes.check error formatting and makes
-- the failing node easy to locate in a Lua source dump.

local S         = require("alc_shapes")
local schema    = require("flow.ir.schema")
local walk      = require("flow.ir.walk")
local path_mod  = require("flow.ir.path")

local M = {}

local CTX_WRITE_PREFIX = "ctx."
local PATH_READ_PREFIX = "$.ctx."

--- Format a compile error with a path prefix.
---@param path string  IR location, e.g. "$.children[2].cond.lhs"
---@param msg  string  human-readable reason
---@return nil
---@return string  formatted "compile: at <path>: <msg>"
local function err(path, msg)
    return nil, string.format("compile: at %s: %s", path, msg)
end

local function has_ctx_write_prefix(s)
    return s:sub(1, #CTX_WRITE_PREFIX) == CTX_WRITE_PREFIX
end

--- Validate path syntax via `flow.ir.path.parse` and surface parse
--- errors at compile time (rather than letting them fall through to
--- the interpreter). The prefix string check above gates the root,
--- and this checks the bracket / name segment shape that follows.
---@param at string
---@return true|nil ok
---@return string?  reason
local function validate_path_syntax(at)
    local _, reason = path_mod.parse(at)
    if reason then return nil, reason end
    return true
end

-- ── Expr validation ─────────────────────────────────────────────────
--
-- Per-op validators receive (expr, path). They run AFTER the shared
-- alc_shapes shallow check + op membership check and AFTER any nested
-- Expr children have themselves been validated. Validators MUST NOT
-- recurse — recursion is centralized in `check_expr` via
-- `walk.expr_children_of`.

local check_expr   -- forward decl

--- Validate Expr children listed by `walk.expr_children_of` and verify
--- that variadic-arg op kinds have at least 2 entries.
---@param expr  flow.ir.Expr
---@param path  string
---@return boolean|nil ok
---@return string?    reason
local function descend_expr(expr, path)
    -- variadic min-2 check (and / or / concat)
    if expr.op == "and" or expr.op == "or" or expr.op == "concat" then
        if type(expr.args) ~= "table" or #expr.args < 2 then
            local got = type(expr.args) == "table" and #expr.args or 0
            return err(path, "Expr." .. expr.op .. ": requires >= 2 args, got " .. got)
        end
    end
    for _, entry in ipairs(walk.expr_children_of(expr)) do
        local sub_path = path .. "." .. entry.key
        if entry.idx ~= nil then sub_path = string.format("%s[%d]", sub_path, entry.idx) end
        local ok, reason = check_expr(entry.child, sub_path)
        if not ok then return nil, reason end
    end
    return true
end

---@type table<string, fun(expr: flow.ir.Expr, path: string): boolean|nil, string?>
local EXPR_LOCAL_CHECK = {
    path = function(expr, path)
        if expr.at:sub(1, #PATH_READ_PREFIX) ~= PATH_READ_PREFIX then
            return err(path, "Expr.path.at must start with '" .. PATH_READ_PREFIX .. "'")
        end
        local ok, reason = validate_path_syntax(expr.at)
        if not ok then
            return err(path, "Expr.path.at: " .. reason)
        end
        return true
    end,
    -- lit / eq / and / or / not / lt / len / add / get: no local invariant
    -- beyond shape + recursive children. (concat min-2 is checked in
    -- descend_expr alongside and/or.)
}

check_expr = function(expr, path)
    if type(expr) ~= "table" then
        return err(path, "expected Expr table, got " .. type(expr))
    end
    local op = expr.op
    if type(op) ~= "string" or not schema.EXPR_OPS[op] then
        return err(path, "unknown Expr op: " .. tostring(op))
    end
    local ok, reason = S.check(expr, schema.Expr)
    if not ok then return err(path, reason) end
    local local_check = EXPR_LOCAL_CHECK[op]
    if local_check then
        ok, reason = local_check(expr, path)
        if not ok then return nil, reason end
    end
    return descend_expr(expr, path)
end

-- ── Node validation ─────────────────────────────────────────────────
--
-- Walk state threaded per subtree:
--   active_counters : Set<string>  loop.counter paths in enclosing scope
--   active_binds    : Set<string>  fanout.bind paths in enclosing scope
--   known_flows     : Set<string>? eager call.flow registry (nil → lazy)
--   known_refs      : Set<string>? eager step.ref registry (nil → lazy)
--
-- Per-kind validators run AFTER the alc_shapes shallow check and AFTER
-- their Expr fields have been independently validated. They return
-- either (true) on success or (nil, reason) on failure. They DO NOT
-- recurse into structural child Nodes — that descent is centralized in
-- `check_node` via `walk.children_of`. The single exception is `loop`
-- / `fanout`, which need to extend the walk_state before descending;
-- they return a possibly-modified `body_state` as the 3rd return value.

local check_node   -- forward decl

local function copy_set(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

---@type table<string, fun(node: flow.ir.Node, path: string, state: table): boolean|nil, string?, table?>
local NODE_LOCAL_CHECK = {
    step = function(node, path, state)
        if not has_ctx_write_prefix(node.out) then
            return err(path, "step.out must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok, reason = validate_path_syntax(node.out)
        if not ok then return err(path, "step.out: " .. reason) end
        if state.known_refs and not state.known_refs[node.ref] then
            return err(path, "step.ref: '" .. node.ref .. "' not in opts.refs registry")
        end
        if node.in_ ~= nil then
            ok, reason = check_expr(node.in_, path .. ".in_")
            if not ok then return nil, reason end
        end
        return true
    end,
    seq = function(_node, _path, _state)
        return true  -- children validated by check_node descent
    end,
    branch = function(node, path, _state)
        local ok, reason = check_expr(node.cond, path .. ".cond")
        if not ok then return nil, reason end
        return true
    end,
    ["let"] = function(node, path, _state)
        if not has_ctx_write_prefix(node.at) then
            return err(path, "let.at must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok, reason = validate_path_syntax(node.at)
        if not ok then return err(path, "let.at: " .. reason) end
        ok, reason = check_expr(node.value, path .. ".value")
        if not ok then return nil, reason end
        return true
    end,
    loop = function(node, path, state)
        if type(node.max) ~= "number" or node.max < 1 or node.max ~= math.floor(node.max) then
            return err(path, "loop.max must be an integer >= 1, got " .. tostring(node.max))
        end
        if not has_ctx_write_prefix(node.counter) then
            return err(path, "loop.counter must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok, reason = validate_path_syntax(node.counter)
        if not ok then return err(path, "loop.counter: " .. reason) end
        if state.active_counters[node.counter] then
            return err(path,
                "loop.counter: nested loop reuses counter path '" .. node.counter .. "'")
        end
        ok, reason = check_expr(node.cond, path .. ".cond")
        if not ok then return nil, reason end
        local body_state = {
            active_counters = copy_set(state.active_counters),
            active_binds    = state.active_binds,
            known_flows     = state.known_flows,
            known_refs      = state.known_refs,
        }
        body_state.active_counters[node.counter] = true
        return true, nil, body_state
    end,
    call = function(node, path, state)
        if not has_ctx_write_prefix(node.out) then
            return err(path, "call.out must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok_p, reason_p = validate_path_syntax(node.out)
        if not ok_p then return err(path, "call.out: " .. reason_p) end
        if node.flow == "" then
            return err(path, "call.flow: required non-empty string")
        end
        if state.known_flows and not state.known_flows[node.flow] then
            return err(path, "call.flow: '" .. node.flow .. "' not in opts.flows registry")
        end
        for k, sub_expr in pairs(node.args) do
            local ok, reason = check_expr(sub_expr, path .. ".args." .. tostring(k))
            if not ok then return nil, reason end
        end
        return true
    end,
    wrap_step = function(node, path, state)
        if not has_ctx_write_prefix(node.out) then
            return err(path, "wrap_step.out must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok, reason = validate_path_syntax(node.out)
        if not ok then return err(path, "wrap_step.out: " .. reason) end
        if state.known_refs and not state.known_refs[node.ref] then
            return err(path, "wrap_step.ref: '" .. node.ref .. "' not in opts.refs registry")
        end
        if node.ref == "" then
            return err(path, "wrap_step.ref: required non-empty string")
        end
        ok, reason = check_expr(node.slot, path .. ".slot")
        if not ok then return nil, reason end
        if node.in_ ~= nil then
            ok, reason = check_expr(node.in_, path .. ".in_")
            if not ok then return nil, reason end
        end
        return true  -- on_mismatch (if present) walked via children_of
    end,
    fanout = function(node, path, state)
        if not has_ctx_write_prefix(node.bind) then
            return err(path, "fanout.bind must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        if not has_ctx_write_prefix(node.out) then
            return err(path, "fanout.out must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        local ok_p, reason_p = validate_path_syntax(node.bind)
        if not ok_p then return err(path, "fanout.bind: " .. reason_p) end
        ok_p, reason_p = validate_path_syntax(node.out)
        if not ok_p then return err(path, "fanout.out: " .. reason_p) end
        if state.active_binds[node.bind] then
            return err(path,
                "fanout.bind: nested fanout reuses bind path '" .. node.bind .. "'")
        end
        local ok, reason = check_expr(node.items, path .. ".items")
        if not ok then return nil, reason end
        local body_state = {
            active_counters = state.active_counters,
            active_binds    = copy_set(state.active_binds),
            known_flows     = state.known_flows,
            known_refs      = state.known_refs,
        }
        body_state.active_binds[node.bind] = true
        return true, nil, body_state
    end,
}

check_node = function(node, path, state)
    state = state or {
        active_counters = {}, active_binds = {},
        known_flows = nil, known_refs = nil,
    }
    if type(node) ~= "table" then
        return err(path, "expected Node table, got " .. type(node))
    end
    local kind = node.kind
    if type(kind) ~= "string" or not schema.NODE_KINDS[kind] then
        return err(path, "unknown Node kind: " .. tostring(kind))
    end
    local ok, reason = S.check(node, schema.Node)
    if not ok then return err(path, reason) end
    local local_check = NODE_LOCAL_CHECK[kind]
    local body_state
    ok, reason, body_state = local_check(node, path, state)
    if not ok then return nil, reason end
    local child_state = body_state or state
    for _, entry in ipairs(walk.children_of(node)) do
        local sub_path = path .. "." .. entry.key
        if entry.idx ~= nil then sub_path = string.format("%s[%d]", sub_path, entry.idx) end
        local sub_ok, sub_reason = check_node(entry.child, sub_path, child_state)
        if not sub_ok then return nil, sub_reason end
    end
    return true
end

---@class flow.ir.CompileOpts
---@field flows table<string, any>?  if provided, every `call.flow` name
---   not present as a key is a compile error (eager registry check).
---   Default (nil) defers `call.flow` resolution to exec.
---@field refs  table<string, any>?  if provided, every `step.ref` name
---   not present as a key is a compile error (eager registry check).
---   Default (nil) defers resolution to exec/dispatch.

--- Compile a Lua-table IR.
---
--- The Def *is* the IR — no transformation is performed. On success the
--- exact `ir` table is returned (identity), so downstream code can pass
--- the result to `flow.ir.exec` without an indirection. On failure
--- nil + reason are returned. Reasons are JSONPath-ish (`$.cond.lhs: …`).
---
---@param ir flow.ir.Node  the root Node (Def)
---@param opts flow.ir.CompileOpts?  optional eager-validation knobs
---@return flow.ir.Node|nil compiled
---@return string? reason  set when compiled is nil
function M.compile(ir, opts)
    opts = opts or {}
    local walk_state = {
        active_counters = {},
        active_binds    = {},
        known_flows     = opts.flows,
        known_refs      = opts.refs,
    }
    local ok, reason = check_node(ir, "$", walk_state)
    if not ok then return nil, reason end
    return ir
end

-- Exported for spec; not part of the public API contract.
M._check_node = check_node
M._check_expr = check_expr

return M
