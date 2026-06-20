---@module 'flow.ir.walk'
-- Internal walk primitive over Node / Expr trees.
--
-- This module is the **shared backbone** for two clients:
--   1. `flow.ir.compile` — recursive validation descends via the same
--      child-enumeration logic, so compile and introspect always agree
--      on what counts as a child.
--   2. `flow.ir.init` (Phase 3) — public `walk` / `type_of` / `refs_of` /
--      `children` are thin wrappers over the functions exported here.
--
-- The visitor signature here is the **public §3.A contract** in
-- internal form (frozen). Public exports in Phase 3 forward to it
-- unchanged.
--
-- ## Visitor contract (frozen)
--
--   visitor(node, ctx) -> nil | "skip" | "stop"
--     node : current Node (read-only; mutate is undefined)
--     ctx  : { depth = integer, parent = Node|nil, path = {string|int, ...} }
--       depth  — root is 0; child of root is 1, etc.
--       parent — direct parent Node (nil at root)
--       path   — accessor list from root to current node
--                (e.g. {"children", 2, "then_"})
--     returns:
--       nil    — continue (default)
--       "skip" — do not descend into this node's children
--       "stop" — abort the entire walk
--
-- The walk is depth-first, pre-order. Children are enumerated via
-- `children_of(node)`; only structural sub-Nodes are visited (Expr
-- sub-trees of e.g. `branch.cond` / `loop.cond` are NOT walked by
-- `walk`, since the §3.A surface is Node-tree introspection).

local M = {}

-- ── child enumeration ───────────────────────────────────────────────

--- Enumerate direct child Nodes of a Node.
---
--- Returns a list of `{ child = Node, key = string|integer }` entries
--- in deterministic order. The `key` is the accessor used to reach the
--- child from the parent (e.g. "then_", "body", or an integer index
--- under `children`). For `seq`, two-tuple entries `{key="children", idx=i}`
--- are emitted (callers append `key` then `idx` to the path).
---
---@param node flow.ir.Node
---@return { child: flow.ir.Node, key: string|integer, idx: integer? }[]
function M.children_of(node)
    local out = {}
    local kind = node.kind
    if kind == "seq" then
        for i, ch in ipairs(node.children) do
            out[#out + 1] = { child = ch, key = "children", idx = i }
        end
    elseif kind == "branch" then
        out[#out + 1] = { child = node.then_, key = "then_" }
        if node.else_ ~= nil then
            out[#out + 1] = { child = node.else_, key = "else_" }
        end
    elseif kind == "loop" then
        out[#out + 1] = { child = node.body, key = "body" }
    elseif kind == "fanout" then
        out[#out + 1] = { child = node.body, key = "body" }
    elseif kind == "wrap_step" then
        if node.on_mismatch ~= nil then
            out[#out + 1] = { child = node.on_mismatch, key = "on_mismatch" }
        end
    elseif kind == "once" then
        out[#out + 1] = { child = node.body, key = "body" }
    elseif kind == "map" or kind == "reduce" then
        out[#out + 1] = { child = node.body, key = "body" }
    elseif kind == "switch" then
        for i, c in ipairs(node.cases) do
            out[#out + 1] = { child = c.body, key = "cases", idx = i }
        end
        if node.else_ ~= nil then
            out[#out + 1] = { child = node.else_, key = "else_" }
        end
    elseif kind == "try" then
        out[#out + 1] = { child = node.body,  key = "body" }
        out[#out + 1] = { child = node.catch, key = "catch" }
    end
    -- return_early is a leaf Node (only optional Expr `value`).
    -- step / let / call have no direct child Nodes (only Exprs/args).
    -- wrap_step's only structural child is the optional on_mismatch Node;
    -- slot / in_ are Exprs, not structural children.
    return out
end

--- Enumerate direct child Exprs of an Expr.
---
--- Returns `{ child = Expr, key = string|integer }` entries. Used by
--- the compile validator and (Phase 3) `refs_of` to walk Expr trees.
---
---@param expr flow.ir.Expr
---@return { child: flow.ir.Expr, key: string|integer }[]
function M.expr_children_of(expr)
    local out = {}
    local op = expr.op
    if op == "eq" or op == "lt"
        or op == "add" or op == "sub" or op == "mul" or op == "div" or op == "mod"
        or op == "gt" or op == "gte" or op == "lte" or op == "ne" then
        out[#out + 1] = { child = expr.lhs, key = "lhs" }
        out[#out + 1] = { child = expr.rhs, key = "rhs" }
    elseif op == "and" or op == "or" then
        for i, ch in ipairs(expr.args) do
            out[#out + 1] = { child = ch, key = "args", idx = i }
        end
    elseif op == "not" or op == "len" or op == "exists" then
        out[#out + 1] = { child = expr.arg, key = "arg" }
    elseif op == "concat" then
        for i, ch in ipairs(expr.args) do
            out[#out + 1] = { child = ch, key = "args", idx = i }
        end
    elseif op == "get" then
        out[#out + 1] = { child = expr.from, key = "from" }
        out[#out + 1] = { child = expr.key, key = "key" }
    elseif op == "format" then
        out[#out + 1] = { child = expr.fmt, key = "fmt" }
        for i, ch in ipairs(expr.args) do
            out[#out + 1] = { child = ch, key = "args", idx = i }
        end
    elseif op == "filter" then
        out[#out + 1] = { child = expr.from, key = "from" }
        out[#out + 1] = { child = expr.pred, key = "pred" }
    elseif op == "fold" then
        out[#out + 1] = { child = expr.from, key = "from" }
        out[#out + 1] = { child = expr.init, key = "init" }
        out[#out + 1] = { child = expr.fn,   key = "fn" }
    end
    -- path / lit / var are leaves.
    return out
end

-- ── type query ──────────────────────────────────────────────────────

--- Return the kind of a Node (`"step"` / `"seq"` / ...).
---@param node flow.ir.Node
---@return string
function M.type_of(node)
    return node.kind
end

-- ── walk ────────────────────────────────────────────────────────────

local function append_path(base, key, idx)
    local out = {}
    for i, v in ipairs(base) do out[i] = v end
    out[#out + 1] = key
    if idx ~= nil then out[#out + 1] = idx end
    return out
end

--- Depth-first pre-order walk over a Node tree.
---
--- Visits the root first, then descends in `children_of` order.
--- Returns `"stop"` if the visitor aborted, otherwise `nil`.
---
---@param node    flow.ir.Node
---@param visitor fun(node: flow.ir.Node, ctx: { depth: integer, parent: flow.ir.Node?, path: (string|integer)[] }): nil|"skip"|"stop"
---@param _ctx    table?  internal; do not pass at top-level call sites
---@return nil|"stop"
function M.walk(node, visitor, _ctx)
    local ctx = _ctx or { depth = 0, parent = nil, path = {} }
    local r = visitor(node, ctx)
    if r == "stop" then return "stop" end
    if r == "skip" then return nil end
    for _, entry in ipairs(M.children_of(node)) do
        local child_path = append_path(ctx.path, entry.key, entry.idx)
        local child_ctx = {
            depth  = ctx.depth + 1,
            parent = node,
            path   = child_path,
        }
        local sub = M.walk(entry.child, visitor, child_ctx)
        if sub == "stop" then return "stop" end
    end
    return nil
end

-- ── refs collection ─────────────────────────────────────────────────

--- Collect every `path` Expr reference reachable from a Node or Expr.
---
--- Walks both the Node tree (via `children_of`) and every Expr sub-tree
--- (via `expr_children_of`). Returns a list of `at` strings in
--- traversal order (duplicates preserved — caller dedupes if needed).
---
--- Currently only `path.at` is considered a "ref"; `call.flow` and
--- `step.ref` are also opaque registry references and are appended at
--- the end of the result tagged via a structured form. (Phase 3 §3.A
--- finalizes the public shape; the internal form is intentionally
--- lightweight.)
---
---@param node_or_expr flow.ir.Node|flow.ir.Expr
---@return string[]  list of referenced ctx-path strings (Expr.path.at)
function M.refs_of(node_or_expr)
    local out = {}
    local function collect_expr(e)
        if type(e) ~= "table" then return end
        if e.op == "path" then
            out[#out + 1] = e.at
            return
        end
        for _, entry in ipairs(M.expr_children_of(e)) do
            collect_expr(entry.child)
        end
    end
    local function collect_node(n)
        if type(n) ~= "table" then return end
        local k = n.kind
        if k == "step" then
            if n.in_ ~= nil then collect_expr(n.in_) end
        elseif k == "branch" then
            collect_expr(n.cond)
        elseif k == "let" then
            collect_expr(n.value)
        elseif k == "loop" then
            collect_expr(n.cond)
        elseif k == "call" then
            for _, e in pairs(n.args) do collect_expr(e) end
        elseif k == "fanout" then
            collect_expr(n.items)
        elseif k == "wrap_step" then
            collect_expr(n.slot)
            if n.in_ ~= nil then collect_expr(n.in_) end
        elseif k == "fail" then
            collect_expr(n.message)
        elseif k == "assert" then
            collect_expr(n.cond)
            collect_expr(n.message)
        elseif k == "map" then
            collect_expr(n.in_)
        elseif k == "reduce" then
            collect_expr(n.in_)
            collect_expr(n.init)
        elseif k == "switch" then
            collect_expr(n.on)
            for _, c in ipairs(n.cases) do collect_expr(c.match) end
        elseif k == "return_early" then
            if n.value ~= nil then collect_expr(n.value) end
        end
        for _, entry in ipairs(M.children_of(n)) do
            collect_node(entry.child)
        end
    end
    -- Dispatch on shape: Node has `kind`, Expr has `op`.
    if node_or_expr.kind ~= nil then
        collect_node(node_or_expr)
    elseif node_or_expr.op ~= nil then
        collect_expr(node_or_expr)
    end
    return out
end

return M
