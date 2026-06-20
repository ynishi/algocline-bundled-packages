--- Tests for flow.ir map / reduce Nodes.

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
    return require("flow.ir")
end

describe("flow.ir.compile map/reduce", function()
    it("accepts a minimal map", function()
        local ir = fresh()
        local node = ir.map({
            in_ = ir.lit({ 1, 2, 3 }),
            bind = "ctx.it",
            body = ir["let"]({ at = "ctx.r", value = ir.mul(ir.path("$.ctx.it"), ir.lit(2)) }),
            collect = "ctx.r",
            out = "ctx.doubled",
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("rejects map.bind without ctx. prefix", function()
        local ir = fresh()
        local node = ir.map({
            in_ = ir.lit({}),
            bind = "it",
            body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }),
            collect = "ctx.r",
            out = "ctx.o",
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("map.bind must start with 'ctx.'")).to_not.equal(nil)
    end)

    it("accepts a minimal reduce", function()
        local ir = fresh()
        local node = ir.reduce({
            in_ = ir.lit({ 1, 2, 3 }),
            init = ir.lit(0),
            acc = "ctx.sum",
            bind = "ctx.it",
            body = ir["let"]({
                at = "ctx.sum",
                value = ir.add(ir.path("$.ctx.sum"), ir.path("$.ctx.it")),
            }),
            out = "ctx.total",
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)
end)

describe("flow.ir.exec map", function()
    it("collects per-item results into out", function()
        local ir = fresh()
        local node = ir.compile(ir.map({
            in_ = ir.lit({ 1, 2, 3, 4 }),
            bind = "ctx.it",
            body = ir["let"]({
                at = "ctx.r",
                value = ir.mul(ir.path("$.ctx.it"), ir.path("$.ctx.it")),
            }),
            collect = "ctx.r",
            out = "ctx.squares",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(#ctx.squares).to.equal(4)
        expect(ctx.squares[1]).to.equal(1)
        expect(ctx.squares[2]).to.equal(4)
        expect(ctx.squares[3]).to.equal(9)
        expect(ctx.squares[4]).to.equal(16)
    end)

    it("works with empty input", function()
        local ir = fresh()
        local node = ir.compile(ir.map({
            in_ = ir.lit({}),
            bind = "ctx.it",
            body = ir["let"]({ at = "ctx.r", value = ir.path("$.ctx.it") }),
            collect = "ctx.r",
            out = "ctx.o",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(#ctx.o).to.equal(0)
    end)

    it("raises when in_ is not an array", function()
        local ir = fresh()
        local node = ir.compile(ir.map({
            in_ = ir.lit("nope"),
            bind = "ctx.it",
            body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }),
            collect = "ctx.r",
            out = "ctx.o",
        }))
        local ok, err = pcall(ir.exec, node, {}, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("map.in_: expected array")).to_not.equal(nil)
    end)
end)

describe("flow.ir.exec reduce", function()
    it("sums via add update body", function()
        local ir = fresh()
        local node = ir.compile(ir.reduce({
            in_ = ir.lit({ 1, 2, 3, 4 }),
            init = ir.lit(0),
            acc = "ctx.sum",
            bind = "ctx.it",
            body = ir["let"]({
                at = "ctx.sum",
                value = ir.add(ir.path("$.ctx.sum"), ir.path("$.ctx.it")),
            }),
            out = "ctx.total",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.total).to.equal(10)
    end)

    it("returns init value on empty input", function()
        local ir = fresh()
        local node = ir.compile(ir.reduce({
            in_ = ir.lit({}),
            init = ir.lit(42),
            acc = "ctx.a",
            bind = "ctx.b",
            body = ir["let"]({ at = "ctx.a", value = ir.lit(0) }),
            out = "ctx.o",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.o).to.equal(42)
    end)
end)

describe("flow.ir.walk map/reduce", function()
    it("children_of yields body", function()
        local ir = fresh()
        local body = ir["let"]({ at = "ctx.x", value = ir.lit(1) })
        local node = ir.map({
            in_ = ir.lit({}), bind = "ctx.it", body = body,
            collect = "ctx.r", out = "ctx.o",
        })
        local children = ir.children_of(node)
        expect(#children).to.equal(1)
        expect(children[1].child).to.equal(body)
        expect(children[1].key).to.equal("body")
    end)

    it("refs_of walks reduce.in_ and reduce.init", function()
        local ir = fresh()
        local node = ir.reduce({
            in_ = ir.path("$.ctx.items"),
            init = ir.path("$.ctx.seed"),
            acc = "ctx.a", bind = "ctx.b",
            body = ir["let"]({ at = "ctx.a", value = ir.lit(1) }),
            out = "ctx.o",
        })
        local refs = ir.refs_of(node)
        -- $.ctx.items + $.ctx.seed (body's let has no path ref)
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("$.ctx.items")
        expect(refs[2]).to.equal("$.ctx.seed")
    end)
end)
