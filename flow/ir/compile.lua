---@module 'flow.ir.compile'
-- Def → IR validation (Compile stage of Def→Compile→Exec).
--
-- Two passes:
--   1. shallow alc_shapes check at the root (catches typos in kind/op
--      tag and the top-level field set).
--   2. recursive walk that re-checks every nested Node / Expr. The
--      schema declares children as T.table (not T.ref) because MVP
--      avoids registry-resolved recursion; the walk here is the second
--      validation half.
--
-- ## Static guarantees after compile
--
--   - every kind is in NODE_KINDS, every op is in EXPR_OPS
--   - step.out starts with "ctx."
--   - Expr.path.at starts with "$.ctx." (other roots reserved)
--   - step.in_, if present, is a valid Expr (recursively)
--   - seq.children are all valid Nodes (recursively)
--   - branch.{cond, then_, else_} are all valid (recursively)
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

local S      = require("alc_shapes")
local schema = require("flow.ir.schema")

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

--- Recursively validate an Expr.
---@param expr flow.ir.Expr
---@param path string  IR location for error messages
---@return boolean|nil ok   true on success, nil on failure
---@return string?    reason  set when ok is nil
local function check_expr(expr, path)
    if type(expr) ~= "table" then
        return err(path, "expected Expr table, got " .. type(expr))
    end
    local op = expr.op
    if type(op) ~= "string" or not schema.EXPR_OPS[op] then
        return err(path, "unknown Expr op: " .. tostring(op))
    end
    local ok, reason = S.check(expr, schema.Expr)
    if not ok then return err(path, reason) end
    if op == "path" then
        if expr.at:sub(1, #PATH_READ_PREFIX) ~= PATH_READ_PREFIX then
            return err(path, "Expr.path.at must start with '" .. PATH_READ_PREFIX .. "'")
        end
    elseif op == "eq" then
        local sub
        sub, reason = check_expr(expr.lhs, path .. ".lhs")
        if not sub then return nil, reason end
        sub, reason = check_expr(expr.rhs, path .. ".rhs")
        if not sub then return nil, reason end
    elseif op == "and" then
        if type(expr.args) ~= "table" or #expr.args < 2 then
            local got = type(expr.args) == "table" and #expr.args or 0
            return err(path, "Expr.and: requires >= 2 args, got " .. got)
        end
        for i, sub_expr in ipairs(expr.args) do
            local sub_ok
            sub_ok, reason = check_expr(sub_expr, string.format("%s.args[%d]", path, i))
            if not sub_ok then return nil, reason end
        end
    elseif op == "not" then
        local sub
        sub, reason = check_expr(expr.arg, path .. ".arg")
        if not sub then return nil, reason end
    elseif op == "lt" then
        local sub
        sub, reason = check_expr(expr.lhs, path .. ".lhs")
        if not sub then return nil, reason end
        sub, reason = check_expr(expr.rhs, path .. ".rhs")
        if not sub then return nil, reason end
    end
    return true
end

--- Recursively validate a Node.
---@param node flow.ir.Node
---@param path string  IR location for error messages
---@return boolean|nil ok   true on success, nil on failure
---@return string?    reason  set when ok is nil
local function check_node(node, path)
    if type(node) ~= "table" then
        return err(path, "expected Node table, got " .. type(node))
    end
    local kind = node.kind
    if type(kind) ~= "string" or not schema.NODE_KINDS[kind] then
        return err(path, "unknown Node kind: " .. tostring(kind))
    end
    local ok, reason = S.check(node, schema.Node)
    if not ok then return err(path, reason) end
    if kind == "step" then
        if node.out:sub(1, #CTX_WRITE_PREFIX) ~= CTX_WRITE_PREFIX then
            return err(path, "step.out must start with '" .. CTX_WRITE_PREFIX .. "'")
        end
        if node.in_ ~= nil then
            local sub
            sub, reason = check_expr(node.in_, path .. ".in_")
            if not sub then return nil, reason end
        end
    elseif kind == "seq" then
        for i, child in ipairs(node.children) do
            local sub
            sub, reason = check_node(child, string.format("%s.children[%d]", path, i))
            if not sub then return nil, reason end
        end
    elseif kind == "branch" then
        local sub
        sub, reason = check_expr(node.cond, path .. ".cond")
        if not sub then return nil, reason end
        sub, reason = check_node(node.then_, path .. ".then_")
        if not sub then return nil, reason end
        sub, reason = check_node(node.else_, path .. ".else_")
        if not sub then return nil, reason end
    end
    return true
end

--- Compile a Lua-table IR.
---
--- The Def *is* the IR — no transformation is performed. On success the
--- exact `ir` table is returned (identity), so downstream code can pass
--- the result to `flow.ir.exec` without an indirection. On failure
--- nil + reason are returned. Reasons are JSONPath-ish (`$.cond.lhs: …`).
---
---@param ir flow.ir.Node  the root Node (Def)
---@return flow.ir.Node|nil compiled
---@return string? reason  set when compiled is nil
function M.compile(ir)
    local ok, reason = check_node(ir, "$")
    if not ok then return nil, reason end
    return ir
end

-- Exported for spec; not part of the public API contract.
M._check_node = check_node
M._check_expr = check_expr

return M
