--- Tests for flow.ir Expr.call_extern: value-shape Hatch for the IR.
---
--- Covers (a) compile-time shape + ref non-empty check + eager whitelist
--- check via opts.externs; (b) exec-time resolution via opts.externs +
--- error semantics when the whitelist is missing / fn unregistered; (c)
--- end-to-end dissolution of A1 regex_match / A2 json_decode / A4
--- array_append / A6b keys atoms — proving these can be expressed via
--- host functions without growing the Expr op set per use case.

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

local ir      = require("flow.ir")
local compile = ir.compile
local exec    = ir.exec

local function letx(at, value)
    return { kind = "let", at = at, value = value }
end

-- ── shape + constructor ─────────────────────────────────────────────

describe("flow.ir Expr.call_extern: shape", function()
    it("constructor builds a tagged table with ref + args", function()
        local e = ir.call_extern("string.match", ir.lit("hello"), ir.lit("h(.+)"))
        expect(e.op).to.equal("call_extern")
        expect(e.ref).to.equal("string.match")
        expect(#e.args).to.equal(2)
    end)

    it("constructor accepts zero args (nullary)", function()
        local e = ir.call_extern("now")
        expect(e.op).to.equal("call_extern")
        expect(#e.args).to.equal(0)
    end)

    it("compile rejects empty ref", function()
        local _, reason = compile(letx("ctx.x", ir.call_extern("", ir.lit("a"))))
        expect(reason:find("call_extern.ref: required non%-empty string")).to.exist()
    end)
end)

-- ── compile-time whitelist (eager via opts.externs) ────────────────

describe("flow.ir Expr.call_extern: compile-time whitelist", function()
    it("compile passes when opts.externs contains the ref", function()
        local def = letx("ctx.x", ir.call_extern("upper", ir.lit("a")))
        local compiled, reason = compile(def, { externs = { upper = string.upper } })
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(def)  -- identity
    end)

    it("compile rejects unknown ref when opts.externs is provided", function()
        local def = letx("ctx.x", ir.call_extern("mystery", ir.lit("a")))
        local _, reason = compile(def, { externs = { upper = string.upper } })
        expect(reason:find(
            "call_extern.ref: 'mystery' not in opts.externs registry")).to.exist()
    end)

    it("compile defers to exec when opts.externs is omitted", function()
        -- Lazy registry: shape-valid call_extern compiles without
        -- opts.externs (the ref check happens at exec).
        local def = letx("ctx.x", ir.call_extern("mystery", ir.lit("a")))
        local compiled, reason = compile(def)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(def)
    end)
end)

-- ── exec-time resolution + errors ──────────────────────────────────

describe("flow.ir Expr.call_extern: exec", function()
    it("invokes the registered fn with evaluated positional args", function()
        local def = letx("ctx.out", ir.call_extern("string.format",
            ir.lit("n=%d, s=%s"), ir.lit(7), ir.lit("hi")))
        local ctx = exec(def, {}, { externs = { ["string.format"] = string.format } })
        expect(ctx.out).to.equal("n=7, s=hi")
    end)

    it("returns the raw fn result (no coercion)", function()
        local def = letx("ctx.t", ir.call_extern("pair", ir.lit(1), ir.lit(2)))
        local ctx = exec(def, {}, {
            externs = { pair = function(a, b) return { a, b } end },
        })
        expect(ctx.t[1]).to.equal(1)
        expect(ctx.t[2]).to.equal(2)
    end)

    it("raises when opts.externs is nil", function()
        local def = letx("ctx.x", ir.call_extern("upper", ir.lit("a")))
        expect(function() exec(def, {}) end).to.fail()
    end)

    it("raises when ref is not in opts.externs", function()
        local def = letx("ctx.x", ir.call_extern("missing", ir.lit("a")))
        expect(function()
            exec(def, {}, { externs = { upper = string.upper } })
        end).to.fail()
    end)

    it("raises when registered value is not a function", function()
        local def = letx("ctx.x", ir.call_extern("oops", ir.lit("a")))
        expect(function()
            exec(def, {}, { externs = { oops = "not a function" } })
        end).to.fail()
    end)

    it("threads opts.externs through nested Expr (inside fold)", function()
        -- Stress: call_extern lives under a fold env-binding context.
        -- The interpreter must forward opts through the recursion.
        local def = letx("ctx.sum_strs", ir.fold({
            from     = ir.lit({ "a", "bb", "ccc" }),
            init     = ir.lit(0),
            acc_var  = "acc",
            item_var = "item",
            fn       = ir.call_extern("add_len", ir["var"]("acc"), ir["var"]("item")),
        }))
        local ctx = exec(def, {}, {
            externs = {
                add_len = function(acc, s) return acc + #s end,
            },
        })
        expect(ctx.sum_strs).to.equal(6)  -- 1 + 2 + 3
    end)
end)

-- ── A1 / A2 / A4 / A6b dissolution proofs ──────────────────────────
--
-- These tests prove that the four "missing" Expr ops listed in issue
-- edf05e72 are NOT needed as IR atoms — they can be expressed via
-- call_extern + host helpers without growing M.EXPR_OPS.

describe("flow.ir Expr.call_extern: dissolves A1 regex_match", function()
    it("string.match via call_extern extracts a capture", function()
        local def = letx("ctx.captured", ir.call_extern("string.match",
            ir.lit("DONE path=alpha"),
            ir.lit("^DONE path=(%S+)$")))
        local ctx = exec(def, {}, {
            externs = { ["string.match"] = string.match },
        })
        expect(ctx.captured).to.equal("alpha")
    end)
end)

describe("flow.ir Expr.call_extern: dissolves A2 json_decode", function()
    it("json_decode via call_extern parses a literal string", function()
        local def = letx("ctx.parsed", ir.call_extern("json_decode",
            ir.lit('{"status":"pass","n":3}')))
        local ctx = exec(def, {}, {
            externs = {
                json_decode = function(s)
                    -- Minimal stand-in (mirroring alc.json_decode).
                    -- Production wires the real codec.
                    local status = s:match('"status":"([^"]+)"')
                    local n = tonumber(s:match('"n":(%d+)'))
                    return { status = status, n = n }
                end,
            },
        })
        expect(ctx.parsed.status).to.equal("pass")
        expect(ctx.parsed.n).to.equal(3)
    end)
end)

describe("flow.ir Expr.call_extern: dissolves A4 array_append", function()
    it("immutable append via call_extern produces a new array", function()
        local def = letx("ctx.next", ir.call_extern("array_append",
            ir.lit({ "a", "b" }), ir.lit("c")))
        local ctx = exec(def, {}, {
            externs = {
                array_append = function(arr, x)
                    local r = {}
                    for i, v in ipairs(arr) do r[i] = v end
                    r[#r + 1] = x
                    return r
                end,
            },
        })
        expect(ctx.next[1]).to.equal("a")
        expect(ctx.next[2]).to.equal("b")
        expect(ctx.next[3]).to.equal("c")
    end)
end)

describe("flow.ir Expr.call_extern: dissolves A6b keys", function()
    it("keys via call_extern returns a sorted key list", function()
        local def = letx("ctx.ks", ir.call_extern("keys",
            ir.lit({ alpha = 1, beta = 2, gamma = 3 })))
        local ctx = exec(def, {}, {
            externs = {
                keys = function(t)
                    local r = {}
                    for k in pairs(t) do r[#r + 1] = k end
                    table.sort(r)
                    return r
                end,
            },
        })
        expect(#ctx.ks).to.equal(3)
        expect(ctx.ks[1]).to.equal("alpha")
        expect(ctx.ks[2]).to.equal("beta")
        expect(ctx.ks[3]).to.equal("gamma")
    end)
end)
