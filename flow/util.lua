---@module 'flow.util'
-- Internal utilities for the flow Frame (not part of public API).

local M = {}

-- Seed PRNG once at module load. os.clock mixed in to differentiate
-- multiple require() calls within the same os.time() tick.
math.randomseed(os.time() + math.floor((os.clock() or 0) * 1e6))

--- Generate an n-character lowercase hex string.
---@param n integer? default 16
---@return string
function M.random_hex(n)
    n = n or 16
    local chars = {}
    for i = 1, n do
        chars[i] = string.format("%x", math.random(0, 15))
    end
    return table.concat(chars)
end

--- Extract value from a single tag of the form `[tag_name=VALUE]`.
--- VALUE must match `[%w_%-]+` (letters, digits, underscore, hyphen).
--- Returns nil on no match or invalid inputs.
---@param text string
---@param tag_name string
---@return string?
function M.parse_tag(text, tag_name)
    if type(text) ~= "string" or type(tag_name) ~= "string" then
        return nil
    end
    local escaped = tag_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local pattern = "%[" .. escaped .. "=([%w_%-]+)%]"
    return text:match(pattern)
end

--- Shallow-copy a table. Non-table inputs are returned unchanged.
---@generic T
---@param t T
---@return T
function M.shallow_copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

return M
