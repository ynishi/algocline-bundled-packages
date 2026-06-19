---@module 'flow.ir.interpreter'
-- Exec stage of the Def→Compile→Exec pipeline.
--
-- Walks a compiled IR. Total responsibility:
--   - eval_expr  : Expr → value
--   - exec_node  : Node → ctx' (in-place mutation under documented keys)
--
-- ## Dispatch injection
--
-- Host dispatch is injected via `opts.dispatch(ref, input)` so the
-- interpreter stays host-neutral. The default stub returns nil and
-- raises on call, which is spec-friendly: tests provide their own
-- recorder; production callers inject their own dispatcher.
--
-- ## Path resolution (MVP)
--
--   read:  "$.ctx.foo.bar"  → ctx.foo.bar (table walk, missing key → nil)
--   write: "ctx.foo.bar"    → ctx.foo.bar (intermediate tables auto-created)
--
-- Reads are absolute and rooted at ctx (the "$" sigil is required, only
-- the `$.ctx.*` sub-tree is exposed). Writes are relative to ctx and
-- always create missing tables along the path. Index errors / non-table
-- intermediates on reads return nil (silent missing-key); writes through
-- a non-table intermediate are *replaced* with a fresh table.
--
-- ## Surface
--
-- 3 Node kinds × 3 Expr ops only. The schema discriminated +
-- `open = false` guard ensures unknown kind / op never reaches here.

local M = {}

-- ── path utils ──────────────────────────────────────────────────────

--- Split a dotted path into its segments (no escaping in MVP).
---@param s string
---@return string[]  segments (1-based, dense)
local function split_dots(s)
    local out, idx = {}, 1
    for part in string.gmatch(s, "[^%.]+") do
        out[idx], idx = part, idx + 1
    end
    return out
end

--- Resolve a `$.ctx.*` read path against the ctx table.
---
--- Walks the segments after `$.ctx`. A non-table intermediate yields
--- nil (missing-key semantics), which lets `eq(path, lit)` test for
--- presence as `eq(path, lit(nil))`.
---
---@param ctx table
---@param at  string  e.g. "$.ctx.verdict"
---@return any|nil value
---@return string? err  set only on malformed path
local function read_path(ctx, at)
    local parts = split_dots(at)
    if parts[1] ~= "$" or parts[2] ~= "ctx" then
        return nil, "read_path: only $.ctx.* supported, got " .. at
    end
    local cur = ctx
    for i = 3, #parts do
        if type(cur) ~= "table" then return nil end
        cur = cur[parts[i]]
    end
    return cur
end

--- Write `value` into ctx under a `ctx.*` path, auto-creating tables.
---
--- A non-table intermediate is *replaced* with a fresh table (e.g.
--- writing "ctx.a.b" when ctx.a == "string" overwrites ctx.a). Callers
--- are expected to keep ctx well-typed; this is a deliberate choice
--- over a silent failure path.
---
---@param ctx   table
---@param at    string  e.g. "ctx.foo.bar"
---@param value any
local function write_path(ctx, at, value)
    local parts = split_dots(at)
    if parts[1] ~= "ctx" then
        error("write_path: only ctx.* supported, got " .. at, 2)
    end
    local cur = ctx
    for i = 2, #parts - 1 do
        local k = parts[i]
        if type(cur[k]) ~= "table" then cur[k] = {} end
        cur = cur[k]
    end
    cur[parts[#parts]] = value
end

-- ── Expr eval ───────────────────────────────────────────────────────

--- Evaluate an Expr against ctx.
---
--- `path` returns the value at the JSONPath-ish ref (or nil).
--- `lit` returns the literal value as-is.
--- `eq` returns boolean (Lua `==` semantics; nil == nil is true).
--- `and` returns boolean (short-circuit; true iff every arg is truthy).
--- `not` returns boolean (truthiness inversion).
--- `lt` returns boolean (Lua `<` semantics; numeric for numbers,
---     lexicographic for strings, raises on mixed/unordered types).
---
---@param expr flow.ir.Expr
---@param ctx  table
---@return any
local function eval_expr(expr, ctx)
    local op = expr.op
    if op == "lit" then
        return expr.value
    elseif op == "path" then
        local v, err = read_path(ctx, expr.at)
        if err then error(err, 2) end
        return v
    elseif op == "eq" then
        return eval_expr(expr.lhs, ctx) == eval_expr(expr.rhs, ctx)
    elseif op == "and" then
        for _, sub in ipairs(expr.args) do
            if not eval_expr(sub, ctx) then return false end
        end
        return true
    elseif op == "not" then
        return not eval_expr(expr.arg, ctx)
    elseif op == "lt" then
        return eval_expr(expr.lhs, ctx) < eval_expr(expr.rhs, ctx)
    end
    error("eval_expr: unknown op " .. tostring(op), 2)
end

-- ── stub dispatch ───────────────────────────────────────────────────

--- Spec-friendly default: returns nil and a "no dispatch configured" reason.
---
--- The interpreter treats `(nil, reason)` from dispatch as a fatal error
--- when invoked via the default; spec runs always inject their own
--- recorder via `opts.dispatch`, and production callers inject their own
--- dispatcher.
---
---@param ref string
---@param _input any
---@return nil
---@return string reason
local function default_dispatch(ref, _input)
    return nil, "default_dispatch: no dispatch configured for " .. ref
end

-- ── Node exec ───────────────────────────────────────────────────────

--- Execute one Node against ctx (in-place mutation).
---
--- `step`   evaluates `in_` (if present), calls opts.dispatch(ref, in),
---          writes the result to ctx[out].
--- `seq`    walks children in order.
--- `branch` evaluates cond, dispatches to then_ / else_ by truthiness.
---
--- Errors raise (`error(... , 2)`) rather than returning nil-reason; the
--- caller (`M.exec`) treats Node exec as transactional from the caller's
--- POV (no partial ctx repair on error). Callers wanting recovery should
--- pcall around `M.exec`.
---
---@param node flow.ir.Node
---@param ctx  table
---@param opts flow.ir.ExecOpts  guaranteed populated by M.exec
---@return table ctx
local function exec_node(node, ctx, opts)
    local kind = node.kind
    if kind == "step" then
        local input = nil
        if node.in_ then input = eval_expr(node.in_, ctx) end
        local result, derr = opts.dispatch(node.ref, input)
        if derr and result == nil then
            error("exec: step '" .. node.ref .. "': " .. derr, 2)
        end
        write_path(ctx, node.out, result)
    elseif kind == "seq" then
        for _, child in ipairs(node.children) do
            exec_node(child, ctx, opts)
        end
    elseif kind == "branch" then
        local cond_val = eval_expr(node.cond, ctx)
        if cond_val then
            exec_node(node.then_, ctx, opts)
        else
            exec_node(node.else_, ctx, opts)
        end
    else
        error("exec: unknown kind " .. tostring(kind), 2)
    end
    return ctx
end

---@class flow.ir.ExecOpts
---@field dispatch fun(ref: string, input: any): any, string?

--- Execute a compiled IR.
---
--- Mutates `ctx` in place and also returns it (convenient one-liner usage
--- `local ctx = flow.ir.exec(ir, {}, { dispatch = ... })`).
--- Errors raise via `error()` — callers wanting recovery should pcall.
---
---@param compiled flow.ir.Node  IR validated by flow.ir.compile
---@param ctx      table         initial ctx (mutated in place)
---@param opts     flow.ir.ExecOpts?  `{ dispatch = fn(ref, input) -> result, err? }`; default raises
---@return table ctx
function M.exec(compiled, ctx, opts)
    opts = opts or {}
    opts.dispatch = opts.dispatch or default_dispatch
    return exec_node(compiled, ctx, opts)
end

-- Exported for spec; not part of the public API contract.
M._eval_expr  = eval_expr
M._read_path  = read_path
M._write_path = write_path

return M
