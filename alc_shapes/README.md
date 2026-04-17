# alc_shapes — Result Shape Convention

Lightweight schema definitions for `ctx.result` validation across algocline packages. Ensures "promised keys exist" at package boundaries without type coercion or excess-field rejection.

```lua
local S = require("alc_shapes")
local ok, reason = S.check(value, S.voted)     -- silent check
local x = S.assert(value, "voted", "caller")   -- loud fail
```

## Core concept — Schema-as-Data

alc_shapes is modelled after **Malli (Clojure)**'s [TypeSchemaAsData][malli] doctrine:

> "Schemas are just data. They can be serialized, persisted, transformed, and inspected with the same tools you use for any other data structure. There is no separate AST, no opaque compiled form — the schema *is* the representation."

[malli]: https://github.com/metosin/malli#schema-as-data

This shapes three invariants that the entire system depends on.

### 1. Single AST (no parallel representations)

There is exactly **one** schema representation: the kind-tagged plain table. Downstream consumers (validator, reflector, codegen, documentation projector) read `rawget(schema, "kind")` and dispatch; they never normalise, denormalise, or convert into a second AST.

Parallel representations (e.g. "TypeExpr for docs, Schema for runtime") are explicitly prohibited. If a consumer needs a derived form, it must be a pure projection of the schema — never a mirrored structure that can drift.

### 2. Persistable by construction

Because schemas are plain tables with all state in `rawget`-readable fields, they are **serialisable without loss**: JSON-encode → decode → still fully functional against `check` / `fields` / `walk`. Metatables carry combinator sugar only (`:is_optional()`, `:describe(doc)`); stripping the metatable must never change validation behaviour.

This is why combinators return new tables (never mutate) and why reflection uses `rawget` exclusively.

### 3. Reflectable

`kind` is the universal discriminator. `reflect.fields` and `reflect.walk` traverse by reading `kind` and the kind-specific field names (`inner`, `elem`, `fields`, `variants`, `key`, `val`, `values`). Every consumer in the system uses the same dispatch.

## Design principles

- **Layer contract (Runtime vs Entity)**: `T.shape` defaults to `open = true`. Runtime shapes (`ctx.result` etc.) stay open to preserve the pass-through culture — packages chain outputs through ctx and may attach trace / metrics / debug keys without invalidating downstream consumers. Entity shapes (boundary contracts, e.g. `tools/docs/entity_schemas.lua`) opt into strict mode (`open = false`) because their fields *are* the contract itself, and extra keys signal drift. The asymmetric default matches the layer semantics: Runtime = pass-through, Entity = closed.
- **Existence checking**: validates that declared keys exist with the right primitive type. Does not normalize values or enforce strict typing on nested table contents beyond what the schema declares.
- **SSoT**: `alc_shapes/init.lua` is the single source of truth. `types/alc_shapes.d.lua` is auto-generated via `just gen-shapes` — hand-editing is prohibited.

## DSL combinators

Schemas are plain Lua tables with a `kind` tag. The DSL produces them with combinator sugar.

```lua
local T = require("alc_shapes.t")

-- Primitives
T.string              -- { kind = "prim", prim = "string" }
T.number              -- { kind = "prim", prim = "number" }
T.boolean             -- { kind = "prim", prim = "boolean" }
T.table               -- { kind = "prim", prim = "table" }
T.any                 -- { kind = "any" }

-- Composites
T.shape(fields, opts)                -- named key set (opts.open defaults to true)
T.array_of(elem)                     -- homogeneous array
T.one_of(values)                     -- literal enum (string/number/boolean)
T.map_of(key, val)                   -- key/value typed map
T.discriminated(tag, variants)       -- tag-dispatched union
T.ref(name)                          -- named reference into alc_shapes registry

-- Wrappers (return new schema, never mutate)
schema:is_optional()                 -- nil-permitted wrapper
schema:describe(doc)                 -- doc annotation (transparent to check)
```

### Example

```lua
local voted = T.shape({
    answer      = T.string,
    vote_counts = T.map_of(T.string, T.number),
    votes       = T.array_of(T.string),
    stages      = T.array_of(T.discriminated("name", {
        sc        = T.shape({ name = T.one_of({"sc"}), panel_size = T.number }),
        calibrate = T.shape({ name = T.one_of({"calibrate"}), confidence = T.number }),
    })),
    answer_norm = T.string:is_optional():describe("Normalized vote key"),
}, { open = true })
```

## Schema internal structure

Every schema node is a plain table with `kind` readable via `rawget`. Metatables carry combinator sugar only — reflection never depends on `__index`.

| kind | Fields | Description |
|---|---|---|
| `prim` | `prim` | Lua type name: `"string"`, `"number"`, `"boolean"`, `"table"` |
| `any` | — | Accepts anything including nil |
| `optional` | `inner` | Wraps inner schema; nil passes |
| `described` | `inner`, `doc` | Doc annotation; transparent to check |
| `array_of` | `elem` | Homogeneous array of elem schema |
| `one_of` | `values` | Literal enum (dense 1-based array) |
| `shape` | `fields`, `open` | Named key set; `open=true` allows extra keys |
| `map_of` | `key`, `val` | Key/value typed map (like tableshape `types.map_of` / Zod `z.record()`) |
| `discriminated` | `tag`, `variants` | Tag-dispatched union; `variants` is `{ [tag_value] = shape_schema }` |
| `ref` | `name` | Named reference into the `alc_shapes` registry (Malli `[:ref :name]` analogue). Resolved lazily so registry cycles and forward references work. |

## Validator API

```lua
local S = require("alc_shapes")

-- Silent check (never throws)
local ok, reason = S.check(value, schema)

-- Loud fail (returns value on pass for chaining)
local v = S.assert(value, schema_or_name, ctx_hint?)

-- Dev-mode only assert (no-op when ALC_SHAPE_CHECK != "1")
local v = S.assert_dev(value, schema_or_name, ctx_hint?)

-- Dev mode query
local active = S.is_dev_mode()
```

`assert` accepts both schema objects and string names:

```lua
S.assert(r, S.voted, "sc.run")    -- direct schema reference
S.assert(r, "voted", "sc.run")    -- name lookup in alc_shapes registry
S.assert(r, "any")                 -- no-op pass (explicit)
S.assert(r, "typo")               -- error: unknown shape
S.assert(r, nil)                   -- error: schema_or_name must not be nil
```

`assert` means "I intended to validate"; passing `nil` is a typo signal
(e.g. `S.assert(r, S.votd, ...)` where the typo'd `S.votd` resolves to
`nil`) and loud-fails. Use `S.check(v, nil)` if silent pass is
intentional (projection-side guard pattern).

### Error messages

Path format is JSONPath-ish with 1-based array indices:

```
shape violation at $.stages[2].name: expected string, got nil (ctx: recipe_safe_panel)
shape violation at $[key=42]: expected string, got number (ctx: vote_counts)
shape violation at $.mode: expected one of ["a", "b"], got "c"
shape violation at $.stages: discriminant 'name' = "unknown" not in ["calibrate", "sc"]
```

## Reflection API

```lua
-- Enumerate direct fields of a shape (sorted by name)
local entries = S.fields(schema)
-- entries[i] = { name, type, optional, doc? }

-- DFS walk of the schema tree
S.walk(schema, function(node) ... end)
```

`fields` unwraps `optional`/`described` wrappers and reports the inner type. `walk` visits every node depth-first in sorted order.

## LuaCATS codegen

`types/alc_shapes.d.lua` is generated from `alc_shapes/init.lua`:

```bash
just gen-shapes      # regenerate
just verify-shapes   # CI drift check (diff against committed file)
```

### Type mappings

| Schema kind | LuaCATS output |
|---|---|
| `prim(string)` | `string` |
| `prim(number)` | `number` |
| `prim(boolean)` | `boolean` |
| `prim(table)` | `table` |
| `any` | `any` |
| `array_of(T)` | `T[]` |
| `array_of(optional(T))` | `(T\|nil)[]` |
| `shape` (inline) | `table` |
| `one_of({"a","b"})` | `"a"\|"b"` |
| `map_of(K, V)` | `table<K, V>` |
| `discriminated` | `table` |
| `ref(name)` | `<class_prefix>PascalCase(name)` (e.g. `ref("voted")` → `AlcResultVoted`) |
| `optional(T)` | field name gets `?` suffix |
| `described(T, doc)` | doc appended as `@...` suffix |

## Producer usage

Declare `result_shape` in package meta, optionally add `assert_dev` for self-defense:

```lua
local S = require("alc_shapes")

local M = {}
M.meta = {
    name = "sc",
    version = "0.2.0",
    description = "...",
    category = "aggregation",
    result_shape = "voted",
}

function M.run(ctx)
    -- ... build ctx.result ...
    S.assert_dev(ctx.result, "voted", "sc.run")
    return ctx
end

return M
```

## Consumer usage

Assert at package boundaries:

```lua
local S = require("alc_shapes")
local sc = require("sc")
local sc_result = sc.run({ task = task, n = 7 })
S.assert(sc_result.result, S.voted, "recipe_safe_panel input")
```

## Registered shapes

| Name | Package(s) | Key fields |
|---|---|---|
| `voted` | sc | consensus, answer, paths, votes, vote_counts, n_sampled |
| `paneled` | panel | arguments, synthesis |
| `assessed` | calibrate.assess | answer, confidence |
| `calibrated` | calibrate | answer, confidence, escalated, strategy, fallback_detail |
| `tournament` | rank | best, best_index, total_wins, candidates, matches |
| `listwise_ranked` | listwise_rank | ranked, top_k, killed, best, n_candidates |
| `pairwise_ranked` | pairwise_rank | ranked, top_k, killed, best, method, score_semantics |
| `funnel_ranked` | recipe_ranking_funnel | ranking, best, funnel_bypassed, stages (discriminated), warnings |
| `safe_paneled` | recipe_safe_panel | answer, confidence, vote_counts (map_of), stages (discriminated), aborted |

## File layout

```
alc_shapes/
  init.lua        # SSoT — shape dictionary + public API re-export
  t.lua           # DSL combinators
  check.lua       # Validator (check / assert / assert_dev)
  reflect.lua     # Reflection (fields / walk)
  luacats.lua     # LuaCATS codegen
  README.md       # This file

types/
  alc_shapes.d.lua  # Auto-generated LuaCATS (hand-edit prohibited)

scripts/
  gen_shapes_luacats.lua  # Codegen runner (just gen-shapes)

tests/
  test_alc_shapes_t.lua           # DSL combinator tests
  test_alc_shapes_check.lua       # Validator tests
  test_alc_shapes_luacats.lua     # Codegen tests
  test_alc_shapes_reflect.lua     # Reflection tests
  test_shapes_conformance.lua     # Cross-package conformance tests
```
