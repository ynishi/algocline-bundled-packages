--- Tests for flow.ir filter / fold / var Exprs (axis-7 collection Exprs).

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

describe("filter Expr", function()
    it("keeps elements satisfying pred", function()
        local ir, eval = fresh()
        local e = ir.filter(
            ir.lit({ 1, 2, 3, 4, 5 }),
            "x",
            ir.gt(ir["var"]("x"), ir.lit(2))
        )
        local res = eval(e, {})
        expect(#res).to.equal(3)
        expect(res[1]).to.equal(3)
        expect(res[2]).to.equal(4)
        expect(res[3]).to.equal(5)
    end)

    it("returns empty array when nothing passes", function()
        local ir, eval = fresh()
        local e = ir.filter(ir.lit({ 1, 2, 3 }), "x", ir.gt(ir["var"]("x"), ir.lit(100)))
        local res = eval(e, {})
        expect(#res).to.equal(0)
    end)

    it("raises when from is not an array", function()
        local ir, eval = fresh()
        local e = ir.filter(ir.lit("nope"), "x", ir.lit(true))
        local ok, err = pcall(eval, e, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("filter.from must be an array")).to_not.equal(nil)
    end)
end)

describe("fold Expr", function()
    it("sums via add", function()
        local ir, eval = fresh()
        local e = ir.fold({
            from = ir.lit({ 1, 2, 3, 4 }),
            init = ir.lit(0),
            acc_var = "a",
            item_var = "x",
            fn = ir.add(ir["var"]("a"), ir["var"]("x")),
        })
        expect(eval(e, {})).to.equal(10)
    end)

    it("returns init on empty array", function()
        local ir, eval = fresh()
        local e = ir.fold({
            from = ir.lit({}),
            init = ir.lit(42),
            acc_var = "a", item_var = "x",
            fn = ir["var"]("a"),
        })
        expect(eval(e, {})).to.equal(42)
    end)

    it("concatenates strings", function()
        local ir, eval = fresh()
        local e = ir.fold({
            from = ir.lit({ "a", "b", "c" }),
            init = ir.lit(""),
            acc_var = "a", item_var = "x",
            fn = ir.concat(ir["var"]("a"), ir["var"]("x")),
        })
        expect(eval(e, {})).to.equal("abc")
    end)
end)

describe("var Expr without env", function()
    it("raises when called without enclosing filter/fold", function()
        local ir, eval = fresh()
        local ok, err = pcall(eval, ir["var"]("x"), {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("var 'x' has no enclosing binding env")).to_not.equal(nil)
    end)
end)

describe("compile filter/fold", function()
    it("accepts valid filter", function()
        local ir = fresh()
        local node = ir["let"]({
            at = "ctx.evens",
            value = ir.filter(ir.path("$.ctx.nums"), "n",
                ir.eq(ir.mod(ir["var"]("n"), ir.lit(2)), ir.lit(0))),
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("rejects malformed filter child", function()
        local ir = fresh()
        local node = ir["let"]({
            at = "ctx.r",
            value = { op = "filter", from = ir.lit({}), var = "x", pred = { op = "bad" } },
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("unknown Expr op")).to_not.equal(nil)
    end)
end)

describe("refs_of walks filter/fold children", function()
    it("collects path refs through filter from + pred", function()
        local ir = fresh()
        local e = ir.filter(ir.path("$.ctx.nums"), "n",
            ir.lt(ir.path("$.ctx.cutoff"), ir["var"]("n")))
        local refs = ir.refs_of(e)
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("$.ctx.nums")
        expect(refs[2]).to.equal("$.ctx.cutoff")
    end)

    it("collects path refs through fold from + init + fn", function()
        local ir = fresh()
        local e = ir.fold({
            from = ir.path("$.ctx.items"),
            init = ir.path("$.ctx.seed"),
            acc_var = "a", item_var = "x",
            fn = ir.add(ir["var"]("a"), ir.path("$.ctx.bias")),
        })
        local refs = ir.refs_of(e)
        expect(#refs).to.equal(3)
        expect(refs[1]).to.equal("$.ctx.items")
        expect(refs[2]).to.equal("$.ctx.seed")
        expect(refs[3]).to.equal("$.ctx.bias")
    end)
end)

describe("filter inside flow context (exec)", function()
    it("works inside a let Node", function()
        local ir = fresh()
        local node = ir.compile(ir["let"]({
            at = "ctx.big",
            value = ir.filter(
                ir.path("$.ctx.nums"),
                "n",
                ir.gt(ir["var"]("n"), ir.lit(10))
            ),
        }))
        local ctx = ir.exec(node, { nums = { 5, 10, 15, 20 } }, {})
        expect(#ctx.big).to.equal(2)
        expect(ctx.big[1]).to.equal(15)
        expect(ctx.big[2]).to.equal(20)
    end)
end)
