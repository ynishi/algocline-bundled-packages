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

-- ── M.meta: package metadata table ──

---@class AlcMeta
---@field name string Package identifier (e.g. "cot", "mcts")
---@field version string SemVer string (e.g. "0.1.0")
---@field description string One-line summary
---@field category string Category tag (e.g. "reasoning", "exploration")
---@field result_shape? string|table Registry-name lookup key (string) or inline `T.shape(...)` schema

