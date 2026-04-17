--- tools.docs.entity_schemas — Entity registry for the docs pipeline.
---
--- Plain `{name → schema}` data. No closures, no opaque state.
--- Pass via `S.check(v, EntitySchemas.PkgInfo, { registry = EntitySchemas })`.
---
--- Entity 境界は strict (open=false)。未知 field は契約違反として
--- loud-fail する。このポリシーは Runtime result shape (alc_shapes の
--- pass-through culture) とは意図的に反対。
---
--- Single source of truth: pipeline-spec.md §3 (Core Entity: PkgInfo)
---
--- Design notes:
---   * Schema-as-Data 主義に従い、このモジュールは closure を保持しない。
---   * T.ref("Identity") 等の内部参照は `check` 側で registry (このモジュール
---     自身) を辿ることで解決される。
---   * shape.input / shape.result は alc_shapes schema data を受ける。
---     完全 meta-schema は記述せず、"kind field を持つ table" という
---     structural invariant のみを要求する (`AlcSchema` を open=true で定義)。

local T = require("alc_shapes.t")

local M = {}

-- Leaf: alc_shapes schema data.
-- kind field の存在だけを必須にし、残りの structural body は alc_shapes
-- t.lua 側の invariant に委ねる。open=true により他フィールド (prim/elem/
-- fields/variants 等) はそのまま通す。
local AlcSchema = T.shape({
    kind = T.string,
}, { open = true })

M.Identity = T.shape({
    name        = T.string,
    version     = T.string,
    category    = T.string,
    description = T.string,
    source_path = T.string,
}, { open = false })

M.Section = T.shape({
    level   = T.one_of({ 2, 3 }),
    heading = T.string,
    anchor  = T.string,
    body_md = T.string,
}, { open = false })

M.Narrative = T.shape({
    title    = T.string,
    summary  = T.string,
    sections = T.array_of(T.ref("Section")),
}, { open = false })

M.Shape = T.shape({
    input  = AlcSchema:is_optional(),
    result = AlcSchema:is_optional(),
}, { open = false })

M.PkgInfo = T.shape({
    identity  = T.ref("Identity"),
    narrative = T.ref("Narrative"),
    shape     = T.ref("Shape"),
}, { open = false })

return M
