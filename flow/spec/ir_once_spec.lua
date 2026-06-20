--- Tests for flow.ir once Node (resume guard).

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

describe("flow.ir.compile once", function()
    it("accepts a minimal once Node", function()
        local ir = fresh_ir()
        local node = ir.once({
            flag = "ctx.did_init",
            body = ir["let"]({ at = "ctx.x", value = ir.lit(1) }),
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("rejects flag without ctx. prefix", function()
        local ir = fresh_ir()
        local node = ir.once({
            flag = "did_init",
            body = ir["let"]({ at = "ctx.x", value = ir.lit(1) }),
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("once.flag must start with 'ctx.'")).to_not.equal(nil)
    end)

    it("descends into body for validation", function()
        local ir = fresh_ir()
        -- body has an invalid let.at (no ctx. prefix)
        local node = ir.once({
            flag = "ctx.did",
            body = { kind = "let", at = "bad", value = ir.lit(1) },
        })
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("let.at must start with 'ctx.'")).to_not.equal(nil)
    end)
end)

describe("flow.ir.exec once", function()
    it("runs body when flag is falsy then sets flag = true", function()
        local ir = fresh_ir()
        local node = ir.once({
            flag = "ctx.did_init",
            body = ir["let"]({ at = "ctx.x", value = ir.lit(42) }),
        })
        local compiled = ir.compile(node)
        local ctx = ir.exec(compiled, {}, {})
        expect(ctx.x).to.equal(42)
        expect(ctx.did_init).to.equal(true)
    end)

    it("skips body when flag is already truthy", function()
        local ir = fresh_ir()
        local calls = 0
        local node = ir.once({
            flag = "ctx.did_init",
            body = ir.step({ ref = "noop", out = "ctx.r" }),
        })
        local compiled = ir.compile(node)
        local ctx = ir.exec(compiled, { did_init = true }, {
            dispatch = function(_ref, _input)
                calls = calls + 1
                return { ok = true }
            end,
        })
        expect(calls).to.equal(0)
        expect(ctx.r).to.equal(nil)
        expect(ctx.did_init).to.equal(true)
    end)

    it("re-running after a successful first pass skips the body (idempotent)", function()
        local ir = fresh_ir()
        local calls = 0
        local node = ir.once({
            flag = "ctx.did",
            body = ir.step({ ref = "tick", out = "ctx.r" }),
        })
        local compiled = ir.compile(node)
        local dispatch = function(_ref, _input)
            calls = calls + 1
            return { ok = true, n = calls }
        end
        local ctx = ir.exec(compiled, {}, { dispatch = dispatch })
        expect(calls).to.equal(1)
        expect(ctx.did).to.equal(true)
        -- second pass with the same ctx — body must not run
        ir.exec(compiled, ctx, { dispatch = dispatch })
        expect(calls).to.equal(1)
    end)
end)

describe("flow.ir.walk once", function()
    it("enumerates body as a single child", function()
        local ir = fresh_ir()
        local body = ir["let"]({ at = "ctx.x", value = ir.lit(1) })
        local node = ir.once({ flag = "ctx.f", body = body })
        local children = ir.children_of(node)
        expect(#children).to.equal(1)
        expect(children[1].child).to.equal(body)
        expect(children[1].key).to.equal("body")
    end)
end)
