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
        { kind = "step", agent = "a", out = "ctx.x" },
        { kind = "step", agent = "b", out = "ctx.y" },
        {
            kind  = "branch",
            cond  = {
                op  = "eq",
                lhs = { op = "path", at = "$.ctx.y.status" },
                rhs = { op = "lit",  value = "ok" },
            },
            then_ = { kind = "step", agent = "c", out = "ctx.done" },
            else_ = { kind = "step", agent = "d", out = "ctx.retry" },
        },
    },
})
assert(compiled, "compile failed")

local ctx = ir.exec(compiled, {}, {
    dispatch = function(agent, _input)
        return { agent = agent, status = "ok" }  -- host wires its own dispatcher
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
- **Host neutral** — the interpreter knows nothing about agents. It
  only walks Nodes / Exprs and calls `opts.dispatch(agent, input)`.

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
                │             │  calls opts.dispatch(agent, input)
                └─────────────┘
                       │
                       ▼
                     ctx'
```

Compile is a separate stage so the IR can be inspected and rejected
before any side effect runs. The Def *is* the IR — `compile` returns
the same table on success; no separate transformation step.

## Surface (MVP)

| Layer | Kinds |
|---|---|
| Node | `step` / `seq` / `branch` |
| Expr | `path` / `lit` / `eq` |

### Node shapes

```lua
{ kind = "step",   agent = "<name>", in_ = <Expr>?, out = "ctx.<path>" }
{ kind = "seq",    children = { <Node>, ... } }
{ kind = "branch", cond = <Expr>, then_ = <Node>, else_ = <Node> }
```

### Expr shapes

```lua
{ op = "path", at = "$.ctx.<path>" }   -- read ctx
{ op = "lit",  value = <any> }         -- literal
{ op = "eq",   lhs = <Expr>, rhs = <Expr> }
```

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
                                 -- opts.dispatch(agent, input) -> result, err?

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
