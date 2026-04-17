--- alc_shapes.check — validator (check / assert / assert_dev / is_dev_mode).
---
--- API:
---   check(value, schema)                -> ok:boolean, reason:string?
---   assert(value, schema_or_name, hint) -> value (or throws)
---   assert_dev(value, ..., hint)        -> value (no-op pass if dev off)
---   is_dev_mode()                       -> boolean
---
--- Paths use JSONPath-ish form with 1-based array indices:
---   $.field, $[1], $.stages[2].name
---
--- Error message:
---   shape violation at <path>: <detail> (ctx: <hint>)

local M = {}

-- Primitive type test (separate from schema kind).
local function lua_type_of(v) return type(v) end

-- Forward decls.
local check_node

local handlers = {}

handlers.any = function(_value, _schema, _path)
    return true
end

handlers.prim = function(value, schema, path)
    local expected = schema.prim
    local got = lua_type_of(value)
    if got ~= expected then
        return false, string.format(
            "shape violation at %s: expected %s, got %s",
            path, expected, got)
    end
    return true
end

handlers.optional = function(value, schema, path)
    if value == nil then return true end
    return check_node(value, schema.inner, path)
end

handlers.described = function(value, schema, path)
    return check_node(value, schema.inner, path)
end

handlers.array_of = function(value, schema, path)
    if type(value) ~= "table" then
        return false, string.format(
            "shape violation at %s: expected table (array), got %s",
            path, type(value))
    end
    -- iterate 1-based dense indices
    for i = 1, #value do
        local item = value[i]
        local sub_path = path .. "[" .. i .. "]"
        local ok, reason = check_node(item, schema.elem, sub_path)
        if not ok then return false, reason end
    end
    return true
end

handlers.shape = function(value, schema, path)
    if type(value) ~= "table" then
        return false, string.format(
            "shape violation at %s: expected table, got %s",
            path, type(value))
    end
    local fields = schema.fields
    -- Determinism: sort field names so first-fail reports the same
    -- violating field across runs. Lua `pairs` order is unspecified;
    -- tableshape / Zod / Joi all leave this to implementation but we
    -- require reproducibility for CI + conformance tests.
    local names = {}
    for name in pairs(fields) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        local name = names[i]
        local sub_schema = fields[name]
        local sub_path = (path == "$") and ("$." .. name) or (path .. "." .. name)
        local sub_val = value[name]
        local ok, reason = check_node(sub_val, sub_schema, sub_path)
        if not ok then return false, reason end
    end
    -- strict mode: reject extra keys when open=false. Also sorted
    -- for deterministic error reporting (Q1).
    if schema.open == false then
        local extra = {}
        for name in pairs(value) do
            if type(name) == "string" and fields[name] == nil then
                extra[#extra + 1] = name
            end
        end
        table.sort(extra)
        if extra[1] ~= nil then
            local name = extra[1]
            local sub_path = (path == "$") and ("$." .. name) or (path .. "." .. name)
            return false, string.format(
                "shape violation at %s: unexpected field", sub_path)
        end
    end
    return true
end

handlers.discriminated = function(value, schema, path)
    if type(value) ~= "table" then
        return false, string.format(
            "shape violation at %s: expected table, got %s",
            path, type(value))
    end
    local tag = schema.tag
    local tag_val = value[tag]
    if tag_val == nil then
        return false, string.format(
            "shape violation at %s: missing discriminant field '%s'",
            path, tag)
    end
    local variant = schema.variants[tag_val]
    if variant == nil then
        local keys = {}
        for k in pairs(schema.variants) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for i = 1, #keys do parts[i] = string.format("%q", keys[i]) end
        return false, string.format(
            "shape violation at %s: discriminant '%s' = %q not in [%s]",
            path, tag, tostring(tag_val), table.concat(parts, ", "))
    end
    return handlers.shape(value, variant, path)
end

handlers.map_of = function(value, schema, path)
    if type(value) ~= "table" then
        return false, string.format(
            "shape violation at %s: expected table (map), got %s",
            path, type(value))
    end
    for k, v in pairs(value) do
        local key_path = path .. "[key=" .. tostring(k) .. "]"
        local ok, reason = check_node(k, schema.key, key_path)
        if not ok then return false, reason end
        local val_path = path .. "[" .. tostring(k) .. "]"
        ok, reason = check_node(v, schema.val, val_path)
        if not ok then return false, reason end
    end
    return true
end

handlers.ref = function(value, schema, path)
    local name = schema.name
    -- Lazy-require to avoid circular load on init.
    local shapes = require("alc_shapes")
    local resolved = shapes[name]
    if resolved == nil or type(resolved) ~= "table"
            or rawget(resolved, "kind") == nil then
        return false, string.format(
            "shape violation at %s: unresolved ref '%s'", path, name)
    end
    return check_node(value, resolved, path)
end

handlers.one_of = function(value, schema, path)
    local vs = schema.values
    for i = 1, #vs do
        if value == vs[i] then return true end
    end
    local parts = {}
    for i = 1, #vs do
        local v = vs[i]
        if type(v) == "string" then
            parts[i] = string.format("%q", v)
        else
            parts[i] = tostring(v)
        end
    end
    return false, string.format(
        "shape violation at %s: expected one of [%s], got %s",
        path, table.concat(parts, ", "), tostring(value))
end

check_node = function(value, schema, path)
    if schema == nil then return true end
    local kind = rawget(schema, "kind")
    if kind == nil then
        error("alc_shapes.check: schema missing 'kind' field", 2)
    end
    local h = handlers[kind]
    if h == nil then
        error("alc_shapes.check: unknown kind '" .. tostring(kind) .. "'", 2)
    end
    return h(value, schema, path)
end

--- Return (ok, reason). Never throws for normal schema violations.
function M.check(value, schema)
    if schema == nil then return true end
    return check_node(value, schema, "$")
end

local function compose_msg(reason, ctx_hint)
    if ctx_hint == nil or ctx_hint == "" then return reason end
    return reason .. " (ctx: " .. tostring(ctx_hint) .. ")"
end

--- Assert schema; returns value on pass, throws on fail.
--- Overloads on schema_or_name:
---   nil          -> no-op pass (value returned)
---   "any"        -> no-op pass
---   other string -> lookup in alc_shapes registry (loud fail if unknown)
---   table        -> direct schema
function M.assert(value, schema_or_name, ctx_hint)
    local schema
    if schema_or_name == nil then
        return value
    elseif type(schema_or_name) == "string" then
        if schema_or_name == "any" then return value end
        -- lazy-require to avoid circular load
        local shapes = require("alc_shapes")
        schema = shapes[schema_or_name]
        if schema == nil or type(schema) ~= "table" or rawget(schema, "kind") == nil then
            error("alc_shapes.assert: unknown shape name '" .. schema_or_name .. "'", 2)
        end
    elseif type(schema_or_name) == "table" then
        schema = schema_or_name
    else
        error("alc_shapes.assert: schema_or_name must be nil, string, or table (got "
            .. type(schema_or_name) .. ")", 2)
    end
    local ok, reason = M.check(value, schema)
    if not ok then
        error(compose_msg(reason, ctx_hint), 2)
    end
    return value
end

--- Dev-mode-only assert: no-op pass when ALC_SHAPE_CHECK != "1".
function M.assert_dev(value, schema_or_name, ctx_hint)
    if not M.is_dev_mode() then return value end
    return M.assert(value, schema_or_name, ctx_hint)
end

function M.is_dev_mode()
    return os.getenv("ALC_SHAPE_CHECK") == "1"
end

M._internal = {
    handlers    = handlers,
    check_node  = check_node,
    compose_msg = compose_msg,
}

return M
