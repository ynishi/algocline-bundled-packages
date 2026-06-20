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

---@class flow.ir.Expr.var
---@field op    "var"
---@field name  string  reads from the binding env established by filter/fold

---@class flow.ir.Expr.filter
---@field op    "filter"
---@field from  flow.ir.Expr  must eval to a Lua array
---@field var   string        name bound to the current item while evaluating pred
---@field pred  flow.ir.Expr  truthy → keep element

---@class flow.ir.Expr.fold
---@field op        "fold"
---@field from      flow.ir.Expr  must eval to a Lua array
---@field init      flow.ir.Expr  initial accumulator
---@field acc_var   string        name bound to the running acc inside fn
---@field item_var  string        name bound to the current item inside fn
---@field fn        flow.ir.Expr  Expr returning the new acc (becomes next iter's acc_var)

---@class flow.ir.Expr.sub
---@field op   "sub"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.mul
---@field op   "mul"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.div
---@field op   "div"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr  raises on division by zero

---@class flow.ir.Expr.mod
---@field op   "mod"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr  raises on modulo by zero

---@class flow.ir.Expr.gt
---@field op   "gt"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.gte
---@field op   "gte"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.lte
---@field op   "lte"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.ne
---@field op   "ne"
---@field lhs  flow.ir.Expr
---@field rhs  flow.ir.Expr

---@class flow.ir.Expr.exists
---@field op    "exists"
---@field arg   flow.ir.Expr  truthy iff arg evaluates to a non-nil value

---@class flow.ir.Expr.format
---@field op    "format"
---@field fmt   flow.ir.Expr  Expr → string (string.format format string)
---@field args  flow.ir.Expr[]  positional args (any Lua values accepted by string.format)

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
---| flow.ir.Expr.sub
---| flow.ir.Expr.mul
---| flow.ir.Expr.div
---| flow.ir.Expr.mod
---| flow.ir.Expr.gt
---| flow.ir.Expr.gte
---| flow.ir.Expr.lte
---| flow.ir.Expr.ne
---| flow.ir.Expr.exists
---| flow.ir.Expr.format
---| flow.ir.Expr.get
---| flow.ir.Expr.var
---| flow.ir.Expr.filter
---| flow.ir.Expr.fold

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
    sub = T.shape({
        op  = T.one_of({ "sub" }),
        lhs = T.table:describe("nested Expr; must eval to a number"),
        rhs = T.table:describe("nested Expr; must eval to a number"),
    }, { open = false }),
    mul = T.shape({
        op  = T.one_of({ "mul" }),
        lhs = T.table:describe("nested Expr; must eval to a number"),
        rhs = T.table:describe("nested Expr; must eval to a number"),
    }, { open = false }),
    div = T.shape({
        op  = T.one_of({ "div" }),
        lhs = T.table:describe("nested Expr; must eval to a number"),
        rhs = T.table:describe("nested Expr; must eval to a non-zero number"),
    }, { open = false }),
    mod = T.shape({
        op  = T.one_of({ "mod" }),
        lhs = T.table:describe("nested Expr; must eval to a number"),
        rhs = T.table:describe("nested Expr; must eval to a non-zero number"),
    }, { open = false }),
    gt = T.shape({
        op  = T.one_of({ "gt" }),
        lhs = T.table, rhs = T.table,
    }, { open = false }),
    gte = T.shape({
        op  = T.one_of({ "gte" }),
        lhs = T.table, rhs = T.table,
    }, { open = false }),
    lte = T.shape({
        op  = T.one_of({ "lte" }),
        lhs = T.table, rhs = T.table,
    }, { open = false }),
    ne = T.shape({
        op  = T.one_of({ "ne" }),
        lhs = T.table, rhs = T.table,
    }, { open = false }),
    exists = T.shape({
        op  = T.one_of({ "exists" }),
        arg = T.table:describe("nested Expr; truthy iff result is non-nil"),
    }, { open = false }),
    format = T.shape({
        op   = T.one_of({ "format" }),
        fmt  = T.table:describe("nested Expr; must eval to a string (string.format fmt)"),
        args = T.array_of(T.table):describe("nested Exprs (walked); positional args"),
    }, { open = false }),
    ["var"] = T.shape({
        op   = T.one_of({ "var" }),
        name = T.string:describe("binding name resolved from the enclosing filter/fold env"),
    }, { open = false }),
    filter = T.shape({
        op   = T.one_of({ "filter" }),
        from = T.table:describe("nested Expr; must eval to a Lua array"),
        var  = T.string:describe("binding name for the current item inside pred"),
        pred = T.table:describe("nested Expr (walked under var binding); truthy keeps element"),
    }, { open = false }),
    fold = T.shape({
        op       = T.one_of({ "fold" }),
        from     = T.table:describe("nested Expr; must eval to a Lua array"),
        init     = T.table:describe("nested Expr; initial accumulator"),
        acc_var  = T.string:describe("binding name for the running acc inside fn"),
        item_var = T.string:describe("binding name for the current item inside fn"),
        fn       = T.table:describe(
            "nested Expr (walked under acc_var + item_var bindings); returns next acc"),
    }, { open = false }),
})

---@type table<string, boolean>  Set of supported Expr ops (membership test).
M.EXPR_OPS = {
    path = true, lit = true, eq = true,
    ["and"] = true, ["not"] = true, lt = true,
    ["or"] = true, len = true,
    concat = true, add = true, get = true,
    sub = true, mul = true, div = true, mod = true,
    gt = true, gte = true, lte = true, ne = true,
    exists = true, format = true,
    ["var"] = true, filter = true, fold = true,
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

---@class flow.ir.Node.SwitchCase
---@field match  flow.ir.Expr  value compared (Lua `==`) against on
---@field body   flow.ir.Node  executed when match equals on

---@class flow.ir.Node.switch
---@field kind   "switch"
---@field on     flow.ir.Expr               value compared per case
---@field cases  flow.ir.Node.SwitchCase[]  evaluated in order, first match wins
---@field else_  flow.ir.Node|nil           default body when no case matches

---@class flow.ir.Node.try
---@field kind    "try"
---@field body    flow.ir.Node    executed under pcall
---@field catch   flow.ir.Node    executed when body raises (non-sentinel error)
---@field err_at  string|nil      optional ctx write path ("ctx.*") for the error message

---@class flow.ir.Node.return_early
---@field kind   "return_early"
---@field out    string|nil       optional ctx write path for the value
---@field value  flow.ir.Expr|nil optional Expr; written to ctx[out] before unwind

---@class flow.ir.Node.map
---@field kind     "map"
---@field in_      flow.ir.Expr  must eval to a Lua array
---@field bind     string        ctx write path for current item ("ctx.*")
---@field body     flow.ir.Node  runs per item against the shared ctx
---@field collect  string        ctx read sub-path under "$." prefix; the value
---  at this path after each body run is collected as the i-th element of out
---@field out      string        ctx write path for the collected array ("ctx.*")

---@class flow.ir.Node.reduce
---@field kind   "reduce"
---@field in_    flow.ir.Expr  must eval to a Lua array
---@field init   flow.ir.Expr  initial accumulator value
---@field acc    string        ctx write path used as accumulator ("ctx.*"); body
---  reads this to obtain the running acc and writes it to update.
---@field bind   string        ctx write path for current item ("ctx.*")
---@field body   flow.ir.Node  runs per item; expected to update ctx[acc]
---@field out    string        ctx write path for the final acc ("ctx.*")

---@class flow.ir.Node.fail
---@field kind     "fail"
---@field message  flow.ir.Expr  Expr evaluated to a string; raised as error

---@class flow.ir.Node.assert
---@field kind     "assert"
---@field cond     flow.ir.Expr  truthy → no-op; falsy → raises with message
---@field message  flow.ir.Expr  Expr evaluated to a string when cond is falsy

---@class flow.ir.Node.once
---@field kind  "once"
---@field flag  string        ctx write path; must start with "ctx.". Read as
---  `$.<flag>` before body; on truthy, body is skipped. After body completes,
---  `flag` is set to `true`. Use this as a resume guard so the body runs at
---  most once across re-entries (caller persists ctx via FlowState).
---@field body  flow.ir.Node

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
---| flow.ir.Node.once
---| flow.ir.Node.fail
---| flow.ir.Node.assert
---| flow.ir.Node.map
---| flow.ir.Node.reduce
---| flow.ir.Node.switch
---| flow.ir.Node.try
---| flow.ir.Node.return_early

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
    once = T.shape({
        kind = T.one_of({ "once" }),
        flag = T.string:describe(
            "ctx write path, must start with 'ctx.'; truthy value skips body, "
            .. "otherwise body runs and flag is set to true"),
        body = T.table:describe("nested Node (walked); executed at most once per ctx"),
    }, { open = false }),
    ["fail"] = T.shape({
        kind    = T.one_of({ "fail" }),
        message = T.table:describe("nested Expr (walked); must eval to a string"),
    }, { open = false }),
    ["assert"] = T.shape({
        kind    = T.one_of({ "assert" }),
        cond    = T.table:describe("nested Expr (walked); falsy → raise"),
        message = T.table:describe("nested Expr (walked); must eval to a string"),
    }, { open = false }),
    map = T.shape({
        kind    = T.one_of({ "map" }),
        in_     = T.table:describe("nested Expr (walked); must eval to a Lua array"),
        bind    = T.string:describe("ctx write path for current item, 'ctx.*'"),
        body    = T.table:describe("nested Node (walked); runs per item, shared ctx"),
        collect = T.string:describe(
            "ctx write path read back after each body run, 'ctx.*'; "
            .. "the value at this path becomes the i-th element of out"),
        out     = T.string:describe("ctx write path for the collected array, 'ctx.*'"),
    }, { open = false }),
    reduce = T.shape({
        kind = T.one_of({ "reduce" }),
        in_  = T.table:describe("nested Expr (walked); must eval to a Lua array"),
        init = T.table:describe("nested Expr (walked); initial accumulator value"),
        acc  = T.string:describe("ctx write path used as accumulator, 'ctx.*'"),
        bind = T.string:describe("ctx write path for current item, 'ctx.*'"),
        body = T.table:describe("nested Node (walked); runs per item, updates ctx[acc]"),
        out  = T.string:describe("ctx write path for the final acc, 'ctx.*'"),
    }, { open = false }),
    switch = T.shape({
        kind  = T.one_of({ "switch" }),
        on    = T.table:describe("nested Expr (walked); compared against each case"),
        cases = T.array_of(T.table):describe(
            "list of { match = Expr, body = Node }; evaluated in order, first match wins"),
        else_ = T.table:is_optional():describe("nested Node; default when no case matches"),
    }, { open = false }),
    ["try"] = T.shape({
        kind   = T.one_of({ "try" }),
        body   = T.table:describe("nested Node (walked); executed under pcall"),
        catch  = T.table:describe("nested Node (walked); runs on non-sentinel raise"),
        err_at = T.string:is_optional():describe("ctx write path for caught error message"),
    }, { open = false }),
    return_early = T.shape({
        kind  = T.one_of({ "return_early" }),
        out   = T.string:is_optional():describe("ctx write path for the value, 'ctx.*'"),
        value = T.table:is_optional():describe("nested Expr; written to ctx[out] before unwind"),
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
    wrap_step = true, once = true,
    ["fail"] = true, ["assert"] = true,
    map = true, reduce = true,
    switch = true, ["try"] = true, return_early = true,
}

return M
