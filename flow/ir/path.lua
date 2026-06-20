---@module 'flow.ir.path'
-- JSONPath-ish path parser shared by compile (validation) and
-- interpreter (read/write).
--
-- ## Subset (RFC 9535 minimal)
--
-- Two segment kinds:
--   - **name selector**: `.foo` or leading `foo` — accesses string
--     keys on a table. May contain any chars except `.` and `[`.
--   - **bracket integer index**: `[N]` — accesses integer keys
--     (1-based Lua array index). Negative N reads from the tail
--     (e.g. `[-1]` is the last element); negative N on WRITE raises.
--
-- Out of scope (per design §3.4):
--   - wildcard `[*]`
--   - slice `[1:5]`
--   - filter `[?(@.x == 1)]`
--   - quoted name selectors `["foo bar"]`
--
-- ## Output
--
-- `parse(s)` returns a flat list of segments where each entry is
-- either a `string` (name) or an `integer` (bracket index). The list
-- preserves the order in which they appear in the source string. The
-- caller (read / write / compile validator) interprets the first
-- segment as the root token (`"$"` for reads, `"ctx"` for writes).

local M = {}

--- Parse a path string into a flat segment list.
---
---@param s string
---@return (string|integer)[]|nil  segments
---@return string?  reason  set when segments is nil
function M.parse(s)
    if type(s) ~= "string" or s == "" then
        return nil, "empty path"
    end
    local segs, i, len = {}, 1, #s
    -- leading segment may start directly with a name (write-side "ctx.foo")
    -- OR a special character that the parser also handles below.
    if s:sub(i, i) ~= "." and s:sub(i, i) ~= "[" then
        local j = i
        while j <= len do
            local c = s:sub(j, j)
            if c == "." or c == "[" then break end
            j = j + 1
        end
        segs[#segs + 1] = s:sub(i, j - 1)
        i = j
    end
    while i <= len do
        local c = s:sub(i, i)
        if c == "." then
            i = i + 1
            local j = i
            while j <= len do
                local d = s:sub(j, j)
                if d == "." or d == "[" then break end
                j = j + 1
            end
            if j == i then
                return nil, "empty name segment after '.'"
            end
            segs[#segs + 1] = s:sub(i, j - 1)
            i = j
        elseif c == "[" then
            local end_pos = s:find("]", i + 1, true)
            if not end_pos then
                return nil, "unterminated '[' in path"
            end
            local inner = s:sub(i + 1, end_pos - 1)
            if inner == "" then
                return nil, "empty bracket segment '[]'"
            end
            local n = tonumber(inner)
            if not n or n ~= math.floor(n) then
                return nil, "non-integer bracket segment: [" .. inner .. "]"
            end
            if n == 0 then
                return nil, "bracket index must be non-zero (1-based; negatives count from end)"
            end
            segs[#segs + 1] = n
            i = end_pos + 1
        else
            return nil, "unexpected char '" .. c .. "' at position " .. i
        end
    end
    return segs
end

--- Validate that `s` parses cleanly. Returns (true) or (nil, reason).
---@param s string
---@return true|nil ok
---@return string?  reason
function M.validate(s)
    local segs, reason = M.parse(s)
    if not segs then return nil, reason end
    return true
end

return M
