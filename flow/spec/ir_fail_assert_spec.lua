--- Tests for flow.ir fail / assert Nodes.

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

local function fresh_ir()
    reset_modules()
    return require("flow.ir")
end

describe("flow.ir.compile fail/assert", function()
    it("accepts a minimal fail Node", function()
        local ir = fresh_ir()
        local node = ir["fail"]({ message = ir.lit("boom") })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("accepts a minimal assert Node", function()
        local ir = fresh_ir()
        local node = ir["assert"]({
            cond = ir.eq(ir.path("$.ctx.x"), ir.lit(1)),
            message = ir.lit("x must be 1"),
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("rejects malformed fail.message Expr", function()
        local ir = fresh_ir()
        -- bare table (no op) — invalid Expr
        local node = { kind = "fail", message = { op = "bogus" } }
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("unknown Expr op")).to_not.equal(nil)
    end)
end)

describe("flow.ir.exec fail", function()
    it("always raises with the eval'd message", function()
        local ir = fresh_ir()
        local node = ir.compile(ir["fail"]({ message = ir.lit("nope") }))
        local ok, err = pcall(ir.exec, node, {}, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("exec: fail: nope")).to_not.equal(nil)
    end)

    it("evaluates message Expr against ctx", function()
        local ir = fresh_ir()
        local node = ir.compile(ir["fail"]({
            message = ir.concat(ir.lit("bad="), ir.path("$.ctx.reason")),
        }))
        local ok, err = pcall(ir.exec, node, { reason = "timeout" }, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("exec: fail: bad=timeout")).to_not.equal(nil)
    end)

    it("raises when message does not eval to a string", function()
        local ir = fresh_ir()
        local node = ir.compile(ir["fail"]({ message = ir.lit(123) }))
        local ok, err = pcall(ir.exec, node, {}, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("fail.message must eval to a string")).to_not.equal(nil)
    end)
end)

describe("flow.ir.exec assert", function()
    it("no-ops when cond is truthy", function()
        local ir = fresh_ir()
        local node = ir.compile(ir["assert"]({
            cond = ir.eq(ir.path("$.ctx.x"), ir.lit(1)),
            message = ir.lit("x must be 1"),
        }))
        local ctx = ir.exec(node, { x = 1 }, {})
        expect(ctx.x).to.equal(1)
    end)

    it("raises with eval'd message when cond is falsy", function()
        local ir = fresh_ir()
        local node = ir.compile(ir["assert"]({
            cond = ir.eq(ir.path("$.ctx.x"), ir.lit(1)),
            message = ir.concat(ir.lit("x="), ir.path("$.ctx.x_str")),
        }))
        local ok, err = pcall(ir.exec, node, { x = 2, x_str = "two" }, {})
        expect(ok).to.equal(false)
        expect(tostring(err):find("exec: assert: x=two")).to_not.equal(nil)
    end)
end)

describe("flow.ir.refs_of fail/assert", function()
    it("collects refs from fail.message", function()
        local ir = fresh_ir()
        local node = ir["fail"]({
            message = ir.concat(ir.lit("e="), ir.path("$.ctx.err")),
        })
        local refs = ir.refs_of(node)
        expect(#refs).to.equal(1)
        expect(refs[1]).to.equal("$.ctx.err")
    end)

    it("collects refs from assert.cond and assert.message", function()
        local ir = fresh_ir()
        local node = ir["assert"]({
            cond = ir.eq(ir.path("$.ctx.x"), ir.lit(1)),
            message = ir.path("$.ctx.msg"),
        })
        local refs = ir.refs_of(node)
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("$.ctx.x")
        expect(refs[2]).to.equal("$.ctx.msg")
    end)
end)
