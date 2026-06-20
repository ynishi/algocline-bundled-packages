--- Tests for flow.ir Expr v0.8.0 additions: concat / add / get.
---
--- Covers compile-time shape + runtime eval + error semantics
--- (no implicit tostring / no number coercion / strict key types).

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

local function exec_let(value, ctx)
    return exec(letx("ctx.out", value), ctx or {})
end

-- ── concat ──────────────────────────────────────────────────────────

describe("flow.ir Expr.concat", function()
    it("constructor + happy path joins string Exprs", function()
        local e = ir.concat(ir.lit("hello "), ir.lit("world"))
        expect(e.op).to.equal("concat")
        expect(#e.args).to.equal(2)
        local ctx = exec_let(e, {})
        expect(ctx.out).to.equal("hello world")
    end)

    it("joins literal + path read from ctx", function()
        local e = ir.concat(ir.lit("branch_"), ir.path("$.ctx.i"))
        local ctx = exec_let(e, { i = "3" })
        expect(ctx.out).to.equal("branch_3")
    end)

    it("compile rejects fewer than 2 args", function()
        local _, reason = compile(letx("ctx.x", ir.concat(ir.lit("a"))))
        expect(reason:find("concat: requires >= 2 args")).to.exist()
    end)

    it("exec raises on non-string arg (no tostring coercion)", function()
        local e = ir.concat(ir.lit("n="), ir.lit(7))
        expect(function() exec_let(e, {}) end).to.fail()
    end)
end)

-- ── add ─────────────────────────────────────────────────────────────

describe("flow.ir Expr.add", function()
    it("constructor + numeric addition", function()
        local e = ir.add(ir.path("$.ctx.round"), ir.lit(1))
        local ctx = exec_let(e, { round = 4 })
        expect(ctx.out).to.equal(5)
    end)

    it("exec raises on non-number lhs", function()
        local e = ir.add(ir.lit("3"), ir.lit(1))
        expect(function() exec_let(e, {}) end).to.fail()
    end)

    it("exec raises on non-number rhs", function()
        local e = ir.add(ir.lit(1), ir.lit("3"))
        expect(function() exec_let(e, {}) end).to.fail()
    end)
end)

-- ── get ─────────────────────────────────────────────────────────────

describe("flow.ir Expr.get", function()
    it("constructor + dynamic table[key] read", function()
        local e = ir.get(ir.path("$.ctx.branches"), ir.path("$.ctx.bkey"))
        local ctx = exec_let(e, {
            branches = { branch_1 = "first", branch_2 = "second" },
            bkey     = "branch_2",
        })
        expect(ctx.out).to.equal("second")
    end)

    it("returns nil for missing key (Lua t[k] semantics)", function()
        local e = ir.get(ir.path("$.ctx.t"), ir.lit("missing"))
        local ctx = exec_let(e, { t = { a = 1 } })
        expect(ctx.out).to.equal(nil)
    end)

    it("accepts numeric key", function()
        local e = ir.get(ir.path("$.ctx.items"), ir.lit(2))
        local ctx = exec_let(e, { items = { "x", "y", "z" } })
        expect(ctx.out).to.equal("y")
    end)

    it("exec raises when from is not a table", function()
        local e = ir.get(ir.lit("string"), ir.lit("k"))
        expect(function() exec_let(e, {}) end).to.fail()
    end)

    it("exec raises when key is not string or number", function()
        local e = ir.get(ir.path("$.ctx.t"), ir.lit(true))
        expect(function() exec_let(e, { t = {} }) end).to.fail()
    end)
end)

-- ── walk / refs_of integration ──────────────────────────────────────

describe("flow.ir integration with new Exprs", function()
    it("refs_of collects path.at inside concat / add / get subtrees", function()
        local e = letx("ctx.o", ir.concat(
            ir.path("$.ctx.prefix"),
            ir.get(ir.path("$.ctx.map"), ir.path("$.ctx.k"))
        ))
        local refs = ir.refs_of(e)
        -- order is traversal order; we just assert membership
        local seen = {}
        for _, r in ipairs(refs) do seen[r] = true end
        expect(seen["$.ctx.prefix"]).to.equal(true)
        expect(seen["$.ctx.map"]).to.equal(true)
        expect(seen["$.ctx.k"]).to.equal(true)
    end)

    it("compile descends into nested children (error path-tagged)", function()
        -- Nested path with wrong root should be caught.
        local e = letx("ctx.o", ir.concat(ir.lit("a"), ir.path("$.bad.x")))
        local _, reason = compile(e)
        expect(reason:find("Expr%.path%.at must start")).to.exist()
    end)
end)
