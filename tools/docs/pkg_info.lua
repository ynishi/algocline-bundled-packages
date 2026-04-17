--- tools.docs.pkg_info — Core Entity schema.
---
--- Data-only module. Declares the shape of PkgInfo / Shape / TypeExpr
--- as Lua tables and exposes pure constructors. All downstream
--- modules (extract / shape / projections / lint) produce or consume
--- this schema.
---
--- PkgInfo layout
---
---   {
---     identity  = { name, version, category, source_path },
---     narrative = {
---       title   = <string>,      -- docstring 1st line
---       summary = <string>,      -- abstract paragraph (joined)
---       sections = { Section, ... },
---     },
---     shape = {
---       input  = Shape | nil,    -- nil iff no input_shape declared
---       result = <string> | nil,
---     },
---   }
---
---   Section = { level = 2|3, heading = <string>,
---               anchor = <string>, body_md = <string> }
---
---   Shape   = { fields = { Field, ... }, open = <boolean> }
---   Field   = { name, type = TypeExpr, optional = <boolean>,
---               doc = <string> }
---
---   TypeExpr one of:
---     { kind = "primitive", name = "string"|"number"|"boolean"|"table"|"any" }
---     { kind = "array_of",  of = TypeExpr }
---     { kind = "map_of",    key = TypeExpr, val = TypeExpr }
---     { kind = "one_of",    values = { <lit>, ... } }
---     { kind = "shape",     shape = Shape }         -- nested T.shape
---     { kind = "discriminated", tag = <string>,
---                              variants = { [name] = Shape } }
---     { kind = "label",     name = <string> }       -- opaque result-type name
---                                                   -- (e.g. "paneled.Result")

local M = {}

function M.primitive(name)
    return { kind = "primitive", name = name }
end

function M.array_of(of)
    return { kind = "array_of", of = of }
end

function M.map_of(key, val)
    return { kind = "map_of", key = key, val = val }
end

function M.one_of(values)
    local copy = {}
    for i = 1, #values do copy[i] = values[i] end
    return { kind = "one_of", values = copy }
end

function M.shape_ref(shape)
    return { kind = "shape", shape = shape }
end

function M.discriminated(tag, variants)
    return { kind = "discriminated", tag = tag, variants = variants }
end

function M.label(name)
    return { kind = "label", name = name }
end

function M.make_shape(fields, open)
    return { fields = fields or {}, open = open and true or false }
end

function M.make_field(name, type_expr, optional, doc)
    return {
        name     = name,
        type     = type_expr,
        optional = optional and true or false,
        doc      = doc or "",
    }
end

function M.make_section(level, heading, anchor, body_md)
    return {
        level   = level,
        heading = heading,
        anchor  = anchor,
        body_md = body_md,
    }
end

function M.make_pkg_info(identity, narrative, shape)
    return {
        identity  = identity,
        narrative = narrative,
        shape     = shape,
    }
end

return M
