--- Tests for flow.ir axis-4 Expr extensions (sub/mul/div/mod, gt/gte/lte/ne,
--- exists, format).

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

local function reset_modules()
    for _, k in ipairs({ "flow.ir", "flow.ir.interpreter", "flow.ir.compile",
                        "flow.ir.schema", "flow.ir.walk" }) do
        package.loaded[k] = nil
    end
end

local function fresh()
    reset_modules()
    local ir = require("flow.ir")
    local interp = require("flow.ir.interpreter")
    return ir, interp._eval_expr
end

describe("eval_expr arithmetic", function()
    it("sub", function()
        local ir, eval = fresh()
        expect(eval(ir.sub(ir.lit(10), ir.lit(3)), {})).to.equal(7)
    end)
    it("mul", function()
        local ir, eval = fresh()
        expect(eval(ir.mul(ir.lit(4), ir.lit(5)), {})).to.equal(20)
    end)
    it("div", function()
        local ir, eval = fresh()
        expect(eval(ir.div(ir.lit(12), ir.lit(4)), {})).to.equal(3)
    end)
    it("mod", function()
        local ir, eval = fresh()
        expect(eval(ir.mod(ir.lit(10), ir.lit(3)), {})).to.equal(1)
    end)
    it("div by zero raises", function()
        local ir, eval = fresh()
        local ok, err = pcall(eval, ir.div(ir.lit(1), ir.lit(0)), {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("div.rhs must be non%-zero")).to_not.equal(nil)
    end)
    it("type error surfaces with op name", function()
        local ir, eval = fresh()
        local ok, err = pcall(eval, ir.sub(ir.lit("a"), ir.lit(1)), {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("sub.lhs must be a number")).to_not.equal(nil)
    end)
end)

describe("eval_expr comparison", function()
    it("gt", function()
        local ir, eval = fresh()
        expect(eval(ir.gt(ir.lit(5), ir.lit(3)), {})).to.equal(true)
        expect(eval(ir.gt(ir.lit(3), ir.lit(5)), {})).to.equal(false)
    end)
    it("gte / lte boundary", function()
        local ir, eval = fresh()
        expect(eval(ir.gte(ir.lit(5), ir.lit(5)), {})).to.equal(true)
        expect(eval(ir.lte(ir.lit(5), ir.lit(5)), {})).to.equal(true)
    end)
    it("ne", function()
        local ir, eval = fresh()
        expect(eval(ir.ne(ir.lit(1), ir.lit(2)), {})).to.equal(true)
        expect(eval(ir.ne(ir.lit(1), ir.lit(1)), {})).to.equal(false)
    end)
end)

describe("eval_expr exists", function()
    it("returns true on non-nil ctx read", function()
        local ir, eval = fresh()
        expect(eval(ir.exists(ir.path("$.ctx.x")), { x = 0 })).to.equal(true)
        expect(eval(ir.exists(ir.path("$.ctx.x")), { x = false })).to.equal(true)
    end)
    it("returns false on nil ctx read", function()
        local ir, eval = fresh()
        expect(eval(ir.exists(ir.path("$.ctx.missing")), {})).to.equal(false)
    end)
end)

describe("eval_expr format", function()
    it("formats with one positional arg", function()
        local ir, eval = fresh()
        local e = ir.format(ir.lit("hello %s"), ir.lit("world"))
        expect(eval(e, {})).to.equal("hello world")
    end)
    it("formats with multiple args of mixed types", function()
        local ir, eval = fresh()
        local e = ir.format(ir.lit("%d-%s-%d"), ir.lit(1), ir.path("$.ctx.tag"), ir.lit(3))
        expect(eval(e, { tag = "x" })).to.equal("1-x-3")
    end)
    it("raises when fmt is not a string", function()
        local ir, eval = fresh()
        local ok, err = pcall(eval, ir.format(ir.lit(1)), {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("format.fmt must be a string")).to_not.equal(nil)
    end)
end)

describe("compile descends into new Expr children", function()
    it("rejects malformed sub child", function()
        local ir = fresh()
        local node = ir["let"]({
            at = "ctx.x",
            value = ir.sub(ir.lit(1), { op = "bogus" }),
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("unknown Expr op")).to_not.equal(nil)
    end)

    it("refs_of walks format args", function()
        local ir = fresh()
        local e = ir.format(ir.lit("%s"), ir.path("$.ctx.a"))
        local refs = ir.refs_of(e)
        expect(#refs).to.equal(1)
        expect(refs[1]).to.equal("$.ctx.a")
    end)
end)
