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
-- Persistence (§3.2a; host-neutral, caller-injected JSON impl):
--   M.to_json(node, opts?)   : encode via opts.alc.json_encode / _G.alc
--   M.from_json(str, opts?)  : decode via opts.alc.json_decode / _G.alc
--   JSON impl is NOT bundled — flow.ir is interpreter-host-neutral.
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

-- ── Persistence API (§3.2a) ─────────────────────────────────────────
--
-- Node tree ↔ JSON via a caller-injected `alc.json_encode` /
-- `alc.json_decode` pair. flow.ir does NOT bundle a JSON impl
-- (host-neutral discipline). 2-step injection seam:
--
--   (1) opts.alc explicit injection (test seam; lets standalone
--       runners pass in pure_json or any other impl)
--   (2) `_G.alc` fall-through (production default; algocline runtime
--       provides alc.json_encode / json_decode)
--
-- Failure contract (canonicalized; impl-difference NOT exposed):
--   - alc / alc.json_encode missing       -> error("...required...")
--   - alc / alc.json_decode missing       -> error("...required...")
--   - encode raises                       -> propagated as error()
--   - decode raises OR returns nil+err    -> error("...decode failed:...")
--
-- Static-tree only: execution state / opts.dispatch / closures are
-- not persisted. JSON impls differ on array-vs-object detection,
-- sparse arrays, nil handling, etc. — those concerns are the
-- caller's (injected impl's) responsibility, not flow.ir's.

local function resolve_alc(opts, kind, fn_name)
    local alc = opts and opts.alc or _G.alc
    if not alc or not alc[fn_name] then
        error(string.format(
            "flow.ir.%s_json: alc.%s required (set _G.alc or pass opts.alc)",
            kind, fn_name), 3)
    end
    return alc[fn_name]
end

--- Serialize a (possibly compiled) Node tree to a JSON string.
---
--- Returns the encoded JSON string. Raises on missing encoder or on
--- encoder failure. Caller is responsible for ensuring the injected
--- `alc.json_encode` handles the table layout (e.g. empty `seq.children`
--- arrays may be encoded as `[]` or `{}` depending on impl — this is
--- caller's choice, not flow.ir's).
---
---@param node flow.ir.Node
---@param opts { alc: { json_encode: fun(any): string, json_decode: fun(string): any }? }?
---@return string json
function M.to_json(node, opts)
    local encode = resolve_alc(opts, "to", "json_encode")
    return encode(node)
end

--- Deserialize a JSON string into a Node tree (raw table form).
---
--- The returned value is the raw table the injected `alc.json_decode`
--- produces; it is NOT re-validated by `flow.ir.compile`. Run
--- `flow.ir.compile(node)` if structural guarantees are needed.
---
--- Errors are normalized: decoders that throw and decoders that return
--- `(nil, err)` are both surfaced as a single `error()` whose message
--- starts with "flow.ir.from_json: decode failed:".
---
---@param json_str string
---@param opts { alc: { json_encode: fun(any): string, json_decode: fun(string): any }? }?
---@return flow.ir.Node node
function M.from_json(json_str, opts)
    local decode = resolve_alc(opts, "from", "json_decode")
    local ok, decoded_or_err = pcall(decode, json_str)
    if not ok then
        error("flow.ir.from_json: decode failed: " .. tostring(decoded_or_err), 2)
    end
    if decoded_or_err == nil then
        error("flow.ir.from_json: decode failed: decoder returned nil", 2)
    end
    return decoded_or_err
end

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

--- `concat` Expr: string concatenation (length >= 2). Variadic. Every
--- arg must eval to a string at runtime — no implicit `tostring`
--- coercion. Use `M.lit("...")` for literal string segments.
---@param ... flow.ir.Expr
---@return flow.ir.Expr.concat
function M.concat(...) return { op = "concat", args = { ... } } end

--- `add` Expr: numeric addition over two nested Exprs. Both sides must
--- eval to numbers at runtime (no string-number coercion). Use
--- `M.concat` for string joining.
---@param lhs flow.ir.Expr
---@param rhs flow.ir.Expr
---@return flow.ir.Expr.add
function M.add(lhs, rhs) return { op = "add", lhs = lhs, rhs = rhs } end

--- `get` Expr: dynamic table read `from[key]`. `from` must eval to a
--- table; `key` must eval to a string or number. Complements `path`
--- (which is a compile-time fixed JSONPath) for runtime-computed keys.
--- Missing keys return nil (Lua `t[k]` semantics).
---@param from flow.ir.Expr
---@param key  flow.ir.Expr
---@return flow.ir.Expr.get
function M.get(from, key) return { op = "get", from = from, key = key } end

--- `sub` Expr: numeric subtraction (lhs - rhs). Both sides must eval to numbers.
function M.sub(lhs, rhs) return { op = "sub", lhs = lhs, rhs = rhs } end

--- `mul` Expr: numeric multiplication.
function M.mul(lhs, rhs) return { op = "mul", lhs = lhs, rhs = rhs } end

--- `div` Expr: numeric division. Raises on division by zero.
function M.div(lhs, rhs) return { op = "div", lhs = lhs, rhs = rhs } end

--- `mod` Expr: numeric modulo. Raises on modulo by zero.
function M.mod(lhs, rhs) return { op = "mod", lhs = lhs, rhs = rhs } end

--- `gt` / `gte` / `lte` / `ne` Exprs: comparison sugar over Lua operators.
function M.gt(lhs, rhs)  return { op = "gt",  lhs = lhs, rhs = rhs } end
function M.gte(lhs, rhs) return { op = "gte", lhs = lhs, rhs = rhs } end
function M.lte(lhs, rhs) return { op = "lte", lhs = lhs, rhs = rhs } end
function M.ne(lhs, rhs)  return { op = "ne",  lhs = lhs, rhs = rhs } end

--- `exists` Expr: truthy iff `arg` evaluates to a non-nil value. Equivalent
--- to `not(eq(arg, lit(nil)))` but expresses the intent directly.
function M.exists(arg) return { op = "exists", arg = arg } end

--- `format` Expr: `string.format(fmt, args...)`. `fmt` must eval to a string;
--- `args` evaluate to the positional substitutions in order.
---@param fmt flow.ir.Expr
---@param ... flow.ir.Expr
function M.format(fmt, ...) return { op = "format", fmt = fmt, args = { ... } } end

--- `var` Expr: read a named binding from the enclosing filter / fold env.
--- Raises at eval time when no binding env is active.
---@param name string
---@return flow.ir.Expr.var
M["var"] = function(name) return { op = "var", name = name } end

--- `filter` Expr: keep elements of `from` (array) for which `pred` is truthy,
--- with each element bound to `var` while evaluating pred.
---@param from flow.ir.Expr
---@param var  string
---@param pred flow.ir.Expr
---@return flow.ir.Expr.filter
function M.filter(from, var, pred)
    return { op = "filter", from = from, var = var, pred = pred }
end

--- `fold` Expr: left-fold over `from` (array). `init` seeds the accumulator;
--- per iter `fn` is evaluated with `acc_var` bound to the running acc and
--- `item_var` bound to the current element; its result becomes the next acc.
---@param spec { from: flow.ir.Expr, init: flow.ir.Expr, acc_var: string, item_var: string, fn: flow.ir.Expr }
---@return flow.ir.Expr.fold
function M.fold(spec)
    return {
        op       = "fold",
        from     = spec.from,
        init     = spec.init,
        acc_var  = spec.acc_var,
        item_var = spec.item_var,
        fn       = spec.fn,
    }
end

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

--- `wrap_step` Node: ReqToken-bracketed dispatch as a single AST atom.
---
--- Evaluates `slot` (Expr → non-empty string), issues+wraps a ReqToken
--- around the payload (`in_` if present), calls `opts.dispatch(ref,
--- wrapped_payload)`, then verifies the result echo. On verify success
--- the raw result is written to `ctx[out]`. On verify mismatch the
--- `on_mismatch` Node (if provided) runs against ctx (with the failing
--- result already written to `ctx[out]` so the fallback can inspect it);
--- when `on_mismatch` is omitted, exec raises a slot-tagged error.
---
--- `bound = true` switches issue / wrap / verify to the session-spanning
--- variants (`flow.token_wrap_bound` / `verify_bound`), persisting the
--- verify-side req under `state.data._flow_req_<slot>`. Bound mode
--- requires `opts.state` (FlowState) to be passed to `flow.ir.exec`.
---
--- The pkg-side contract is unchanged from §11.2 / `flow/token.lua`:
--- handlers MAY echo `_flow_token` / `_flow_slot` in their result;
--- verify is fail-open when echo is absent.
---@param spec { slot: flow.ir.Expr, ref: string, in_: flow.ir.Expr?, out: string, bound: boolean?, on_mismatch: flow.ir.Node? }
---@return flow.ir.Node.wrap_step
function M.wrap_step(spec)
    return {
        kind        = "wrap_step",
        slot        = spec.slot,
        ref         = spec.ref,
        in_         = spec.in_,
        out         = spec.out,
        bound       = spec.bound,
        on_mismatch = spec.on_mismatch,
    }
end

--- `switch` Node: n-way branch on `on`. `cases` is an ordered list of
--- `{ match = Expr, body = Node }` entries; the first whose `match`
--- evaluates to a value equal (Lua `==`) to `on` wins. `else_` runs when
--- no case matches (optional).
---@param spec { on: flow.ir.Expr, cases: { match: flow.ir.Expr, body: flow.ir.Node }[], else_: flow.ir.Node? }
---@return flow.ir.Node.switch
function M.switch(spec)
    return {
        kind  = "switch",
        on    = spec.on,
        cases = spec.cases,
        else_ = spec.else_,
    }
end

--- `try` Node: runs `body` under pcall; on a non-sentinel raise, optionally
--- writes the error message to `ctx[err_at]` and runs `catch`. Does NOT
--- swallow `return_early` — that sentinel unwinds to the enclosing
--- `flow.ir.exec` frame.
---@param spec { body: flow.ir.Node, catch: flow.ir.Node, err_at: string? }
---@return flow.ir.Node.try
M["try"] = function(spec)
    return { kind = "try", body = spec.body, catch = spec.catch, err_at = spec.err_at }
end

--- `return_early` Node: optionally writes `value` (Expr) to `ctx[out]`,
--- then unwinds to the enclosing `flow.ir.exec` frame. `try` does NOT
--- catch this sentinel.
---@param spec { out: string?, value: flow.ir.Expr? }
---@return flow.ir.Node.return_early
function M.return_early(spec)
    spec = spec or {}
    return { kind = "return_early", out = spec.out, value = spec.value }
end

--- `map` Node: iterate over an array, run `body` per item against the shared
--- ctx (with the item bound to `bind`), and collect the value at `collect`
--- (a "$." + ctx path) into `out` as the i-th element.
---@param spec { in_: flow.ir.Expr, bind: string, body: flow.ir.Node, collect: string, out: string }
---@return flow.ir.Node.map
function M.map(spec)
    return {
        kind    = "map",
        in_     = spec.in_,
        bind    = spec.bind,
        body    = spec.body,
        collect = spec.collect,
        out     = spec.out,
    }
end

--- `reduce` Node: iterate over an array, threading an accumulator at ctx[acc]
--- through each body run (body is expected to update ctx[acc]). The initial
--- acc value is `init` (Expr). Final acc is written to `out`.
---@param spec { in_: flow.ir.Expr, init: flow.ir.Expr, acc: string, bind: string, body: flow.ir.Node, out: string }
---@return flow.ir.Node.reduce
function M.reduce(spec)
    return {
        kind = "reduce",
        in_  = spec.in_,
        init = spec.init,
        acc  = spec.acc,
        bind = spec.bind,
        body = spec.body,
        out  = spec.out,
    }
end

--- `fail` Node: unconditionally raises. `message` is an Expr that must
--- eval to a string.
---@param spec { message: flow.ir.Expr }
---@return flow.ir.Node.fail
M["fail"] = function(spec)
    return { kind = "fail", message = spec.message }
end

--- `assert` Node: raises with `message` (Expr → string) iff `cond` (Expr)
--- evaluates to a falsy value. Otherwise no-op.
---@param spec { cond: flow.ir.Expr, message: flow.ir.Expr }
---@return flow.ir.Node.assert
M["assert"] = function(spec)
    return { kind = "assert", cond = spec.cond, message = spec.message }
end

--- `once` Node: resume-guarded body. `flag` is a ctx write path; the body
--- runs iff `$.<flag>` is currently falsy, then `flag` is set to `true`.
--- Combine with FlowState (load → exec → save) for cross-session resume.
---@param spec { flag: string, body: flow.ir.Node }
---@return flow.ir.Node.once
function M.once(spec)
    return { kind = "once", flag = spec.flag, body = spec.body }
end

return M
