---@module 'flow.util'
-- Internal utilities for the flow Frame (not part of public API).

local M = {}

-- Seed PRNG once at module load. os.clock differentiates multiple
-- require() calls within the same os.time() tick. We additionally fold
-- in 4 bytes from /dev/urandom when available — this guards against
-- two independent processes starting within the same second both
-- reading near-zero os.clock() and colliding on the seed. On platforms
-- without /dev/urandom (Windows native Lua), we fall back to the
-- time+clock seed.
do
    local seed = os.time() + math.floor((os.clock() or 0) * 1e6)
    local f = io.open("/dev/urandom", "rb")
    if f then
        local bytes = f:read(4)
        f:close()
        if type(bytes) == "string" and #bytes == 4 then
            local b1, b2, b3, b4 = bytes:byte(1, 4)
            seed = seed + b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
        end
    end
    math.randomseed(seed)
end

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

--- Extract value from a tag of the form `[tag_name=VALUE]`.
--- VALUE must match `[%w_%-]+` (letters, digits, underscore, hyphen).
--- When multiple matching tags are present, returns the LAST one — this
--- is required because flow.llm appends its tag pair to the prompt end,
--- and prompts often carry an earlier gate's echoed tags embedded in
--- `prev_output`. Reading first-match would hit the stale tag and raise a
--- spurious mismatch error.
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
    local last
    for m in text:gmatch(pattern) do
        last = m
    end
    return last
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

--- Recursive structural equality. Handles nil, primitives, and nested
--- tables with the same key set. Functions / userdata / thread are
--- compared by reference (==). Metatables are NOT considered.
---@param a any
---@param b any
---@return boolean
function M.deep_equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not M.deep_equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

return M
