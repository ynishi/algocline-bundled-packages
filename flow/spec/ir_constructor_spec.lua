--- Constructor API ↔ raw table SoT equivalence (Step 3 §3.0).
---
--- Asserts that for every Expr (8 ops) and every Node (7 kinds), the
--- constructor wrapper (`flow.ir.<name>(...)`) produces a table that is
--- deep-equal to the canonical raw-table form. This pins the contract
--- "raw table is the SoT; constructors are thin sugar".

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

-- ── helpers ─────────────────────────────────────────────────────────

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

-- sanity check on the helper (so a buggy comparator does not mask
-- real constructor drift downstream).
describe("deep_equal helper", function()
    it("matches identical scalars", function()
        expect(deep_equal(1, 1)).to.equal(true)
        expect(deep_equal("a", "a")).to.equal(true)
        expect(deep_equal(nil, nil)).to.equal(true)
    end)
    it("matches identical tables", function()
        expect(deep_equal({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } }))
            .to.equal(true)
    end)
    it("rejects mismatched values", function()
        expect(deep_equal(1, 2)).to.equal(false)
        expect(deep_equal({ a = 1 }, { a = 2 })).to.equal(false)
        expect(deep_equal({ a = 1 }, { a = 1, b = 2 })).to.equal(false)
    end)
end)

-- ── Expr constructors (8 ops) ───────────────────────────────────────

describe("flow.ir constructor — Expr", function()
    it("path / lit (≤1 field, positional)", function()
        expect(deep_equal(ir.path("$.ctx.v"), { op = "path", at = "$.ctx.v" }))
            .to.equal(true)
        expect(deep_equal(ir.lit(42), { op = "lit", value = 42 })).to.equal(true)
        expect(deep_equal(ir.lit(nil), { op = "lit", value = nil })).to.equal(true)
    end)

    it("eq / lt (2 fields, positional)", function()
        local l, r = ir.path("$.ctx.a"), ir.lit(1)
        expect(deep_equal(ir.eq(l, r), { op = "eq", lhs = l, rhs = r }))
            .to.equal(true)
        expect(deep_equal(ir.lt(l, r), { op = "lt", lhs = l, rhs = r }))
            .to.equal(true)
    end)

    it("and / or (variadic, bracket access)", function()
        local a, b, c = ir.lit(true), ir.lit(false), ir.lit(true)
        expect(deep_equal(ir["and"](a, b, c),
            { op = "and", args = { a, b, c } })).to.equal(true)
        expect(deep_equal(ir["or"](a, b),
            { op = "or", args = { a, b } })).to.equal(true)
    end)

    it("not / len (1 field, positional; not via bracket)", function()
        local arg = ir.path("$.ctx.x")
        expect(deep_equal(ir["not"](arg),
            { op = "not", arg = arg })).to.equal(true)
        expect(deep_equal(ir.len(arg),
            { op = "len", arg = arg })).to.equal(true)
    end)
end)

-- ── Node constructors (7 kinds) ─────────────────────────────────────

describe("flow.ir constructor — Node", function()
    it("step (table-arg, in_ optional)", function()
        local in_expr = ir.path("$.ctx.input")
        expect(deep_equal(
            ir.step({ ref = "h", out = "ctx.r", in_ = in_expr }),
            { kind = "step", ref = "h", out = "ctx.r", in_ = in_expr }
        )).to.equal(true)
        -- in_ omitted → nil (matches schema is_optional)
        expect(deep_equal(
            ir.step({ ref = "h", out = "ctx.r" }),
            { kind = "step", ref = "h", out = "ctx.r", in_ = nil }
        )).to.equal(true)
    end)

    it("seq (variadic children)", function()
        local a = ir.step({ ref = "a", out = "ctx.a" })
        local b = ir.step({ ref = "b", out = "ctx.b" })
        expect(deep_equal(ir.seq(a, b),
            { kind = "seq", children = { a, b } })).to.equal(true)
        expect(deep_equal(ir.seq(),
            { kind = "seq", children = {} })).to.equal(true)
    end)

    it("branch (cond / then_ / else_)", function()
        local cond = ir.lit(true)
        local t = ir.step({ ref = "t", out = "ctx.t" })
        local e = ir.step({ ref = "e", out = "ctx.e" })
        expect(deep_equal(
            ir.branch({ cond = cond, then_ = t, else_ = e }),
            { kind = "branch", cond = cond, then_ = t, else_ = e }
        )).to.equal(true)
        -- else_ omitted
        expect(deep_equal(
            ir.branch({ cond = cond, then_ = t }),
            { kind = "branch", cond = cond, then_ = t, else_ = nil }
        )).to.equal(true)
    end)

    it("let (bracket access)", function()
        local value = ir.lit(1)
        expect(deep_equal(
            ir["let"]({ at = "ctx.x", value = value }),
            { kind = "let", at = "ctx.x", value = value }
        )).to.equal(true)
    end)

    it("loop", function()
        local cond = ir.lit(true)
        local body = ir.step({ ref = "b", out = "ctx.b" })
        expect(deep_equal(
            ir.loop({ cond = cond, body = body, max = 5, counter = "ctx.i" }),
            { kind = "loop", cond = cond, body = body, max = 5, counter = "ctx.i" }
        )).to.equal(true)
    end)

    it("call", function()
        local args = { x = ir.path("$.ctx.x") }
        expect(deep_equal(
            ir.call({ flow = "sub", args = args, out = "ctx.r" }),
            { kind = "call", flow = "sub", args = args, out = "ctx.r" }
        )).to.equal(true)
    end)

    it("fanout (all / any)", function()
        local items = ir.path("$.ctx.items")
        local body = ir.step({ ref = "b", out = "ctx.b" })
        expect(deep_equal(
            ir.fanout({
                items = items, bind = "ctx.it", body = body,
                join = "all", out = "ctx.r",
            }),
            {
                kind = "fanout", items = items, bind = "ctx.it",
                body = body, join = "all", out = "ctx.r",
            }
        )).to.equal(true)
        expect(deep_equal(
            ir.fanout({
                items = items, bind = "ctx.it", body = body,
                join = "any", out = "ctx.r",
            }),
            {
                kind = "fanout", items = items, bind = "ctx.it",
                body = body, join = "any", out = "ctx.r",
            }
        )).to.equal(true)
    end)
end)

-- ── compile / exec acceptance (sanity) ──────────────────────────────
--
-- Constructed nodes flow through compile + exec just like raw tables.

describe("flow.ir constructor — compile + exec parity", function()
    it("constructor-built seq passes compile", function()
        local node = ir.seq(
            ir.step({ ref = "a", out = "ctx.a" }),
            ir.step({ ref = "b", out = "ctx.b" })
        )
        local ok, reason = ir.compile(node)
        expect(ok).to.exist()
        expect(reason).to_not.exist()
    end)

    it("constructor-built branch + let executes end-to-end", function()
        local node = ir.seq(
            ir["let"]({ at = "ctx.flag", value = ir.lit(true) }),
            ir.branch({
                cond  = ir.path("$.ctx.flag"),
                then_ = ir["let"]({ at = "ctx.taken", value = ir.lit("t") }),
                else_ = ir["let"]({ at = "ctx.taken", value = ir.lit("e") }),
            })
        )
        local compiled = assert(ir.compile(node))
        local ctx = ir.exec(compiled, {})
        expect(ctx.flag).to.equal(true)
        expect(ctx.taken).to.equal("t")
    end)
end)
