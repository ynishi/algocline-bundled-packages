---@module 'flow.ir.schema'
-- Node + Expr schema (Schema-as-Data).
--
-- MVP surface: 3 Node kinds (step / seq / branch) + 3 Expr ops
-- (path / lit / eq).
--
-- ## Why discriminated + open=false
--
-- alc_shapes discriminated (alc_shapes.t §discriminated) requires each
-- variant to declare the tag field via T.one_of({"X"}) — belt-and-
-- suspenders fail-loud (C4 in alc_shapes/t.lua). Typos in `kind` /
-- `op` are caught at compile (`flow.ir.compile`) rather than silently
-- passing through at exec. `open = false` rejects unknown top-level
-- fields so e.g. `{ kind = "step", agnet = "x", ... }` (typo in
-- `agent`) fails loud instead of leaking through.
--
-- ## Why T.table for children (not T.ref recursion)
--
-- Recursive children (seq.children / branch.then_ / branch.else_) are
-- declared as T.table rather than T.ref("Node"). MVP avoids registry-
-- resolved recursion. Instead, `flow.ir.compile` walks every nested
-- Node / Expr by hand. The two-pass model (shallow alc_shapes check +
-- recursive walk) is equivalent in coverage and easier to debug.
--
-- ## Stability contract
--
-- The IR shape declared here is the public Schema-as-Data SoT for
-- `flow.ir`. Consumers MAY rawget on these fields:
--
--   step.kind / step.agent / step.in_ / step.out
--   seq.kind / seq.children
--   branch.kind / branch.cond / branch.then_ / branch.else_
--   Expr.path.op / Expr.path.at
--   Expr.lit.op / Expr.lit.value
--   Expr.eq.op / Expr.eq.lhs / Expr.eq.rhs
--
-- Adding fields is non-breaking. Removing or renaming an exposed field
-- is a breaking change.

local T = require("alc_shapes.t")

local M = {}

-- ── Expr (op-tagged) ────────────────────────────────────────────────

---@class flow.ir.Expr.path
---@field op  "path"
---@field at  string  JSONPath-ish read, e.g. "$.ctx.verdict"

---@class flow.ir.Expr.lit
---@field op    "lit"
---@field value any  literal value (any Lua value)

---@class flow.ir.Expr.eq
---@field op   "eq"
---@field lhs  flow.ir.Expr  nested Expr (walked by compile)
---@field rhs  flow.ir.Expr  nested Expr (walked by compile)

---@alias flow.ir.Expr
---| flow.ir.Expr.path
---| flow.ir.Expr.lit
---| flow.ir.Expr.eq

---@type AlcShapeDiscriminated  alc_shapes discriminated schema over `op`
M.Expr = T.discriminated("op", {
    path = T.shape({
        op = T.one_of({ "path" }),
        at = T.string:describe("JSONPath-ish ref, e.g. $.ctx.verdict"),
    }, { open = false }),
    lit = T.shape({
        op    = T.one_of({ "lit" }),
        value = T.any:describe("literal value"),
    }, { open = false }),
    eq = T.shape({
        op  = T.one_of({ "eq" }),
        lhs = T.table:describe("nested Expr (walked by compile)"),
        rhs = T.table:describe("nested Expr (walked by compile)"),
    }, { open = false }),
})

---@type table<string, boolean>  Set of supported Expr ops (membership test).
M.EXPR_OPS = { path = true, lit = true, eq = true }

-- ── Node (kind-tagged) ──────────────────────────────────────────────

---@class flow.ir.Node.step
---@field kind   "step"
---@field agent  string  agent name, looked up via opts.dispatch
---@field in_    flow.ir.Expr|nil  input Expr; nil → dispatch receives nil
---@field out    string  ctx write path; must start with "ctx."

---@class flow.ir.Node.seq
---@field kind      "seq"
---@field children  flow.ir.Node[]  executed in order

---@class flow.ir.Node.branch
---@field kind   "branch"
---@field cond   flow.ir.Expr  truthiness of this Expr selects then_/else_
---@field then_  flow.ir.Node
---@field else_  flow.ir.Node

---@alias flow.ir.Node
---| flow.ir.Node.step
---| flow.ir.Node.seq
---| flow.ir.Node.branch

---@type AlcShapeDiscriminated  alc_shapes discriminated schema over `kind`
M.Node = T.discriminated("kind", {
    step = T.shape({
        kind  = T.one_of({ "step" }),
        agent = T.string:describe("agent name, registry lookup key"),
        in_   = T.table:is_optional():describe("input Expr (walked)"),
        out   = T.string:describe("ctx write path, must start with 'ctx.'"),
    }, { open = false }),
    seq = T.shape({
        kind     = T.one_of({ "seq" }),
        children = T.array_of(T.table):describe("nested Nodes (walked)"),
    }, { open = false }),
    branch = T.shape({
        kind  = T.one_of({ "branch" }),
        cond  = T.table:describe("nested Expr (walked)"),
        then_ = T.table:describe("nested Node (walked)"),
        else_ = T.table:describe("nested Node (walked)"),
    }, { open = false }),
})

---@type table<string, boolean>  Set of supported Node kinds (membership test).
M.NODE_KINDS = { step = true, seq = true, branch = true }

return M
