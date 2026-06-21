# flow.ir

Schema-as-Data Node + Expr IR with a Def → Compile → Exec pipeline.
Minimum-primitive substrate for authoring a pipeline as a single
Lua table.

```lua
local flow = require("flow")
local ir   = flow.ir

local compiled = ir.compile({
    kind = "seq",
    children = {
        { kind = "step", ref = "a", out = "ctx.x" },
        { kind = "step", ref = "b", out = "ctx.y" },
        {
            kind  = "branch",
            cond  = {
                op  = "eq",
                lhs = { op = "path", at = "$.ctx.y.status" },
                rhs = { op = "lit",  value = "ok" },
            },
            then_ = { kind = "step", ref = "c", out = "ctx.done" },
            else_ = { kind = "step", ref = "d", out = "ctx.retry" },
        },
    },
})
assert(compiled, "compile failed")

local ctx = ir.exec(compiled, {}, {
    dispatch = function(ref, _input)
        return { ref = ref, status = "ok" }  -- host wires its own dispatcher
    end,
})
```

## Why a data IR

The Def layer is a plain Lua table:

- **Schema-as-Data** — the flow is a value, not a closure graph. It
  can be inspected, serialised, persisted, walked, codegened from.
  Same convention `alc_shapes` and `lshape` use; the doctrine is
  [Malli](https://github.com/metosin/malli)'s.
- **Static validation** — typos in `kind` / `op` and ill-formed nodes
  fail at compile, not at exec. `T.discriminated` with
  `open = false` (belt-and-suspenders, `alc_shapes.t §C4`) makes
  unknown tags a compile error.
- **Host neutral** — the interpreter knows nothing about what `step.ref`
  refers to. It walks Nodes / Exprs and calls `opts.dispatch(ref,
  input)`; everything host-specific (agents, LLM calls, functions,
  external services) lives behind that dispatch.

## Def → Compile → Exec

```
                Def (plain Lua table)
                       │
                       ▼
                ┌─────────────┐
                │  compile()  │  alc_shapes validate + recursive walk
                └─────────────┘
                       │
                       ▼
                 compiled IR (identity)
                       │
                       ▼
                ┌─────────────┐
                │   exec()    │  walks Nodes, evaluates Exprs,
                │             │  calls opts.dispatch(ref, input)
                └─────────────┘
                       │
                       ▼
                     ctx'
```

Compile is a separate stage so the IR can be inspected and rejected
before any side effect runs. The Def *is* the IR — `compile` returns
the same table on success; no separate transformation step.

## Surface

| Layer | Kinds | Purity |
|---|---|---|
| Effect Node (L4) | `step` | host call via `opts.dispatch` |
| Control Node (L3) | `seq` / `branch` / `let` / `loop` / `call` / `fanout` | pure structured control |
| Expr (L3) | `path` / `lit` / `eq` / `and` / `or` / `not` / `lt` / `len` | pure value |

The interpreter treats `step` as the **only** host-escape Node; every
other Node and every Expr is host-neutral.

### Node shapes

```lua
{ kind = "step",   ref = "<handler>", in_ = <Expr>?, out = "ctx.<path>",
                   out_schema = <alc_shapes T>? }                -- optional Schema-as-Data dispatcher contract
{ kind = "seq",    children = { <Node>, ... } }
{ kind = "branch", cond = <Expr>, then_ = <Node>, else_ = <Node> }
{ kind = "let",    at = "ctx.<path>", value = <Expr> }
{ kind = "loop",   cond = <Expr>, body = <Node>,
                   max = <int>=1>, counter = "ctx.<path>" }
{ kind = "call",   flow = "<name>", args = { <k> = <Expr>, ... },
                   out = "ctx.<path>" }
{ kind = "fanout", items = <Expr>, bind = "ctx.<path>",
                   body = <Node>, join = "all"|"any",
                   out = "ctx.<path>" }
```

`fanout` evaluates `items` to a Lua array, runs `body` per item
against a branch-local ctx (shallow copy of caller's ctx + `bind`
written to the item). `join = "all"` writes an array of per-branch
final ctx tables to `out`; `join = "any"` runs branches in order
and writes the first non-raising branch's ctx (empty `items` →
`out = {}`; all-fail → raise). Nested fanout sharing the same
`bind` path is a compile error. The MVP interpreter is serial;
`opts.scheduler` is reserved for a future concurrent scheduler.
Note: `any` is order-dependent in serial fallback — flows should
not depend on *which* branch wins, only on the sub-ctx contents.

`branch.else_` is optional — omit it for a no-op when the cond is
falsy. `compile(ir, { refs = {...}, flows = {...} })` enables
eager registry checks for `step.ref` and `call.flow` at compile
time; both default to lazy resolution.

`let` is pure — `value` is evaluated and bound to `ctx[at]` without
any host call. `loop` is while-style: `cond` is evaluated before each
iteration; `counter` is written as 0 before the loop and incremented
to N after the Nth iteration; `max` is a hard upper bound (compile
rejects `max < 1`). Nested loops sharing the same `counter` path are
a compile error. `call` invokes a registered sub-IR (`opts.flows[flow]`)
with a fresh sub-ctx built from `args`, then writes the entire sub-ctx
to `ctx[out]`. Recursion is bounded by `opts.max_call_depth` (default
64). `compile(ir, { flows = {...} })` enables eager validation of
`call.flow` names; otherwise resolution is deferred to exec.

`step.out_schema` (optional) declares the expected dispatcher result
shape as an alc_shapes T value. When present, exec runs
`alc_shapes.check(result, out_schema)` after dispatch and raises on
mismatch — IR Expr downstream may then `path` into the structured ctx
with compile-time guarantees (routing-as-Data). When nil, any result is
accepted (legacy back-compat). `wrap_step.out_schema` follows the same
contract; on the `on_mismatch` path the schema is NOT enforced (the
caller chose to handle the verify-fail result directly).

### Expr shapes

```lua
{ op = "path", at = "$.ctx.<path>" }   -- read ctx
{ op = "lit",  value = <any> }         -- literal
{ op = "eq",   lhs = <Expr>, rhs = <Expr> }
{ op = "and",  args = { <Expr>, <Expr>, ... } }  -- length >= 2, short-circuit
{ op = "or",   args = { <Expr>, <Expr>, ... } }  -- length >= 2, short-circuit
{ op = "not",  arg = <Expr> }                    -- truthiness inversion
{ op = "lt",   lhs = <Expr>, rhs = <Expr> }      -- numeric or lexicographic
{ op = "len",  arg = <Expr> }                    -- Lua `#`: string / array length
{ op = "call_extern", ref = "<key>", args = { <Expr>, ... } }  -- value-shape Hatch
```

`and` / `or` / `not` / `lt` all return Lua booleans (predictable over
Lua's last-value `and`/`or` semantics). `len` returns an integer
(Lua `#`); it works on strings and sequence-style arrays and raises
on values without a length op. `eq` follows Lua `==` semantics
(reference equality on tables).

`call_extern` is the **value-shape Hatch** for the IR — a host-injected
pure function resolved by opaque key through `opts.externs` whitelist.
The registered function MUST be pure (no side effects), no flow control,
no ctx mutation, and return a scalar / table / nil. Use it to keep the
IR Data while delegating value transformations (regex match, json
decode, collection ops) to host helpers without growing the Expr op set
per use case. Control-flow extension (raising, persisting, network IO)
is OUT of scope — use `step` / `wrap_step` for those.

Discipline (slippery slope fence):
- Comparison / logical / structural control / value composition
  (`eq` / `and` / `fold` / `switch` / `concat` / `format`, etc.) stay as
  IR atoms.
- String processing / data conversion / collection ops / domain helpers
  go through `call_extern`.
- `opts.externs` is caller-supplied; flow itself ships no built-in registry.

### State model

`ctx` is the only mutable state. Reads are absolute and rooted at
`$.ctx.*`; writes are relative and written as `ctx.*`. Write paths
appear in: `step.out`, `let.at`, `loop.counter`, `call.out`,
`fanout.bind` (per-branch local), `fanout.out`. Persistence and
resume are trivial: snapshot `ctx`, replay from the IR position.

## Public API

```lua
local ir = require("flow").ir

ir.compile(def, opts?)           -- flow.ir.Node → flow.ir.Node | nil, reason
                                 --   opts.flows   = { name = ... }       -- eager call.flow check
                                 --   opts.refs    = { name = ... }       -- eager step.ref check
                                 --   opts.externs = { name = ... }       -- eager call_extern.ref check
ir.exec(compiled, ctx, opts)     -- mutates + returns ctx
                                 --   opts.dispatch(ref, input) -> result, err?
                                 --   opts.flows   = { name = compiled_sub_ir, ... }
                                 --   opts.externs = { name = pure_fn, ... }  -- required for call_extern
                                 --   opts.max_call_depth = 64
                                 --   opts.scheduler = <reserved>

ir.default_dispatch              -- public helper (raises with reason for any ref)
ir.Node                          -- alc_shapes discriminated schema (Schema-as-Data)
ir.Expr                          -- alc_shapes discriminated schema (Schema-as-Data)
```

## References

- [Böhm–Jacopini, 1966](https://en.wikipedia.org/wiki/Structured_program_theorem) —
  structured-control completeness; basis for the `seq` / `branch`
  control triplet.
- [Malli](https://github.com/metosin/malli) — the data-driven
  Schema-as-Data doctrine.
- `alc_shapes` (bundled, this repo) — Schema-as-Data implementation
  with `T.discriminated` belt-and-suspenders tagging
  (`alc_shapes.t §C4`); the substrate for the IR's static validation.
- `lshape` (bundled, this repo) — extracted Schema-as-Data library;
  the persistability discipline guided this design.
