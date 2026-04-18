---@meta
--- algocline-bundled-packages — LuaCats type definitions
---
--- This file defines the module-level interface contract shared by all
--- packages in this collection. It complements (not duplicates) the core
--- runtime type definitions shipped by algocline itself:
---
---   ~/.algocline/types/alc.d.lua   — alc.* global (StdLib)
---   (this file)                    — package module convention
---
--- algocline's alc.d.lua types the runtime global `alc` that Lua code
--- calls at execution time. This file types the *module interface*:
--- the table returned by `require("pkg_name")` and the `ctx` table
--- threaded through `M.run(ctx)`.
---
--- Because packages are designed to be chained (the output ctx of one
--- becomes the input of the next), AlcCtx uses an open table shape
--- (`[string]: any`) so that fields added by upstream packages pass
--- through without type errors.
---
--- Setup (.luarc.json):
---   { "workspace": { "library": ["types", "~/.algocline/types"] } }

-- ── ctx: the table threaded through M.run() ──

---@class AlcCtx
---@field task string The problem / question to process
---@field result? any Package output (set by M.run)
---@field [string] any Open extension — upstream fields pass through

-- ── M.meta: package identity ──

---@class AlcMeta
---@field name string Package identifier (e.g. "cot", "mcts")
---@field version string SemVer string (e.g. "0.1.0")
---@field description string One-line summary
---@field category string Category tag (e.g. "reasoning", "exploration")

-- ── M.spec: package I/O contract (bundled packages only) ──
--
-- Opaque packages (community / experimental) omit M.spec entirely;
-- spec_resolver treats them as kind = "opaque" and skips type checks.

---@class AlcSpecEntry
---@field input? string|table Input ctx shape — registry name (string) or inline T.shape
---@field result? string|table Result shape — registry name (string) or inline T.shape
---@field events? any Reserved for future streaming use

---@class AlcSpecCompose
---@field passthrough? string|string[] This entry returns the same shape it consumes
---@field transforms? table[] Declared { from, to } shape transformations
---@field requires? string[] Shape names expected to already exist in ctx

---@class AlcSpec
---@field entries table<string, AlcSpecEntry> Entry points; `run` is the primary by convention
---@field compose? AlcSpecCompose Composability hints for routing / recipe layers
---@field exports? string[] Shape names this pkg registers into the shape registry

