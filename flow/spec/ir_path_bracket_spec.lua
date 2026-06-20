--- Tests for the JSONPath bracket-selector subset (Step 3 §3.4).
---
--- RFC 9535 subset:
---   - name selector (`.foo`) — existing behaviour
---   - integer bracket selector (`[N]`) — 1-based, negatives count
---     from the tail on READ; negative on WRITE is rejected
--- Out of scope (deferred): wildcard / slice / filter / quoted names.

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

local ir   = require("flow.ir")
local path = require("flow.ir.path")
local interp = require("flow.ir.interpreter")

-- ── parser ──────────────────────────────────────────────────────────

describe("flow.ir.path.parse", function()
    it("returns string segments for name-only paths", function()
        local segs = path.parse("$.ctx.foo.bar")
        expect(#segs).to.equal(4)
        expect(segs[1]).to.equal("$")
        expect(segs[2]).to.equal("ctx")
        expect(segs[3]).to.equal("foo")
        expect(segs[4]).to.equal("bar")
    end)

    it("returns integer segments for bracket selectors", function()
        local segs = path.parse("$.ctx.items[3]")
        expect(#segs).to.equal(4)
        expect(segs[1]).to.equal("$")
        expect(segs[2]).to.equal("ctx")
        expect(segs[3]).to.equal("items")
        expect(segs[4]).to.equal(3)
    end)

    it("supports negative integer indices", function()
        local segs = path.parse("$.ctx.items[-1]")
        expect(segs[4]).to.equal(-1)
    end)

    it("supports chained bracket selectors", function()
        local segs = path.parse("$.ctx.m[1][2]")
        expect(#segs).to.equal(5)
        expect(segs[4]).to.equal(1)
        expect(segs[5]).to.equal(2)
    end)

    it("parses write-style paths (no leading $)", function()
        local segs = path.parse("ctx.items[3]")
        expect(segs[1]).to.equal("ctx")
        expect(segs[3]).to.equal(3)
    end)

    it("rejects empty bracket `[]`", function()
        local segs, reason = path.parse("$.ctx.foo[]")
        expect(segs).to.equal(nil)
        expect(reason:find("empty bracket")).to_not.equal(nil)
    end)

    it("rejects non-integer bracket content", function()
        local segs, reason = path.parse("$.ctx.foo[abc]")
        expect(segs).to.equal(nil)
        expect(reason:find("non%-integer")).to_not.equal(nil)
    end)

    it("rejects zero index (1-based; 0 reserved)", function()
        local segs, reason = path.parse("$.ctx.foo[0]")
        expect(segs).to.equal(nil)
        expect(reason:find("non%-zero")).to_not.equal(nil)
    end)

    it("rejects unterminated bracket", function()
        local segs, reason = path.parse("$.ctx.foo[3")
        expect(segs).to.equal(nil)
        expect(reason:find("unterminated")).to_not.equal(nil)
    end)

    it("rejects empty name after '.'", function()
        local segs, reason = path.parse("$.ctx..foo")
        expect(segs).to.equal(nil)
        expect(reason:find("empty name")).to_not.equal(nil)
    end)
end)

-- ── read_path semantics ─────────────────────────────────────────────

describe("interpreter.read_path — bracket selector", function()
    local read_path = interp._read_path

    it("reads positive bracket index (1-based)", function()
        local ctx = { items = { "a", "b", "c" } }
        expect(read_path(ctx, "$.ctx.items[1]")).to.equal("a")
        expect(read_path(ctx, "$.ctx.items[3]")).to.equal("c")
    end)

    it("reads negative bracket index (-1 = last)", function()
        local ctx = { items = { "a", "b", "c" } }
        expect(read_path(ctx, "$.ctx.items[-1]")).to.equal("c")
        expect(read_path(ctx, "$.ctx.items[-2]")).to.equal("b")
        expect(read_path(ctx, "$.ctx.items[-3]")).to.equal("a")
    end)

    it("returns nil for out-of-range index (positive and negative)", function()
        local ctx = { items = { "a", "b" } }
        expect(read_path(ctx, "$.ctx.items[5]")).to.equal(nil)
        expect(read_path(ctx, "$.ctx.items[-5]")).to.equal(nil)
    end)

    it("walks nested arrays via chained brackets", function()
        local ctx = { m = { { 10, 20 }, { 30, 40 } } }
        expect(read_path(ctx, "$.ctx.m[1][1]")).to.equal(10)
        expect(read_path(ctx, "$.ctx.m[2][2]")).to.equal(40)
        expect(read_path(ctx, "$.ctx.m[-1][-1]")).to.equal(40)
    end)
end)

-- ── write_path semantics ────────────────────────────────────────────

describe("interpreter.write_path — bracket selector", function()
    local write_path = interp._write_path

    it("writes a positive bracket index, auto-creating the array table", function()
        local ctx = {}
        write_path(ctx, "ctx.items[2]", "hello")
        expect(type(ctx.items)).to.equal("table")
        expect(ctx.items[2]).to.equal("hello")
    end)

    it("writes through nested brackets, auto-creating intermediates", function()
        local ctx = {}
        write_path(ctx, "ctx.m[1][3]", 42)
        expect(ctx.m[1][3]).to.equal(42)
    end)

    it("rejects negative index on write (no well-defined semantics)", function()
        local ctx = { items = { "a", "b" } }
        local ok, err = pcall(write_path, ctx, "ctx.items[-1]", "x")
        expect(ok).to.equal(false)
        expect(tostring(err):find("negative index not supported"))
            .to_not.equal(nil)
    end)
end)

-- ── compile-time validation ─────────────────────────────────────────

describe("flow.ir.compile — bracket selector syntax", function()
    it("accepts a bracket selector in Expr.path.at", function()
        local node = ir["let"]({
            at = "ctx.x",
            value = ir.path("$.ctx.items[1]"),
        })
        local ok = ir.compile(node)
        expect(ok).to.exist()
    end)

    it("rejects malformed bracket syntax in Expr.path.at at compile time", function()
        local node = ir["let"]({
            at = "ctx.x",
            value = ir.path("$.ctx.foo[abc]"),
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(tostring(reason):find("non%-integer")).to_not.equal(nil)
    end)

    it("accepts a bracket selector in write-side step.out", function()
        local node = ir.step({ ref = "h", out = "ctx.items[1]" })
        local ok = ir.compile(node)
        expect(ok).to.exist()
    end)

    it("rejects malformed bracket syntax in step.out at compile time", function()
        local node = ir.step({ ref = "h", out = "ctx.items[" })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(tostring(reason):find("unterminated")).to_not.equal(nil)
    end)
end)

-- ── end-to-end through compile + exec ───────────────────────────────

describe("flow.ir.exec — bracket selector end-to-end", function()
    it("reads a positive-index element via let from a seeded array", function()
        local node = ir["let"]({
            at = "ctx.picked",
            value = ir.path("$.ctx.items[2]"),
        })
        local compiled = assert(ir.compile(node))
        local ctx = ir.exec(compiled, { items = { "a", "b", "c" } })
        expect(ctx.picked).to.equal("b")
    end)

    it("reads via negative index", function()
        local node = ir["let"]({
            at = "ctx.last",
            value = ir.path("$.ctx.items[-1]"),
        })
        local compiled = assert(ir.compile(node))
        local ctx = ir.exec(compiled, { items = { 10, 20, 30 } })
        expect(ctx.last).to.equal(30)
    end)

    it("writes into an array slot via step.out + dispatch", function()
        local node = ir.step({ ref = "produce", out = "ctx.slots[3]" })
        local compiled = assert(ir.compile(node))
        local dispatch = function(_ref, _input) return "filled" end
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(ctx.slots[3]).to.equal("filled")
    end)
end)
