---@module 'flow.ir.schema'
-- Node + Expr schema (Schema-as-Data).
--
-- MVP surface: 3 Node kinds (step / seq / branch) + 3 Expr ops
-- (path / lit / eq). `step` is the host-escape effect Node (calls
-- opts.dispatch); the remaining Node kinds and all Expr ops are
-- host-neutral (pure structured control + pure value computation).
--
-- ## Why discriminated + open=false
--
-- alc_shapes discriminated (alc_shapes.t §discriminated) requires each
-- variant to declare the tag field via T.one_of({"X"}) — belt-and-
-- suspenders fail-loud (C4 in alc_shapes/t.lua). Typos in `kind` /
-- `op` are caught at compile (`flow.ir.compile`) rather than silently
-- passing through at exec. `open = false` rejects unknown top-level
-- fields so e.g. `{ kind = "step", rf = "x", ... }` (typo in `ref`)
-- fails loud instead of leaking through.
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
--   step.kind / step.ref / step.in_ / step.out
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

---@class flow.ir.Expr.and
---@field op    "and"
---@field args  flow.ir.Expr[]  nested Exprs (walked, length >= 2)

---@class flow.ir.Expr.not
---@field op   "not"
---@field arg  flow.ir.Expr  nested Expr (walked)

---@class flow.ir.Expr.lt
---@field op   "lt"
---@field lhs  flow.ir.Expr  nested Expr (walked); numeric or string
---@field rhs  flow.ir.Expr  nested Expr (walked); same type as lhs

---@class flow.ir.Expr.or
---@field op    "or"
---@field args  flow.ir.Expr[]  nested Exprs (walked, length >= 2)

---@class flow.ir.Expr.len
---@field op   "len"
---@field arg  flow.ir.Expr  nested Expr (walked); must eval to string or array

---@class flow.ir.Expr.concat
---@field op    "concat"
---@field args  flow.ir.Expr[]  nested Exprs (walked, length >= 2); each must
---  eval to a string at runtime (no implicit tostring coercion)

---@class flow.ir.Expr.add
---@field op   "add"
---@field lhs  flow.ir.Expr  nested Expr (walked); must eval to a number
---@field rhs  flow.ir.Expr  nested Expr (walked); must eval to a number

---@class flow.ir.Expr.get
---@field op    "get"
---@field from  flow.ir.Expr  nested Expr (walked); must eval to a table
---@field key   flow.ir.Expr  nested Expr (walked); must eval to a string or number

---@alias flow.ir.Expr
---| flow.ir.Expr.path
---| flow.ir.Expr.lit
---| flow.ir.Expr.eq
---| flow.ir.Expr.and
---| flow.ir.Expr.not
---| flow.ir.Expr.lt
---| flow.ir.Expr.or
---| flow.ir.Expr.len
---| flow.ir.Expr.concat
---| flow.ir.Expr.add
---| flow.ir.Expr.get

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
    ["and"] = T.shape({
        op   = T.one_of({ "and" }),
        args = T.array_of(T.table):describe("nested Exprs (walked, length >= 2)"),
    }, { open = false }),
    ["not"] = T.shape({
        op  = T.one_of({ "not" }),
        arg = T.table:describe("nested Expr (walked)"),
    }, { open = false }),
    lt = T.shape({
        op  = T.one_of({ "lt" }),
        lhs = T.table:describe("nested Expr (walked); numeric or string"),
        rhs = T.table:describe("nested Expr (walked); same type as lhs"),
    }, { open = false }),
    ["or"] = T.shape({
        op   = T.one_of({ "or" }),
        args = T.array_of(T.table):describe("nested Exprs (walked, length >= 2)"),
    }, { open = false }),
    len = T.shape({
        op  = T.one_of({ "len" }),
        arg = T.table:describe("nested Expr (walked); must eval to string or array"),
    }, { open = false }),
    concat = T.shape({
        op   = T.one_of({ "concat" }),
        args = T.array_of(T.table):describe(
            "nested Exprs (walked, length >= 2); each must eval to a string at "
            .. "runtime (exec raises on non-string; no implicit tostring coercion)"),
    }, { open = false }),
    add = T.shape({
        op  = T.one_of({ "add" }),
        lhs = T.table:describe("nested Expr (walked); must eval to a number"),
        rhs = T.table:describe("nested Expr (walked); must eval to a number"),
    }, { open = false }),
    get = T.shape({
        op   = T.one_of({ "get" }),
        from = T.table:describe("nested Expr (walked); must eval to a table"),
        key  = T.table:describe("nested Expr (walked); must eval to a string or number"),
    }, { open = false }),
})

---@type table<string, boolean>  Set of supported Expr ops (membership test).
M.EXPR_OPS = {
    path = true, lit = true, eq = true,
    ["and"] = true, ["not"] = true, lt = true,
    ["or"] = true, len = true,
    concat = true, add = true, get = true,
}

-- ── Node (kind-tagged) ──────────────────────────────────────────────

---@class flow.ir.Node.step
---@field kind   "step"
---@field ref    string  opaque handler reference passed to opts.dispatch
---@field in_    flow.ir.Expr|nil  input Expr; nil → dispatch receives nil
---@field out    string  ctx write path; must start with "ctx."

---@class flow.ir.Node.seq
---@field kind      "seq"
---@field children  flow.ir.Node[]  executed in order

---@class flow.ir.Node.branch
---@field kind   "branch"
---@field cond   flow.ir.Expr  truthiness of this Expr selects then_/else_
---@field then_  flow.ir.Node
---@field else_  flow.ir.Node|nil  omit for no-op on falsy cond

---@class flow.ir.Node.let
---@field kind   "let"
---@field at     string        ctx write path; must start with "ctx."
---@field value  flow.ir.Expr  Expr evaluated and bound to ctx[at]

---@class flow.ir.Node.loop
---@field kind     "loop"
---@field cond     flow.ir.Expr  while-loop condition (eval'd before each iter)
---@field body     flow.ir.Node  body executed per iteration
---@field max      integer       hard upper bound on iteration count (>= 1)
---@field counter  string        ctx write path for iteration index ("ctx.*")

---@class flow.ir.Node.call
---@field kind  "call"
---@field flow  string                          registry key looked up via opts.flows
---@field args  table<string, flow.ir.Expr>    mapped into sub-flow ctx
---@field out   string                          ctx write path for sub-ctx ("ctx.*")

---@class flow.ir.Node.fanout
---@field kind   "fanout"
---@field items  flow.ir.Expr  Expr evaluating to a Lua array
---@field bind   string        per-branch ctx write path for the item ("ctx.*")
---@field body   flow.ir.Node  executed per item against branch-local ctx
---@field join   "all"|"any"|"race"|"all_settled"  join mode (see §fanout semantics)
---@field out    string        joined result write path ("ctx.*")

---@class flow.ir.Node.wrap_step
---@field kind         "wrap_step"
---@field slot         flow.ir.Expr  Expr evaluating to a non-empty string;
---  used as the ReqToken slot label (and, when bound, as the persistence key).
---@field ref          string        opaque handler reference, passed to opts.dispatch
---@field in_          flow.ir.Expr|nil  input Expr; nil → dispatch receives nil
---@field out          string        ctx write path; must start with "ctx."
---@field bound        boolean|nil   when true, persist req under state.data._flow_req_<slot>
---  and auto-delete on verify success (session-spanning). Default false (in-memory cycle).
---@field on_mismatch  flow.ir.Node|nil  Node executed when verify returns false
---  (instead of raising). When nil, exec raises with a slot-tagged message.

---@alias flow.ir.Node
---| flow.ir.Node.step
---| flow.ir.Node.seq
---| flow.ir.Node.branch
---| flow.ir.Node.let
---| flow.ir.Node.loop
---| flow.ir.Node.call
---| flow.ir.Node.fanout
---| flow.ir.Node.wrap_step

---@type AlcShapeDiscriminated  alc_shapes discriminated schema over `kind`
M.Node = T.discriminated("kind", {
    step = T.shape({
        kind = T.one_of({ "step" }),
        ref  = T.string:describe("opaque handler reference, passed to opts.dispatch"),
        in_  = T.table:is_optional():describe("input Expr (walked)"),
        out  = T.string:describe("ctx write path, must start with 'ctx.'"),
    }, { open = false }),
    seq = T.shape({
        kind     = T.one_of({ "seq" }),
        children = T.array_of(T.table):describe("nested Nodes (walked)"),
    }, { open = false }),
    branch = T.shape({
        kind  = T.one_of({ "branch" }),
        cond  = T.table:describe("nested Expr (walked)"),
        then_ = T.table:describe("nested Node (walked)"),
        else_ = T.table:is_optional():describe("nested Node (walked); omit for no-op"),
    }, { open = false }),
    ["let"] = T.shape({
        kind  = T.one_of({ "let" }),
        at    = T.string:describe("ctx write path, must start with 'ctx.'"),
        value = T.table:describe("nested Expr (walked)"),
    }, { open = false }),
    loop = T.shape({
        kind    = T.one_of({ "loop" }),
        cond    = T.table:describe("nested Expr (walked, evaluated before each iter)"),
        body    = T.table:describe("nested Node (walked)"),
        max     = T.number:describe("hard iteration cap, integer >= 1"),
        counter = T.string:describe("ctx write path for iteration index, 'ctx.*'"),
    }, { open = false }),
    call = T.shape({
        kind = T.one_of({ "call" }),
        flow = T.string:describe("registry key looked up via opts.flows"),
        args = T.table:describe("{ key = Expr, ... } mapped into sub-flow ctx"),
        out  = T.string:describe("ctx write path for sub-flow ctx, 'ctx.*'"),
    }, { open = false }),
    fanout = T.shape({
        kind  = T.one_of({ "fanout" }),
        items = T.table:describe("nested Expr (walked); must eval to a Lua array"),
        bind  = T.string:describe("per-branch ctx write path for the item, 'ctx.*'"),
        body  = T.table:describe("nested Node (walked, runs per item)"),
        join  = T.one_of({ "all", "any", "race", "all_settled" }):describe(
            "join semantics (Promise / futures combinators): "
            .. "'all' collects every branch ctx (Promise.all / try_join_all); "
            .. "'any' returns the first non-raising branch's ctx (Promise.any / select_ok); "
            .. "'race' returns the first branch to settle, success OR raise "
            .. "(Promise.race / select_all first); "
            .. "'all_settled' runs every branch and writes "
            .. "{status='fulfilled'|'rejected', value=ctx|reason=msg} per item "
            .. "(Promise.allSettled / join_all)"),
        out   = T.string:describe("joined result write path, 'ctx.*'"),
    }, { open = false }),
    wrap_step = T.shape({
        kind        = T.one_of({ "wrap_step" }),
        slot        = T.table:describe(
            "nested Expr (walked); must eval to a non-empty string at runtime. "
            .. "Used as the ReqToken slot label and (when bound) as the "
            .. "state.data._flow_req_<slot> persistence key."),
        ref         = T.string:describe("opaque handler reference, passed to opts.dispatch"),
        in_         = T.table:is_optional():describe("input Expr (walked)"),
        out         = T.string:describe("ctx write path, must start with 'ctx.'"),
        bound       = T.boolean:is_optional():describe(
            "when true, persist req under state.data._flow_req_<slot> "
            .. "(survives session restart); default false (in-memory cycle)"),
        on_mismatch = T.table:is_optional():describe(
            "nested Node (walked); executed when verify returns false. "
            .. "When omitted, exec raises with a slot-tagged mismatch message."),
    }, { open = false }),
})

---@type table<string, boolean>  Set of supported Node kinds (membership test).
M.NODE_KINDS = {
    step = true, seq = true, branch = true,
    ["let"] = true, loop = true, call = true, fanout = true,
    wrap_step = true,
}

return M
