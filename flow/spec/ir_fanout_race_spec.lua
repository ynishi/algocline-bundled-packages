--- Tests for fanout `race` / `all_settled` join modes (Step 3 §3.B).
---
--- Asserts the schema accepts the 4 enum values, that compile is
--- happy, and that the interpreter's serial fallback executes the
--- documented semantics:
---
---   race        : first to settle wins (success OR raise). In serial
---                 fallback, item[1] always settles first.
---   all_settled : every branch runs; failures recorded as
---                 { status = "rejected", reason = msg }
---                 successes as
---                 { status = "fulfilled", value = branch_ctx }
---
--- Promise / futures combinator parity:
---   all         ↔ Promise.all         / try_join_all
---   any         ↔ Promise.any         / select_ok
---   race        ↔ Promise.race        / select_all (first)
---   all_settled ↔ Promise.allSettled  / join_all

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

-- recording dispatcher: returns { ref = ..., n = N, item = N's item } or
-- raises on refs prefixed "boom:".
local function make_recorder()
    local log, n = {}, 0
    return function(ref, input)
        n = n + 1
        log[#log + 1] = { ref = ref, input = input, n = n }
        if ref:sub(1, 5) == "boom:" then
            error("recorder: " .. ref, 0)
        end
        return { ref = ref, n = n }
    end, log
end

-- ── compile / schema acceptance ─────────────────────────────────────

describe("flow.ir.compile — fanout join enum", function()
    it("accepts 'race'", function()
        local ok = ir.compile(ir.fanout({
            items = ir.lit({ 1, 2 }), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.h" }),
            join  = "race", out = "ctx.r",
        }))
        expect(ok).to.exist()
    end)
    it("accepts 'all_settled'", function()
        local ok = ir.compile(ir.fanout({
            items = ir.lit({ 1, 2 }), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.h" }),
            join  = "all_settled", out = "ctx.r",
        }))
        expect(ok).to.exist()
    end)
    it("rejects an unknown join value", function()
        local ok, reason = ir.compile(ir.fanout({
            items = ir.lit({ 1 }), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.h" }),
            join  = "garbage", out = "ctx.r",
        }))
        expect(ok).to.equal(nil)
        expect(type(reason)).to.equal("string")
    end)
end)

-- ── race semantics ──────────────────────────────────────────────────

describe("flow.ir.exec — fanout(race)", function()
    it("returns item[1]'s branch ctx on success", function()
        local node = ir.fanout({
            items = ir.lit({ "a", "b", "c" }),
            bind  = "ctx.tag",
            body  = ir.step({
                ref = "h", out = "ctx.r",
                in_ = ir.path("$.ctx.tag"),
            }),
            join = "race", out = "ctx.winner",
        })
        local compiled = assert(ir.compile(node))
        local dispatch, log = make_recorder()
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        -- only item[1] runs in serial race
        expect(#log).to.equal(1)
        expect(log[1].input).to.equal("a")
        -- ctx.winner is item[1]'s branch ctx
        expect(ctx.winner.tag).to.equal("a")
        expect(ctx.winner.r.n).to.equal(1)
    end)

    it("re-raises when the first-settled branch fails", function()
        local node = ir.fanout({
            items = ir.lit({ "x" }),
            bind  = "ctx.it",
            body  = ir.step({ ref = "boom:race", out = "ctx.r" }),
            join  = "race", out = "ctx.w",
        })
        local compiled = assert(ir.compile(node))
        local dispatch = make_recorder()
        local ok, err = pcall(ir.exec, compiled, {}, { dispatch = dispatch })
        expect(ok).to.equal(false)
        expect(tostring(err):find("fanout%(race%): first settled branch failed"))
            .to_not.equal(nil)
    end)

    it("writes out = {} on empty items", function()
        local node = ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.r" }),
            join  = "race", out = "ctx.w",
        })
        local compiled = assert(ir.compile(node))
        local dispatch, log = make_recorder()
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(#log).to.equal(0)
        expect(type(ctx.w)).to.equal("table")
        expect(next(ctx.w)).to.equal(nil)
    end)
end)

-- ── all_settled semantics ───────────────────────────────────────────

describe("flow.ir.exec — fanout(all_settled)", function()
    it("returns fulfilled records for all-success items", function()
        local node = ir.fanout({
            items = ir.lit({ "a", "b" }),
            bind  = "ctx.tag",
            body  = ir.step({
                ref = "h", out = "ctx.r",
                in_ = ir.path("$.ctx.tag"),
            }),
            join = "all_settled", out = "ctx.results",
        })
        local compiled = assert(ir.compile(node))
        local dispatch, log = make_recorder()
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(#log).to.equal(2)
        expect(#ctx.results).to.equal(2)
        expect(ctx.results[1].status).to.equal("fulfilled")
        expect(ctx.results[1].value.tag).to.equal("a")
        expect(ctx.results[2].status).to.equal("fulfilled")
        expect(ctx.results[2].value.tag).to.equal("b")
    end)

    it("records rejected entries WITHOUT raising", function()
        local node = ir.fanout({
            items = ir.lit({ "ok1", "fail", "ok2" }),
            bind  = "ctx.it",
            body  = ir.branch({
                cond  = ir.eq(ir.path("$.ctx.it"), ir.lit("fail")),
                then_ = ir.step({ ref = "boom:settled", out = "ctx.r" }),
                else_ = ir.step({
                    ref = "h", out = "ctx.r",
                    in_ = ir.path("$.ctx.it"),
                }),
            }),
            join = "all_settled", out = "ctx.results",
        })
        local compiled = assert(ir.compile(node))
        local dispatch = make_recorder()
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(#ctx.results).to.equal(3)
        expect(ctx.results[1].status).to.equal("fulfilled")
        expect(ctx.results[1].value.r.ref).to.equal("h")
        expect(ctx.results[2].status).to.equal("rejected")
        expect(type(ctx.results[2].reason)).to.equal("string")
        expect(ctx.results[2].reason:find("boom:settled")).to_not.equal(nil)
        expect(ctx.results[3].status).to.equal("fulfilled")
        expect(ctx.results[3].value.r.ref).to.equal("h")
    end)

    it("writes out = {} on empty items", function()
        local node = ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.r" }),
            join  = "all_settled", out = "ctx.w",
        })
        local compiled = assert(ir.compile(node))
        local dispatch, log = make_recorder()
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(#log).to.equal(0)
        expect(type(ctx.w)).to.equal("table")
        expect(next(ctx.w)).to.equal(nil)
    end)
end)

-- ── round-trip preservation (regression for ir_roundtrip pattern) ───

describe("flow.ir — race / all_settled round-trip via to_json", function()
    -- spec-local minimal JSON impl (shared in ir_roundtrip_spec but
    -- duplicated minimally here so this spec runs standalone too).
    local function encode(v)
        local t = type(v)
        if v == nil then return "null"
        elseif t == "boolean" then return v and "true" or "false"
        elseif t == "number" then return tostring(v)
        elseif t == "string" then
            return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
        elseif t == "table" then
            if rawget(v, 1) ~= nil then
                local p = {}
                for i = 1, #v do p[i] = encode(v[i]) end
                return "[" .. table.concat(p, ",") .. "]"
            else
                local p, keys = {}, {}
                for k in pairs(v) do keys[#keys + 1] = k end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    p[#p + 1] = encode(k) .. ":" .. encode(v[k])
                end
                return "{" .. table.concat(p, ",") .. "}"
            end
        end
        error("encode: bad type " .. t, 0)
    end
    -- A tiny decoder good enough for `{"kind":"fanout","join":"race",...}`.
    -- We only need to round-trip the join field structurally.
    local function decode(s)
        -- delegate via load(): JSON is a Lua expr subset for our small inputs
        -- when we replace `:` with `=` and quote keys. But simpler: just
        -- assert the encoded form contains the literal `"join":"race"` /
        -- `"join":"all_settled"` substring.
        return s
    end

    it("encodes 'race' as the literal `\"join\":\"race\"`", function()
        local node = ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.r" }),
            join  = "race", out = "ctx.w",
        })
        local s = ir.to_json(node, { alc = { json_encode = encode, json_decode = decode } })
        expect(s:find('"join":"race"', 1, true)).to_not.equal(nil)
    end)
    it("encodes 'all_settled' as the literal `\"join\":\"all_settled\"`", function()
        local node = ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body  = ir.step({ ref = "h", out = "ctx.r" }),
            join  = "all_settled", out = "ctx.w",
        })
        local s = ir.to_json(node, { alc = { json_encode = encode, json_decode = decode } })
        expect(s:find('"join":"all_settled"', 1, true)).to_not.equal(nil)
    end)
end)
