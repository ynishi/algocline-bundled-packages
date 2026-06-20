---@module 'flow.ir'
-- Flow IR (data Def) + interpreter (Exec) + Constructor API.
--
-- A minimum-primitive substrate that lets a pipeline be authored as a
-- single Lua table (Def), validated structurally (Compile), and walked
-- by a host-neutral interpreter (Exec). The Def is the IR — `compile`
-- returns the same table on success; no separate transformation.
--
-- ## Public surface (v0.4.0)
--
-- Schema (Schema-as-Data SoT):
--   M.Node  : alc_shapes discriminated over `kind`
--   M.Expr  : alc_shapes discriminated over `op`
--
-- Pipeline:
--   M.compile(ir)            : Def → validated IR (identity on success)
--   M.exec(compiled, ctx, opts)
--   M.default_dispatch       : public stub (raises "no dispatch configured")
--
-- Introspect (§3.A; consumer-facing contract for engine integrators):
--   M.walk(node, visitor)    : depth-first pre-order over the Node tree
--   M.type_of(node)          : "step" / "seq" / "branch" / ... (node.kind)
--   M.children_of(node)      : direct child Nodes with accessor keys
--   M.refs_of(node_or_expr)  : every `path.at` reachable from a subtree
--
-- Constructor API (thin sugar over raw table SoT):
--   Expr (8 ops, hybrid args):
--     M.path(at) / M.lit(value)
--     M.eq(lhs, rhs) / M.lt(lhs, rhs)
--     M["and"](...) / M["or"](...)   -- variadic, bracket for reserved word
--     M["not"](arg)                   -- bracket for reserved word
--     M.len(arg)
--   Node (7 kinds, table-arg named; seq variadic):
--     M.step({ ref, out, in_ })       -- in_ field uses underscore suffix
--     M.seq(...)                       -- variadic children
--     M.branch({ cond, then_, else_ })
--     M["let"]({ at, value })          -- bracket for reserved word
--     M.loop({ cond, body, max, counter })
--     M.call({ flow, args, out })
--     M.fanout({ items, bind, body, join, out })
--
-- ## Raw table SoT
--
-- The raw table form is the Single Source of Truth. Constructors are
-- thin wrappers that build raw tables; the schema (M.Node / M.Expr) and
-- compile / exec operate on raw tables. Callers MAY construct raw
-- tables directly (`{kind="seq", children={...}}`) — they are accepted
-- without any normalization step. Constructors are provided so that
-- (a) external callers do not re-invent spec-local helpers, and
-- (b) Lua reserved words (`and` / `or` / `not` / `let`) get a single
-- canonical access form (bracket).
--
-- ## Stability contract
--
-- The schema (M.Node / M.Expr) is the public Schema-as-Data SoT.
-- Adding fields is non-breaking; removing or renaming an exposed field
-- is a breaking change. Constructor signatures are part of the public
-- surface and follow the same SemVer policy.
--
-- See `flow/doc/ir.md` for the full Def→Compile→Exec contract.
--
-- Reference: classic Def→Compile→Exec pipeline over a Schema-as-Data
-- IR (after Malli; via alc_shapes.t discriminated/shape).
-- Structural control completeness follows Böhm–Jacopini (1966).

local schema      = require("flow.ir.schema")
local compile_mod = require("flow.ir.compile")
local interp      = require("flow.ir.interpreter")
local walk_mod    = require("flow.ir.walk")

local M = {}

---@type AlcShapeDiscriminated  see flow.ir.schema.Node
M.Node    = schema.Node

---@type AlcShapeDiscriminated  see flow.ir.schema.Expr
M.Expr    = schema.Expr

--- Compile a Lua-table IR (Def) into a validated IR.
---
--- See flow.ir.compile §Static guarantees for the full invariant list.
--- On success the same `ir` table is returned (identity); on failure
--- (nil, reason) where reason is a JSONPath-ish string.
---
---@type fun(ir: flow.ir.Node): flow.ir.Node|nil, string?
M.compile = compile_mod.compile

--- Execute a compiled IR against an initial ctx.
---
--- See flow.ir.interpreter §Dispatch injection / §Path resolution for
--- the runtime contract. `opts.dispatch(ref, input)` is required for
--- any IR that contains a `step` node; the default stub raises. The
--- interpreter is host-neutral — `ref` is an opaque string the host
--- alone interprets.
---
---@type fun(compiled: flow.ir.Node, ctx: table, opts: flow.ir.ExecOpts?): table
M.exec    = interp.exec

--- Public default dispatch helper — returns (nil, reason); raises when
--- invoked by exec without a caller-supplied dispatch. Exposed so host
--- wrappers can fall through to it for unknown refs.
---@type fun(ref: string, input: any): nil, string
M.default_dispatch = interp.default_dispatch

-- ── Introspect API (§3.A) ───────────────────────────────────────────
--
-- Read-only walk + type query over a Node tree. The visitor signature
-- is the **public contract** and is intentionally frozen — extending
-- it later would be a SemVer-major break. Lock literal:
--
--   visitor(node, ctx) -> nil | "skip" | "stop"
--     node : current Node (read-only; mutate is undefined behavior)
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
-- Walks are Node-tree only — Expr sub-trees of e.g. `branch.cond` are
-- not visited by `walk`. To collect references inside Exprs use
-- `refs_of`.

--- Depth-first pre-order walk over a Node tree.
---
--- Visits the root first, then descends in `children_of` order.
--- Returns "stop" if the visitor aborted, otherwise nil.
---
---@type fun(node: flow.ir.Node, visitor: fun(node: flow.ir.Node, ctx: { depth: integer, parent: flow.ir.Node?, path: (string|integer)[] }): nil|"skip"|"stop"): nil|"stop"
M.walk = walk_mod.walk

--- Return the kind of a Node (`"step"` / `"seq"` / `"branch"` / etc.).
--- Equivalent to `node.kind` — provided for symmetry with `refs_of` /
--- `children_of` and to let consumers depend on the function rather
--- than on the raw-table layout.
---@type fun(node: flow.ir.Node): string
M.type_of = walk_mod.type_of

--- Enumerate direct child Nodes of a Node with their accessor keys.
---
--- Returns a list of `{ child = Node, key = string|integer, idx = integer? }`
--- entries. For `seq.children[i]`, `key = "children"` and `idx = i`.
--- For named accessors (`then_` / `else_` / `body`), only `key` is set.
--- Returns `{}` for leaf Nodes (`step` / `let` / `call`, which have no
--- structural sub-Nodes).
---
---@type fun(node: flow.ir.Node): { child: flow.ir.Node, key: string|integer, idx: integer? }[]
M.children_of = walk_mod.children_of

--- Collect every `path.at` string reachable from a Node or Expr.
---
--- Walks the Node tree and every Expr sub-tree, returning the `at` of
--- every `path` Expr in traversal order. Duplicates are preserved
--- (callers dedupe if needed). Returns `{}` for subtrees that contain
--- no `path` Exprs.
---
---@type fun(node_or_expr: flow.ir.Node|flow.ir.Expr): string[]
M.refs_of = walk_mod.refs_of

-- ── Constructor API — Expr ──────────────────────────────────────────
--
-- Thin wrappers returning raw tables. Raw construction
-- (`{op="path", at=...}`) remains the SoT and is fully equivalent.

--- `path` Expr: read ctx via JSONPath-ish ref (e.g. "$.ctx.verdict").
---@param at string
---@return flow.ir.Expr.path
function M.path(at) return { op = "path", at = at } end

--- `lit` Expr: literal value (any Lua value).
---@param value any
---@return flow.ir.Expr.lit
function M.lit(value) return { op = "lit", value = value } end

--- `eq` Expr: Lua `==` over two nested Exprs.
---@param lhs flow.ir.Expr
---@param rhs flow.ir.Expr
---@return flow.ir.Expr.eq
function M.eq(lhs, rhs) return { op = "eq", lhs = lhs, rhs = rhs } end

--- `lt` Expr: Lua `<` over two nested Exprs (numeric or string).
---@param lhs flow.ir.Expr
---@param rhs flow.ir.Expr
---@return flow.ir.Expr.lt
function M.lt(lhs, rhs) return { op = "lt", lhs = lhs, rhs = rhs } end

--- `and` Expr: short-circuit, true iff every arg is truthy (length >= 2).
--- Bracket access (`M["and"]`) avoids Lua reserved word.
---@param ... flow.ir.Expr
---@return flow.ir.Expr.and
M["and"] = function(...) return { op = "and", args = { ... } } end

--- `or` Expr: short-circuit, true on first truthy arg (length >= 2).
--- Bracket access (`M["or"]`) avoids Lua reserved word.
---@param ... flow.ir.Expr
---@return flow.ir.Expr.or
M["or"] = function(...) return { op = "or", args = { ... } } end

--- `not` Expr: truthiness inversion.
--- Bracket access (`M["not"]`) avoids Lua reserved word.
---@param arg flow.ir.Expr
---@return flow.ir.Expr.not
M["not"] = function(arg) return { op = "not", arg = arg } end

--- `len` Expr: Lua `#` over a string or sequence-style array.
---@param arg flow.ir.Expr
---@return flow.ir.Expr.len
function M.len(arg) return { op = "len", arg = arg } end

-- ── Constructor API — Node ──────────────────────────────────────────
--
-- Node constructors take a single spec table (named args). `seq` is
-- variadic over children since the only required field is the child
-- list. Reserved-word field names (`let`) use bracket access.
--
-- Note: step's input field is `in_` (underscore suffix, not bracket
-- `["in"]`) for consistency with the schema (flow/ir/schema.lua) and
-- interpreter, which already use `in_` to avoid the Lua reserved word.

--- `step` Node: host-escape effect; calls opts.dispatch(ref, input).
---@param spec { ref: string, out: string, in_: flow.ir.Expr? }
---@return flow.ir.Node.step
function M.step(spec)
    return {
        kind = "step",
        ref  = spec.ref,
        out  = spec.out,
        in_  = spec.in_,
    }
end

--- `seq` Node: execute children in order. Variadic.
---@param ... flow.ir.Node
---@return flow.ir.Node.seq
function M.seq(...)
    return { kind = "seq", children = { ... } }
end

--- `branch` Node: select then_/else_ by truthiness of cond.
---@param spec { cond: flow.ir.Expr, then_: flow.ir.Node, else_: flow.ir.Node? }
---@return flow.ir.Node.branch
function M.branch(spec)
    return {
        kind  = "branch",
        cond  = spec.cond,
        then_ = spec.then_,
        else_ = spec.else_,
    }
end

--- `let` Node: bind Expr value to ctx[at] (pure, no host call).
--- Bracket access (`M["let"]`) avoids Lua reserved word.
---@param spec { at: string, value: flow.ir.Expr }
---@return flow.ir.Node.let
M["let"] = function(spec)
    return {
        kind  = "let",
        at    = spec.at,
        value = spec.value,
    }
end

--- `loop` Node: while-loop with hard `max` cap; writes iteration index
--- to `counter` (0 before entering, then incremented per iter).
---@param spec { cond: flow.ir.Expr, body: flow.ir.Node, max: integer, counter: string }
---@return flow.ir.Node.loop
function M.loop(spec)
    return {
        kind    = "loop",
        cond    = spec.cond,
        body    = spec.body,
        max     = spec.max,
        counter = spec.counter,
    }
end

--- `call` Node: invoke sub-flow registered under `opts.flows[flow]`;
--- evaluates each `args[k]` against caller ctx and writes sub-ctx to
--- ctx[out] when done. Recursion capped by opts.max_call_depth.
---@param spec { flow: string, args: table<string, flow.ir.Expr>, out: string }
---@return flow.ir.Node.call
function M.call(spec)
    return {
        kind = "call",
        flow = spec.flow,
        args = spec.args,
        out  = spec.out,
    }
end

--- `fanout` Node: evaluate `items` to an array, run `body` per item
--- with a branch-local ctx (shallow copy + `bind` written to the item),
--- join per `join` ∈ {"all","any"}, write to ctx[out].
---@param spec { items: flow.ir.Expr, bind: string, body: flow.ir.Node, join: "all"|"any", out: string }
---@return flow.ir.Node.fanout
function M.fanout(spec)
    return {
        kind  = "fanout",
        items = spec.items,
        bind  = spec.bind,
        body  = spec.body,
        join  = spec.join,
        out   = spec.out,
    }
end

return M
