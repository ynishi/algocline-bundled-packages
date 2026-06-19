---@module 'flow.ir'
-- Flow IR (data Def) + interpreter (Exec).
--
-- A minimum-primitive substrate that lets a pipeline be authored as a
-- single Lua table (Def), validated structurally (Compile), and walked
-- by a host-neutral interpreter (Exec). The Def is the IR — `compile`
-- returns the same table on success; no separate transformation.
--
-- MVP surface:
--   Nodes: step / seq / branch          (3 of 6)
--   Exprs: path / lit / eq              (3 of 5)
--
-- See `flow/doc/ir.md` for the full Def→Compile→Exec contract.
--
-- Reference: classic Def→Compile→Exec pipeline over a Schema-as-Data
-- IR (after Malli; via alc_shapes.t discriminated/shape).
-- Structural control completeness follows Böhm–Jacopini (1966).

local schema      = require("flow.ir.schema")
local compile_mod = require("flow.ir.compile")
local interp      = require("flow.ir.interpreter")

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

return M
