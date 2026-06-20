--- Tests for the Introspect API (Step 3 §3.A).
---
--- Covers the four public functions:
---   - flow.ir.walk     — visitor contract (depth/parent/path, control)
---   - flow.ir.type_of  — node.kind retrieval
---   - flow.ir.children_of — child enumeration with accessor keys
---   - flow.ir.refs_of  — all path.at strings reachable from a subtree
---
--- The visitor signature is the public §3.A contract and is frozen:
---   visitor(node, ctx) -> nil | "skip" | "stop"
---   ctx = { depth, parent, path }
--- These tests pin that contract.

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

-- ── type_of ─────────────────────────────────────────────────────────

describe("flow.ir.type_of", function()
    it("returns the kind of every Node kind", function()
        expect(ir.type_of(ir.step({ ref = "a", out = "ctx.a" }))).to.equal("step")
        expect(ir.type_of(ir.seq())).to.equal("seq")
        expect(ir.type_of(ir.branch({
            cond = ir.lit(true),
            then_ = ir.step({ ref = "t", out = "ctx.t" }),
        }))).to.equal("branch")
        expect(ir.type_of(ir["let"]({ at = "ctx.x", value = ir.lit(1) })))
            .to.equal("let")
        expect(ir.type_of(ir.loop({
            cond = ir.lit(true),
            body = ir.step({ ref = "b", out = "ctx.b" }),
            max = 1, counter = "ctx.i",
        }))).to.equal("loop")
        expect(ir.type_of(ir.call({
            flow = "f", args = {}, out = "ctx.r",
        }))).to.equal("call")
        expect(ir.type_of(ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body = ir.step({ ref = "b", out = "ctx.b" }),
            join = "all", out = "ctx.r",
        }))).to.equal("fanout")
    end)
end)

-- ── children_of ─────────────────────────────────────────────────────

describe("flow.ir.children_of", function()
    it("returns {} for leaf Node kinds (step / let / call)", function()
        expect(#ir.children_of(ir.step({ ref = "a", out = "ctx.a" }))).to.equal(0)
        expect(#ir.children_of(ir["let"]({ at = "ctx.x", value = ir.lit(1) })))
            .to.equal(0)
        expect(#ir.children_of(ir.call({ flow = "f", args = {}, out = "ctx.r" })))
            .to.equal(0)
    end)

    it("seq emits children with key='children' and idx=i", function()
        local a = ir.step({ ref = "a", out = "ctx.a" })
        local b = ir.step({ ref = "b", out = "ctx.b" })
        local kids = ir.children_of(ir.seq(a, b))
        expect(#kids).to.equal(2)
        expect(kids[1].child).to.equal(a)
        expect(kids[1].key).to.equal("children")
        expect(kids[1].idx).to.equal(1)
        expect(kids[2].child).to.equal(b)
        expect(kids[2].idx).to.equal(2)
    end)

    it("branch emits then_ and (when present) else_", function()
        local t = ir.step({ ref = "t", out = "ctx.t" })
        local e = ir.step({ ref = "e", out = "ctx.e" })
        local with_else = ir.branch({ cond = ir.lit(true), then_ = t, else_ = e })
        local kids = ir.children_of(with_else)
        expect(#kids).to.equal(2)
        expect(kids[1].child).to.equal(t)
        expect(kids[1].key).to.equal("then_")
        expect(kids[2].child).to.equal(e)
        expect(kids[2].key).to.equal("else_")

        local no_else = ir.branch({ cond = ir.lit(true), then_ = t })
        expect(#ir.children_of(no_else)).to.equal(1)
    end)

    it("loop / fanout emit body", function()
        local body = ir.step({ ref = "b", out = "ctx.b" })
        local loop_kids = ir.children_of(ir.loop({
            cond = ir.lit(true), body = body, max = 1, counter = "ctx.i",
        }))
        expect(#loop_kids).to.equal(1)
        expect(loop_kids[1].child).to.equal(body)
        expect(loop_kids[1].key).to.equal("body")

        local fanout_kids = ir.children_of(ir.fanout({
            items = ir.lit({}), bind = "ctx.it",
            body = body, join = "all", out = "ctx.r",
        }))
        expect(#fanout_kids).to.equal(1)
        expect(fanout_kids[1].child).to.equal(body)
        expect(fanout_kids[1].key).to.equal("body")
    end)
end)

-- ── walk ────────────────────────────────────────────────────────────

describe("flow.ir.walk", function()
    it("visits root first, then descends pre-order", function()
        local a = ir.step({ ref = "a", out = "ctx.a" })
        local b = ir.step({ ref = "b", out = "ctx.b" })
        local root = ir.seq(a, b)
        local kinds = {}
        ir.walk(root, function(node, _ctx)
            kinds[#kinds + 1] = node.kind .. "/" .. (node.ref or "")
        end)
        -- pre-order: root (seq), then children left-to-right
        expect(#kinds).to.equal(3)
        expect(kinds[1]).to.equal("seq/")
        expect(kinds[2]).to.equal("step/a")
        expect(kinds[3]).to.equal("step/b")
    end)

    it("ctx carries depth / parent / path", function()
        local inner = ir.step({ ref = "i", out = "ctx.i" })
        local mid = ir.branch({ cond = ir.lit(true), then_ = inner })
        local root = ir.seq(mid)

        local seen = {}
        ir.walk(root, function(node, ctx)
            seen[#seen + 1] = {
                kind = node.kind,
                depth = ctx.depth,
                parent_kind = ctx.parent and ctx.parent.kind or nil,
                path = ctx.path,
            }
        end)
        expect(#seen).to.equal(3)

        -- root
        expect(seen[1].kind).to.equal("seq")
        expect(seen[1].depth).to.equal(0)
        expect(seen[1].parent_kind).to.equal(nil)
        expect(#seen[1].path).to.equal(0)

        -- seq.children[1] → mid (branch)
        expect(seen[2].kind).to.equal("branch")
        expect(seen[2].depth).to.equal(1)
        expect(seen[2].parent_kind).to.equal("seq")
        expect(seen[2].path[1]).to.equal("children")
        expect(seen[2].path[2]).to.equal(1)

        -- branch.then_ → inner (step)
        expect(seen[3].kind).to.equal("step")
        expect(seen[3].depth).to.equal(2)
        expect(seen[3].parent_kind).to.equal("branch")
        expect(seen[3].path[1]).to.equal("children")
        expect(seen[3].path[2]).to.equal(1)
        expect(seen[3].path[3]).to.equal("then_")
    end)

    it("visitor returning 'skip' prunes the subtree", function()
        local inner = ir.step({ ref = "i", out = "ctx.i" })
        local root = ir.seq(
            ir.branch({ cond = ir.lit(true), then_ = inner }),
            ir.step({ ref = "tail", out = "ctx.t" })
        )
        local kinds = {}
        ir.walk(root, function(node, _ctx)
            kinds[#kinds + 1] = node.kind .. "/" .. (node.ref or "")
            if node.kind == "branch" then return "skip" end
        end)
        -- expected: seq, branch (skipped → no descent to inner), tail step
        expect(#kinds).to.equal(3)
        expect(kinds[1]).to.equal("seq/")
        expect(kinds[2]).to.equal("branch/")
        expect(kinds[3]).to.equal("step/tail")
    end)

    it("visitor returning 'stop' aborts the entire walk", function()
        local root = ir.seq(
            ir.step({ ref = "a", out = "ctx.a" }),
            ir.step({ ref = "b", out = "ctx.b" }),
            ir.step({ ref = "c", out = "ctx.c" })
        )
        local refs = {}
        local rv = ir.walk(root, function(node, _ctx)
            if node.kind == "step" then
                refs[#refs + 1] = node.ref
                if node.ref == "b" then return "stop" end
            end
        end)
        expect(rv).to.equal("stop")
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("a")
        expect(refs[2]).to.equal("b")
    end)

    it("returns nil when the visitor never stops", function()
        local root = ir.step({ ref = "a", out = "ctx.a" })
        local rv = ir.walk(root, function() end)
        expect(rv).to.equal(nil)
    end)
end)

-- ── refs_of ─────────────────────────────────────────────────────────

describe("flow.ir.refs_of", function()
    it("returns {} for subtrees with no `path` Expr", function()
        expect(#ir.refs_of(ir.lit(1))).to.equal(0)
        expect(#ir.refs_of(ir.step({ ref = "a", out = "ctx.a" }))).to.equal(0)
    end)

    it("collects path.at from a single Expr", function()
        local e = ir.path("$.ctx.foo")
        local refs = ir.refs_of(e)
        expect(#refs).to.equal(1)
        expect(refs[1]).to.equal("$.ctx.foo")
    end)

    it("walks into nested Expr ops", function()
        local e = ir["and"](
            ir.eq(ir.path("$.ctx.a"), ir.lit(1)),
            ir["not"](ir.path("$.ctx.b"))
        )
        local refs = ir.refs_of(e)
        expect(#refs).to.equal(2)
        expect(refs[1]).to.equal("$.ctx.a")
        expect(refs[2]).to.equal("$.ctx.b")
    end)

    it("walks Node tree + Expr fields together", function()
        local root = ir.seq(
            ir["let"]({ at = "ctx.x", value = ir.path("$.ctx.src") }),
            ir.branch({
                cond  = ir.eq(ir.path("$.ctx.x"), ir.lit(0)),
                then_ = ir.step({
                    ref = "h", out = "ctx.r",
                    in_ = ir.path("$.ctx.x"),
                }),
            })
        )
        local refs = ir.refs_of(root)
        -- expected: let.value (src), branch.cond.lhs (x), step.in_ (x)
        expect(#refs).to.equal(3)
        expect(refs[1]).to.equal("$.ctx.src")
        expect(refs[2]).to.equal("$.ctx.x")
        expect(refs[3]).to.equal("$.ctx.x")
    end)

    it("includes call.args and fanout.items / body refs", function()
        local sub = ir.step({
            ref = "h", out = "ctx.r",
            in_ = ir.path("$.ctx.item"),
        })
        local root = ir.seq(
            ir.call({
                flow = "f",
                args = { x = ir.path("$.ctx.a") },
                out  = "ctx.c",
            }),
            ir.fanout({
                items = ir.path("$.ctx.list"),
                bind  = "ctx.item",
                body  = sub,
                join  = "all",
                out   = "ctx.r",
            })
        )
        local refs = ir.refs_of(root)
        expect(#refs).to.equal(3)
        -- order: call.args.x, fanout.items, fanout.body's step.in_
        local set = {}
        for _, r in ipairs(refs) do set[r] = (set[r] or 0) + 1 end
        expect(set["$.ctx.a"]).to.equal(1)
        expect(set["$.ctx.list"]).to.equal(1)
        expect(set["$.ctx.item"]).to.equal(1)
    end)
end)
