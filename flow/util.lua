---@module 'flow.util'
-- Utilities for the flow Frame. Most entries are internal (random_hex /
-- parse_tag / shallow_copy / deep_equal); `unwrap_result` is part of the
-- public boundary surface re-exported as `flow.unwrap_result`.

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

--- Unwrap a bundled pkg return value to its business result.
---
--- Bundled pkg authored against the `ctx` convention return the call
--- site's `ctx` with the business result tucked under `ctx.result`
--- (see ab_mcts/init.lua:404, orch_gatephase/init.lua:287,
--- cascade/init.lua:347, coevolve/init.lua:422 etc.). Some pkg or
--- mock harnesses still return the result fields at top level — both
--- shapes need to be tolerated at every pkg boundary inside a Recipe
--- / Example.
---
--- Equivalent to the inline idiom `local r = out.result or out`
--- previously copied across recipe_swarm_gate (4 boundaries) and the
--- 4 flow/doc/examples (4 boundaries). Consolidating here means a
--- future shape unification (e.g. enforcing ctx-only return) only has
--- to be migrated in one place.
---
--- The fallback is intentionally permissive: when `out` is nil the
--- helper returns nil so that downstream `nil.<field>` errors surface
--- the same way as if the inline idiom had been used. When `out` is a
--- non-table primitive it is returned as-is for the same reason.
---
--- Boundary regression discipline: spec mocks SHOULD return the
--- production `{ result = {...} }` shape so that an accidental shape
--- drift (e.g. 2026-06-21 commit 42629df where mocks returned flat
--- top-level fields and a real LLM run insta-failed at root_gate)
--- cannot pass the spec while breaking real E2E. This helper is the
--- defense-in-depth layer; mocks matching production shape are the
--- primary defense.
---@generic T
---@param out T|{result: T}|nil
---@return T|nil
function M.unwrap_result(out)
    if type(out) ~= "table" then return out end
    if out.result ~= nil then return out.result end
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
