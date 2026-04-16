--- alc_shapes.t — DSL combinators and schema internal structure.
---
--- Schemas are plain Lua tables with a `kind` field. All internal
--- fields (`kind`, `prim`, `inner`, `elem`, `values`, `fields`, `open`,
--- `doc`) are readable via `rawget` without traversing metatables.
--- Metatables carry only combinator sugar (`:is_optional()`,
--- `:describe(doc)`). Combinators return new tables — schemas are
--- never mutated in place.
---
--- See workspace/tasks/shape-convention/design.md §Shape の内部構造.

local M = {}

local combinators = {}
local schema_mt = { __index = combinators }

local function is_schema(v)
    return type(v) == "table" and rawget(v, "kind") ~= nil
end

function combinators:is_optional()
    return setmetatable({ kind = "optional", inner = self }, schema_mt)
end

function combinators:describe(doc)
    if type(doc) ~= "string" then
        error("alc_shapes.t: describe expects string doc", 2)
    end
    return setmetatable({ kind = "described", inner = self, doc = doc }, schema_mt)
end

M.string  = setmetatable({ kind = "prim", prim = "string" },  schema_mt)
M.number  = setmetatable({ kind = "prim", prim = "number" },  schema_mt)
M.boolean = setmetatable({ kind = "prim", prim = "boolean" }, schema_mt)
M.table   = setmetatable({ kind = "prim", prim = "table" },   schema_mt)
M.any     = setmetatable({ kind = "any" },                    schema_mt)

function M.shape(fields, opts)
    if type(fields) ~= "table" then
        error("alc_shapes.t: shape expects fields table as first argument", 2)
    end
    for name, sub in pairs(fields) do
        if type(name) ~= "string" then
            error("alc_shapes.t: shape field name must be string, got " .. type(name), 2)
        end
        if not is_schema(sub) then
            error(string.format(
                "alc_shapes.t: shape field '%s' must be a schema (table with kind)", name), 2)
        end
    end
    local open
    if opts == nil then
        open = true
    else
        if type(opts) ~= "table" then
            error("alc_shapes.t: shape expects opts table as second argument", 2)
        end
        if opts.open == nil then
            open = true
        else
            open = opts.open and true or false
        end
    end
    return setmetatable({ kind = "shape", fields = fields, open = open }, schema_mt)
end

function M.array_of(elem)
    if not is_schema(elem) then
        error("alc_shapes.t: array_of expects a schema as argument", 2)
    end
    return setmetatable({ kind = "array_of", elem = elem }, schema_mt)
end

function M.one_of(values)
    if type(values) ~= "table" then
        error("alc_shapes.t: one_of expects a values table as argument", 2)
    end
    local n = 0
    for _ in pairs(values) do n = n + 1 end
    if n == 0 then
        error("alc_shapes.t: one_of expects at least one value", 2)
    end
    for i = 1, n do
        local v = values[i]
        if v == nil then
            error("alc_shapes.t: one_of expects a 1-based dense array of values", 2)
        end
        local t = type(v)
        if t ~= "string" and t ~= "number" and t ~= "boolean" then
            error(string.format(
                "alc_shapes.t: one_of values must be string/number/boolean, got %s at index %d",
                t, i), 2)
        end
    end
    local copy = {}
    for i = 1, n do copy[i] = values[i] end
    return setmetatable({ kind = "one_of", values = copy }, schema_mt)
end

function M.discriminated(tag, variants)
    if type(tag) ~= "string" or tag == "" then
        error("alc_shapes.t: discriminated expects non-empty string tag", 2)
    end
    if type(variants) ~= "table" then
        error("alc_shapes.t: discriminated expects variants table", 2)
    end
    local count = 0
    for k, v in pairs(variants) do
        if type(k) ~= "string" then
            error("alc_shapes.t: discriminated variant key must be string, got " .. type(k), 2)
        end
        if not is_schema(v) or rawget(v, "kind") ~= "shape" then
            error(string.format(
                "alc_shapes.t: discriminated variant '%s' must be a shape schema", k), 2)
        end
        count = count + 1
    end
    if count == 0 then
        error("alc_shapes.t: discriminated expects at least one variant", 2)
    end
    return setmetatable({ kind = "discriminated", tag = tag, variants = variants }, schema_mt)
end

function M.map_of(key, val)
    if not is_schema(key) then
        error("alc_shapes.t: map_of expects a schema as key argument", 2)
    end
    if not is_schema(val) then
        error("alc_shapes.t: map_of expects a schema as val argument", 2)
    end
    return setmetatable({ kind = "map_of", key = key, val = val }, schema_mt)
end

M._internal = {
    schema_mt   = schema_mt,
    combinators = combinators,
    is_schema   = is_schema,
}

return M
