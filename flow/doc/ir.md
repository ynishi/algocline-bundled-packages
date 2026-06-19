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
| Control Node (L3) | `seq` / `branch` / `let` / `loop` / `call` | pure structured control |
| Expr (L3) | `path` / `lit` / `eq` / `and` / `not` / `lt` | pure value |

The interpreter treats `step` as the **only** host-escape Node; every
other Node and every Expr is host-neutral.

### Node shapes

```lua
{ kind = "step",   ref = "<handler>", in_ = <Expr>?, out = "ctx.<path>" }
{ kind = "seq",    children = { <Node>, ... } }
{ kind = "branch", cond = <Expr>, then_ = <Node>, else_ = <Node> }
{ kind = "let",    at = "ctx.<path>", value = <Expr> }
{ kind = "loop",   cond = <Expr>, body = <Node>,
                   max = <int>=1>, counter = "ctx.<path>" }
{ kind = "call",   flow = "<name>", args = { <k> = <Expr>, ... },
                   out = "ctx.<path>" }
```

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

### Expr shapes

```lua
{ op = "path", at = "$.ctx.<path>" }   -- read ctx
{ op = "lit",  value = <any> }         -- literal
{ op = "eq",   lhs = <Expr>, rhs = <Expr> }
{ op = "and",  args = { <Expr>, <Expr>, ... } }  -- length >= 2, short-circuit
{ op = "not",  arg = <Expr> }                    -- truthiness inversion
{ op = "lt",   lhs = <Expr>, rhs = <Expr> }      -- numeric or lexicographic
```

`and` / `not` / `lt` all return Lua booleans. `or` is derivable via
De Morgan (`not(and(not(a), not(b)))`); kept out of the budget. `eq`
follows Lua `==` semantics (reference equality on tables).

### State model

`ctx` is the only mutable state; `step.out` is the only write path.
Reads are absolute and rooted at `$.ctx.*`; writes are relative and
written as `ctx.*`. Persistence and resume are trivial: snapshot
`ctx`, replay from the IR position.

## Public API

```lua
local ir = require("flow").ir

ir.compile(def)                  -- flow.ir.Node → flow.ir.Node | nil, reason
ir.exec(compiled, ctx, opts)     -- mutates + returns ctx
                                 -- opts.dispatch(ref, input) -> result, err?

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
