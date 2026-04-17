--- alc_shapes.luacats — LuaCATS codegen for shape registries.
---
--- class_for(class_name, shape_schema)       -> LuaCATS class text
--- gen(shapes_table, class_prefix?)          -> full d.lua contents
---
--- See workspace/tasks/shape-convention/design.md §型マッピング.

local reflect = require("alc_shapes.reflect")

local M = {}

local function pascal_case(name)
    -- "voted" -> "Voted"; "safe_panel" -> "SafePanel".
    local out = {}
    local start = 1
    while true do
        local us = name:find("[_-]", start)
        local token
        if us then
            token = name:sub(start, us - 1)
            start = us + 1
        else
            token = name:sub(start)
        end
        if #token > 0 then
            out[#out + 1] = token:sub(1, 1):upper() .. token:sub(2)
        end
        if not us then break end
    end
    return table.concat(out)
end

--- Map a schema node to its LuaCATS type string.
--- `named_shapes` is a set of inline-shape references that should render
--- as bare `table` (named shapes are only emitted at the top level).
--- `class_prefix` is threaded through so `ref(name)` resolves to the
--- correct class identifier.
local function type_of(node, class_prefix)
    class_prefix = class_prefix or "AlcResult"
    local kind = rawget(node, "kind")
    if kind == "prim" then
        return node.prim
    elseif kind == "any" then
        return "any"
    elseif kind == "optional" then
        return type_of(rawget(node, "inner"), class_prefix)
    elseif kind == "described" then
        return type_of(rawget(node, "inner"), class_prefix)
    elseif kind == "array_of" then
        -- Preserve inner-optional semantics:
        --   array_of(T)            -> T[]
        --   array_of(optional(T))  -> (T|nil)[]
        -- Zod distinguishes z.string().array() vs z.string().optional().array()
        -- the same way; silently flattening to T[] would lose the nil admission.
        -- `described` wrappers are transparent (doc-only).
        -- See workspace/tasks/shape-convention/design.md §P0 修正メモ Q2.
        local elem = rawget(node, "elem")
        local had_optional = false
        while true do
            local k = rawget(elem, "kind")
            if k == "optional" then
                had_optional = true
                elem = rawget(elem, "inner")
            elseif k == "described" then
                elem = rawget(elem, "inner")
            else
                break
            end
        end
        local inner_type = type_of(elem, class_prefix)
        if had_optional then
            return "(" .. inner_type .. "|nil)[]"
        end
        return inner_type .. "[]"
    elseif kind == "discriminated" then
        return "table"
    elseif kind == "map_of" then
        local k = type_of(rawget(node, "key"), class_prefix)
        local v = type_of(rawget(node, "val"), class_prefix)
        return "table<" .. k .. ", " .. v .. ">"
    elseif kind == "shape" then
        -- inline nested shape renders as `table` (no anonymous class emitted).
        return "table"
    elseif kind == "ref" then
        -- ref renders as the target named class (PascalCase of the ref name).
        return class_prefix .. pascal_case(rawget(node, "name"))
    elseif kind == "one_of" then
        local vs = rawget(node, "values")
        local parts = {}
        for i = 1, #vs do
            local v = vs[i]
            if type(v) == "string" then
                parts[i] = string.format("%q", v)
            else
                parts[i] = tostring(v)
            end
        end
        return table.concat(parts, "|")
    else
        error("alc_shapes.luacats: unknown kind '" .. tostring(kind) .. "'", 2)
    end
end

--- Render a single class block for a shape schema.
--- `class_prefix` is used to resolve `ref(name)` occurrences inside the
--- schema; defaults to "AlcResult" to match `gen()`.
function M.class_for(class_name, schema, class_prefix)
    if type(class_name) ~= "string" or class_name == "" then
        error("alc_shapes.luacats.class_for: class_name must be non-empty string", 2)
    end
    if type(schema) ~= "table" or rawget(schema, "kind") ~= "shape" then
        error("alc_shapes.luacats.class_for: schema must be kind='shape'", 2)
    end
    class_prefix = class_prefix or "AlcResult"
    local lines = { "---@class " .. class_name }
    local entries = reflect.fields(schema)
    for i = 1, #entries do
        local e = entries[i]
        local suffix = e.optional and "?" or ""
        local ty = type_of(e.type, class_prefix)
        local line = string.format("---@field %s%s %s", e.name, suffix, ty)
        if e.doc then
            line = line .. " @" .. e.doc
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n") .. "\n"
end

--- Generate the full contents of types/alc_shapes.d.lua from a
--- table of `{ [name] = shape_schema, ... }`. Output always ends
--- with a newline (drift check compatibility).
function M.gen(shapes_table, class_prefix)
    if shapes_table ~= nil and type(shapes_table) ~= "table" then
        error("alc_shapes.luacats.gen: shapes_table must be table or nil", 2)
    end
    class_prefix = class_prefix or "AlcResult"

    local names = {}
    if shapes_table ~= nil then
        for name, schema in pairs(shapes_table) do
            if type(schema) == "table" and rawget(schema, "kind") == "shape" then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)

    local out = { "---@meta" }
    for i = 1, #names do
        local name = names[i]
        local class_name = class_prefix .. pascal_case(name)
        out[#out + 1] = ""
        out[#out + 1] = M.class_for(class_name, shapes_table[name], class_prefix):gsub("\n$", "")
    end

    return table.concat(out, "\n") .. "\n"
end

M._internal = {
    pascal_case = pascal_case,
    type_of     = type_of,
}

return M
