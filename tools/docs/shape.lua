--- tools.docs.shape — alc_shapes DSL → PkgInfo.shape converter.
---
--- Input: a Lua table produced by `alc_shapes.t` combinators
--- (i.e. the value of `M.meta.input_shape`). The DSL internal
--- structure is documented in `alc_shapes/t.lua`:
---   { kind = "prim",         prim = <name> }
---   { kind = "any" }
---   { kind = "shape",        fields = {...}, open = <bool> }
---   { kind = "array_of",     elem = <schema> }
---   { kind = "map_of",       key = <schema>, val = <schema> }
---   { kind = "one_of",       values = {...} }
---   { kind = "discriminated",tag = <string>, variants = {...} }
---   { kind = "optional",     inner = <schema> }
---   { kind = "described",    inner = <schema>, doc = <string> }
---
--- Output: a PkgInfo-shaped Shape / TypeExpr table (see pkg_info.lua).
--- `:is_optional()` / `:describe()` wrappers are unwrapped and their
--- metadata is attached to the enclosing Field entry.

local PI = require("tools.docs.pkg_info")

local M = {}

local function is_schema(v)
    return type(v) == "table" and v.kind ~= nil
end

--- Peel optional / described wrappers off and collect metadata.
---
--- Returns: inner_schema, optional, doc
local function peel(schema)
    local optional = false
    local doc = ""
    local cur = schema
    -- Wrappers may nest in either order: described(optional(x))
    -- or optional(described(x)). Peel both.
    while true do
        if cur.kind == "optional" then
            optional = true
            cur = cur.inner
        elseif cur.kind == "described" then
            if cur.doc ~= nil and cur.doc ~= "" then
                doc = cur.doc
            end
            cur = cur.inner
        else
            break
        end
    end
    return cur, optional, doc
end

--- Convert a peeled alc_shapes schema to a TypeExpr.
--- (peeled: no top-level optional/described wrappers)
local function type_expr_of(schema)
    local k = schema.kind
    if k == "prim" then
        return PI.primitive(schema.prim)
    elseif k == "any" then
        return PI.primitive("any")
    elseif k == "array_of" then
        local elem_peeled = peel(schema.elem)
        return PI.array_of(type_expr_of(elem_peeled))
    elseif k == "map_of" then
        local key_peeled = peel(schema.key)
        local val_peeled = peel(schema.val)
        return PI.map_of(type_expr_of(key_peeled), type_expr_of(val_peeled))
    elseif k == "one_of" then
        return PI.one_of(schema.values)
    elseif k == "shape" then
        return PI.shape_ref(M.convert_shape(schema))
    elseif k == "discriminated" then
        local variants = {}
        for name, variant_schema in pairs(schema.variants) do
            variants[name] = M.convert_shape(variant_schema)
        end
        return PI.discriminated(schema.tag, variants)
    else
        error(string.format(
            "tools.docs.shape: unknown schema kind '%s'", tostring(k)), 2)
    end
end

--- Convert a top-level alc_shapes T.shape(...) to a PkgInfo Shape.
function M.convert_shape(schema)
    if not is_schema(schema) then
        error("tools.docs.shape: convert_shape expects a schema", 2)
    end
    if schema.kind ~= "shape" then
        error(string.format(
            "tools.docs.shape: convert_shape expects kind='shape', got '%s'",
            tostring(schema.kind)), 2)
    end
    local fields = {}
    -- Preserve a stable order by sorting field names.
    local names = {}
    for name, _ in pairs(schema.fields) do
        names[#names + 1] = name
    end
    table.sort(names)
    for i = 1, #names do
        local name = names[i]
        local peeled, optional, doc = peel(schema.fields[name])
        fields[i] = PI.make_field(name, type_expr_of(peeled), optional, doc)
    end
    return PI.make_shape(fields, schema.open and true or false)
end

--- Convert any alc_shapes schema to a PkgInfo TypeExpr.
---
--- Unlike `convert_shape` (which only accepts `kind="shape"`), this
--- accepts any combinator kind — including wrapped forms (`optional` /
--- `described`) which are peeled at the top level. Used by
--- `extract.build_pkg_info` for `meta.result_shape` when the author
--- passes an alc_shapes schema instead of a string label.
---
--- Errors if `schema` is not a recognised combinator.
function M.convert_type_expr(schema)
    if not is_schema(schema) then
        error("tools.docs.shape: convert_type_expr expects a schema", 2)
    end
    local peeled = peel(schema)
    return type_expr_of(peeled)
end

M._internal = {
    is_schema    = is_schema,
    peel         = peel,
    type_expr_of = type_expr_of,
}

return M
