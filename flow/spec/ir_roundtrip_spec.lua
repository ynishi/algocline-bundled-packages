--- Round-trip property spec for flow.ir persistence (Step 3 §3.2b).
---
--- Asserts `from_json(to_json(node)) == node` (deep equal) for every
--- Node kind (7) and every Expr op (8), exercising the persistence
--- API land in §3.2a end-to-end against a minimal standalone JSON
--- impl injected via `opts.alc`.
---
--- The JSON impl below is a spec-local minimal encoder/decoder
--- (sufficient for the table shapes used by flow.ir). It is NOT part
--- of the published surface — flow.ir is host-neutral and ships no
--- JSON impl. Production callers inject algocline's `alc.json_encode`
--- / `alc.json_decode` via `_G.alc` (or any other compatible pair).

local describe, it, expect = lust.describe, lust.it, lust.expect

local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local ir = require("flow.ir")

-- ── minimal JSON encoder / decoder (spec-local) ─────────────────────
--
-- Shape contract sufficient for flow.ir Node / Expr round-trip:
--   - nil       → null   (and back)
--   - boolean   ↔ true / false
--   - number    ↔ numeric literal
--   - string    ↔ "..."   (escapes: \" \\ \n \r \t)
--   - sequence  ↔ JSON array         (detected via `#t > 0` rule;
--                                    empty tables encode as `{}`)
--   - mapping   ↔ JSON object (string keys only)
--
-- This is NOT a general-purpose JSON impl. It encodes a Lua table as
-- an array iff it has at least one entry at index 1 (covers all
-- flow.ir sequence shapes — seq.children / and.args / or.args).
-- Empty tables (e.g. fanout produced with empty `items`) are encoded
-- as objects `{}`; round-trip preserves the empty-table shape.

local function encode(v)
    local t = type(v)
    if v == nil then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        if v ~= v then error("encode: NaN not supported", 0) end
        return tostring(v)
    elseif t == "string" then
        local esc = v
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
        return '"' .. esc .. '"'
    elseif t == "table" then
        if rawget(v, 1) ~= nil then
            -- array form
            local parts = {}
            for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- object form (keys are strings; nil values skipped)
            local parts, keys = {}, {}
            for k, _ in pairs(v) do
                if type(k) ~= "string" then
                    error("encode: object keys must be string, got " .. type(k), 0)
                end
                keys[#keys + 1] = k
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local val = v[k]
                if val ~= nil then
                    parts[#parts + 1] = encode(k) .. ":" .. encode(val)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    error("encode: unsupported type " .. t, 0)
end

local decode

local function skip_ws(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1
        else
            return i
        end
    end
    return i
end

local function decode_string(s, i)
    -- s:sub(i,i) == '"'
    i = i + 1
    local buf = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(buf), i + 1
        elseif c == "\\" then
            local nx = s:sub(i + 1, i + 1)
            if nx == "n" then buf[#buf + 1] = "\n"
            elseif nx == "r" then buf[#buf + 1] = "\r"
            elseif nx == "t" then buf[#buf + 1] = "\t"
            elseif nx == "\\" then buf[#buf + 1] = "\\"
            elseif nx == '"' then buf[#buf + 1] = '"'
            else error("decode: bad escape \\" .. nx, 0) end
            i = i + 2
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    error("decode: unterminated string", 0)
end

local function decode_number(s, i)
    local j = i
    while j <= #s do
        local c = s:sub(j, j)
        if c:match("[%-%+%d%.eE]") then
            j = j + 1
        else
            break
        end
    end
    local n = tonumber(s:sub(i, j - 1))
    if not n then error("decode: bad number near " .. s:sub(i, j - 1), 0) end
    return n, j
end

local function decode_array(s, i)
    i = i + 1  -- past '['
    local out = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then return out, i + 1 end
    while true do
        local v
        v, i = decode(s, i)
        out[#out + 1] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = i + 1
            i = skip_ws(s, i)
        elseif c == "]" then
            return out, i + 1
        else
            error("decode: expected , or ] near " .. c, 0)
        end
    end
end

local function decode_object(s, i)
    i = i + 1  -- past '{'
    local out = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then return out, i + 1 end
    while true do
        i = skip_ws(s, i)
        if s:sub(i, i) ~= '"' then error("decode: expected string key", 0) end
        local key
        key, i = decode_string(s, i)
        i = skip_ws(s, i)
        if s:sub(i, i) ~= ":" then error("decode: expected ':' after key", 0) end
        i = skip_ws(s, i + 1)
        local v
        v, i = decode(s, i)
        out[key] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = i + 1
        elseif c == "}" then
            return out, i + 1
        else
            error("decode: expected , or } near " .. c, 0)
        end
    end
end

decode = function(s, i)
    i = skip_ws(s, i or 1)
    local c = s:sub(i, i)
    if c == "{" then return decode_object(s, i)
    elseif c == "[" then return decode_array(s, i)
    elseif c == '"' then return decode_string(s, i)
    elseif c == "t" and s:sub(i, i + 3) == "true" then return true, i + 4
    elseif c == "f" and s:sub(i, i + 4) == "false" then return false, i + 5
    elseif c == "n" and s:sub(i, i + 3) == "null" then return nil, i + 4
    elseif c == "-" or c:match("%d") then return decode_number(s, i)
    end
    error("decode: unexpected char '" .. c .. "' at " .. i, 0)
end

local function decode_top(s)
    local v = decode(s, 1)
    return v
end

local ALC = { json_encode = encode, json_decode = decode_top }
local OPTS = { alc = ALC }

-- ── deep equal (handles tables with mixed/missing nil) ──────────────

local function deep_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then return false end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- ── encoder / decoder sanity ────────────────────────────────────────

describe("spec-local JSON impl sanity", function()
    it("round-trips primitives", function()
        expect(decode_top(encode(true))).to.equal(true)
        expect(decode_top(encode(false))).to.equal(false)
        expect(decode_top(encode(42))).to.equal(42)
        expect(decode_top(encode("hi"))).to.equal("hi")
    end)
    it("round-trips arrays", function()
        local v = { 1, 2, "x" }
        expect(deep_equal(decode_top(encode(v)), v)).to.equal(true)
    end)
    it("round-trips nested objects", function()
        local v = { a = { b = { c = 1 } } }
        expect(deep_equal(decode_top(encode(v)), v)).to.equal(true)
    end)
end)

-- ── Expr round-trip (8 ops) ─────────────────────────────────────────

local function roundtrip(node)
    return ir.from_json(ir.to_json(node, OPTS), OPTS)
end

describe("flow.ir round-trip — Expr (8 ops)", function()
    it("path", function()
        local n = ir.path("$.ctx.v")
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("lit (number / string / boolean)", function()
        for _, v in ipairs({ 0, 42, -1.5, "hi", true, false }) do
            local n = ir.lit(v)
            expect(deep_equal(roundtrip(n), n)).to.equal(true)
        end
    end)
    it("eq", function()
        local n = ir.eq(ir.path("$.ctx.a"), ir.lit(1))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("lt", function()
        local n = ir.lt(ir.path("$.ctx.a"), ir.lit(10))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("and (variadic)", function()
        local n = ir["and"](ir.lit(true), ir.lit(false), ir.path("$.ctx.x"))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("or (variadic)", function()
        local n = ir["or"](ir.lit(true), ir.lit(false))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("not", function()
        local n = ir["not"](ir.path("$.ctx.x"))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("len", function()
        local n = ir.len(ir.path("$.ctx.list"))
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
end)

-- ── Node round-trip (7 kinds) ───────────────────────────────────────

describe("flow.ir round-trip — Node (7 kinds)", function()
    it("step (with in_)", function()
        local n = ir.step({
            ref = "handler", out = "ctx.r", in_ = ir.path("$.ctx.input"),
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("step (in_ omitted)", function()
        local n = ir.step({ ref = "h", out = "ctx.r" })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("seq", function()
        local n = ir.seq(
            ir.step({ ref = "a", out = "ctx.a" }),
            ir.step({ ref = "b", out = "ctx.b" })
        )
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("branch (with else_)", function()
        local n = ir.branch({
            cond  = ir.eq(ir.path("$.ctx.x"), ir.lit(1)),
            then_ = ir.step({ ref = "t", out = "ctx.t" }),
            else_ = ir.step({ ref = "e", out = "ctx.e" }),
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("branch (else_ omitted)", function()
        local n = ir.branch({
            cond  = ir.lit(true),
            then_ = ir.step({ ref = "t", out = "ctx.t" }),
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("let", function()
        local n = ir["let"]({ at = "ctx.x", value = ir.lit(42) })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("loop", function()
        local n = ir.loop({
            cond  = ir.lt(ir.path("$.ctx.i"), ir.lit(5)),
            body  = ir.step({ ref = "tick", out = "ctx.tick" }),
            max   = 10,
            counter = "ctx.i",
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("call", function()
        local n = ir.call({
            flow = "sub",
            args = { x = ir.path("$.ctx.x"), y = ir.lit(1) },
            out  = "ctx.r",
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("fanout (all)", function()
        local n = ir.fanout({
            items = ir.path("$.ctx.items"),
            bind  = "ctx.item",
            body  = ir.step({ ref = "work", out = "ctx.w" }),
            join  = "all",
            out   = "ctx.r",
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
    it("fanout (any)", function()
        local n = ir.fanout({
            items = ir.lit({ 1, 2, 3 }),
            bind  = "ctx.it",
            body  = ir.step({ ref = "w", out = "ctx.w" }),
            join  = "any",
            out   = "ctx.r",
        })
        expect(deep_equal(roundtrip(n), n)).to.equal(true)
    end)
end)

-- ── compound tree round-trip ────────────────────────────────────────

describe("flow.ir round-trip — compound tree", function()
    it("seq(let, branch(eq, step+let, step)) round-trips", function()
        local n = ir.seq(
            ir["let"]({ at = "ctx.flag", value = ir.lit(true) }),
            ir.branch({
                cond  = ir.eq(ir.path("$.ctx.flag"), ir.lit(true)),
                then_ = ir.seq(
                    ir.step({ ref = "yes", out = "ctx.y", in_ = ir.path("$.ctx.flag") }),
                    ir["let"]({ at = "ctx.taken", value = ir.lit("t") })
                ),
                else_ = ir.step({ ref = "no", out = "ctx.n" }),
            })
        )
        local rt = roundtrip(n)
        expect(deep_equal(rt, n)).to.equal(true)
        -- and the round-tripped tree should still pass compile.
        local ok, reason = ir.compile(rt)
        expect(ok).to.exist()
        expect(reason).to_not.exist()
    end)
end)
