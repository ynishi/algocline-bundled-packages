--- Tests for flow.ir switch / try / return_early Nodes.

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

-- ── switch ──────────────────────────────────────────────────────────

describe("flow.ir switch compile", function()
    it("accepts >= 1 case", function()
        local ir = fresh()
        local node = ir.switch({
            on = ir.path("$.ctx.color"),
            cases = {
                { match = ir.lit("red"),  body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
                { match = ir.lit("blue"), body = ir["let"]({ at = "ctx.r", value = ir.lit(2) }) },
            },
        })
        local compiled, reason = ir.compile(node)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(node)
    end)

    it("rejects empty cases", function()
        local ir = fresh()
        local node = { kind = "switch", on = ir.lit(1), cases = {} }
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("requires >= 1 case")).to_not.equal(nil)
    end)

    it("rejects malformed case entry", function()
        local ir = fresh()
        local node = {
            kind = "switch",
            on = ir.lit(1),
            cases = { { match = ir.lit(1) } },  -- missing body
        }
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("switch.cases%[1%]")).to_not.equal(nil)
    end)
end)

describe("flow.ir switch exec", function()
    it("first matching case wins", function()
        local ir = fresh()
        local node = ir.compile(ir.switch({
            on = ir.path("$.ctx.color"),
            cases = {
                { match = ir.lit("red"),  body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
                { match = ir.lit("blue"), body = ir["let"]({ at = "ctx.r", value = ir.lit(2) }) },
            },
        }))
        local ctx = ir.exec(node, { color = "blue" }, {})
        expect(ctx.r).to.equal(2)
    end)

    it("else_ runs when no case matches", function()
        local ir = fresh()
        local node = ir.compile(ir.switch({
            on = ir.path("$.ctx.color"),
            cases = {
                { match = ir.lit("red"), body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
            },
            else_ = ir["let"]({ at = "ctx.r", value = ir.lit(99) }),
        }))
        local ctx = ir.exec(node, { color = "green" }, {})
        expect(ctx.r).to.equal(99)
    end)

    it("no-op when no case matches and no else_", function()
        local ir = fresh()
        local node = ir.compile(ir.switch({
            on = ir.path("$.ctx.color"),
            cases = {
                { match = ir.lit("red"), body = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
            },
        }))
        local ctx = ir.exec(node, { color = "green" }, {})
        expect(ctx.r).to.equal(nil)
    end)
end)

-- ── try ─────────────────────────────────────────────────────────────

describe("flow.ir try exec", function()
    it("runs body normally when no error", function()
        local ir = fresh()
        local node = ir.compile(ir["try"]({
            body  = ir["let"]({ at = "ctx.r", value = ir.lit(1) }),
            catch = ir["let"]({ at = "ctx.r", value = ir.lit(-1) }),
        }))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.r).to.equal(1)
    end)

    it("runs catch on raise and writes err_at", function()
        local ir = fresh()
        local node = ir.compile(ir["try"]({
            body  = ir["fail"]({ message = ir.lit("boom") }),
            catch = ir["let"]({ at = "ctx.handled", value = ir.lit(true) }),
            err_at = "ctx.err",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.handled).to.equal(true)
        expect(tostring(ctx.err):find("boom")).to_not.equal(nil)
    end)

    it("does NOT catch return_early sentinel (rethrows to exec)", function()
        local ir = fresh()
        local node = ir.compile(ir["try"]({
            body  = ir.return_early({ out = "ctx.r", value = ir.lit(42) }),
            catch = ir["let"]({ at = "ctx.handled", value = ir.lit(true) }),
        }))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.r).to.equal(42)
        expect(ctx.handled).to.equal(nil)
    end)
end)

-- ── return_early ────────────────────────────────────────────────────

describe("flow.ir return_early exec", function()
    it("writes value to out and unwinds", function()
        local ir = fresh()
        local node = ir.compile(ir.seq(
            ir["let"]({ at = "ctx.before", value = ir.lit(1) }),
            ir.return_early({ out = "ctx.r", value = ir.lit("done") }),
            ir["let"]({ at = "ctx.after", value = ir.lit(2) })
        ))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.before).to.equal(1)
        expect(ctx.r).to.equal("done")
        expect(ctx.after).to.equal(nil)
    end)

    it("unwinds without out/value", function()
        local ir = fresh()
        local node = ir.compile(ir.seq(
            ir["let"]({ at = "ctx.before", value = ir.lit(1) }),
            ir.return_early({}),
            ir["let"]({ at = "ctx.after", value = ir.lit(2) })
        ))
        local ctx = ir.exec(node, {}, {})
        expect(ctx.before).to.equal(1)
        expect(ctx.after).to.equal(nil)
    end)

    it("rejects asymmetric out/value at compile", function()
        local ir = fresh()
        local node = { kind = "return_early", out = "ctx.r" }  -- missing value
        local ok, reason = ir.compile(node)
        expect(ok).to.equal(nil)
        expect(reason:find("both present or both absent")).to_not.equal(nil)
    end)
end)

-- ── walk ────────────────────────────────────────────────────────────

describe("flow.ir walk switch/try", function()
    it("switch children_of yields case bodies + else_", function()
        local ir = fresh()
        local b1 = ir["let"]({ at = "ctx.x", value = ir.lit(1) })
        local b2 = ir["let"]({ at = "ctx.x", value = ir.lit(2) })
        local elsebody = ir["let"]({ at = "ctx.x", value = ir.lit(99) })
        local node = ir.switch({
            on = ir.path("$.ctx.k"),
            cases = { { match = ir.lit("a"), body = b1 }, { match = ir.lit("b"), body = b2 } },
            else_ = elsebody,
        })
        local children = ir.children_of(node)
        expect(#children).to.equal(3)
        expect(children[1].child).to.equal(b1)
        expect(children[2].child).to.equal(b2)
        expect(children[3].child).to.equal(elsebody)
    end)

    it("try children_of yields body + catch", function()
        local ir = fresh()
        local b = ir["let"]({ at = "ctx.x", value = ir.lit(1) })
        local c = ir["let"]({ at = "ctx.x", value = ir.lit(2) })
        local node = ir["try"]({ body = b, catch = c })
        local children = ir.children_of(node)
        expect(#children).to.equal(2)
        expect(children[1].child).to.equal(b)
        expect(children[2].child).to.equal(c)
    end)

    it("refs_of walks switch.on and case.match", function()
        local ir = fresh()
        local node = ir.switch({
            on = ir.path("$.ctx.color"),
            cases = {
                { match = ir.path("$.ctx.target"),
                  body  = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
            },
        })
        local refs = ir.refs_of(node)
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("$.ctx.color")
        expect(refs[2]).to.equal("$.ctx.target")
    end)
end)
