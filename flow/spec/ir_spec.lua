--- Tests for flow.ir (Flow IR Def + interpreter).
---
--- MVP coverage:
---   - schema validation (6 cases: 3 reject + 3 accept)
---   - interpreter execution (4 cases: step/seq/branch/multi-stage)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- See flow/spec/flow_spec.lua for the rationale of deriving REPO from
-- package.path rather than os.getenv("PWD") — same constraint applies
-- under mlua-probe-mcp.
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

-- ── helpers ─────────────────────────────────────────────────────────

local function path(at) return { op = "path", at = at } end
local function lit(v)   return { op = "lit",  value = v } end
local function eq(l, r) return { op = "eq",   lhs = l, rhs = r } end
local function andx(...) return { op = "and", args = { ... } } end
local function notx(e) return { op = "not",  arg = e } end
local function lt(l, r) return { op = "lt",   lhs = l, rhs = r } end

local function step(ref, out, in_)
    return { kind = "step", ref = ref, out = out, in_ = in_ }
end
local function seq(...)
    return { kind = "seq", children = { ... } }
end
local function branch(cond, t, e)
    return { kind = "branch", cond = cond, then_ = t, else_ = e }
end
local function letx(at, value)
    return { kind = "let", at = at, value = value }
end
local function loopx(cond, body, max, counter)
    return { kind = "loop", cond = cond, body = body, max = max, counter = counter }
end
local function callx(flow_name, args, out)
    return { kind = "call", flow = flow_name, args = args, out = out }
end

-- recording dispatcher: returns { ref = N } where N = ordinal call index
local function make_recorder()
    local log, n = {}, 0
    return function(ref, input)
        n = n + 1
        log[#log + 1] = { ref = ref, input = input, n = n }
        return { ref = ref, n = n }
    end, log
end

-- ── compile / schema ────────────────────────────────────────────────

describe("flow.ir.compile", function()
    it("accepts a minimal step", function()
        local ok = compile(step("a", "ctx.x"))
        expect(ok).to.exist()
    end)

    it("accepts a seq of steps", function()
        local ok = compile(seq(
            step("a", "ctx.x"),
            step("b", "ctx.y")
        ))
        expect(ok).to.exist()
    end)

    it("accepts a branch with an eq cond", function()
        local ok = compile(branch(
            eq(path("$.ctx.status"), lit("ok")),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        expect(ok).to.exist()
    end)

    it("rejects an unknown Node kind", function()
        local ok, reason = compile({ kind = "no_such_kind", body = step("a", "ctx.x") })
        expect(ok).to.equal(nil)
        expect(reason:find("unknown Node kind")).to.exist()
    end)

    it("rejects an unknown Expr op (nested under branch.cond)", function()
        local ok, reason = compile(branch(
            { op = "not_yet_supported", arg = lit(true) },
            step("a", "ctx.a"),
            step("b", "ctx.b")
        ))
        expect(ok).to.equal(nil)
        expect(reason:find("unknown Expr op")).to.exist()
    end)

    it("rejects step.out without the 'ctx.' prefix", function()
        local ok, reason = compile(step("a", "missing_prefix"))
        expect(ok).to.equal(nil)
        expect(reason:find("ctx%.")).to.exist()
    end)

    it("accepts an `and` Expr with >= 2 args", function()
        local ok = compile(branch(
            andx(eq(lit(1), lit(1)), eq(lit(2), lit(2))),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        expect(ok).to.exist()
    end)

    it("rejects an `and` Expr with < 2 args", function()
        local ok, reason = compile(branch(
            andx(eq(lit(1), lit(1))),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        expect(ok).to.equal(nil)
        expect(reason:find("requires >= 2 args")).to.exist()
    end)

    it("accepts `not` and `lt` Exprs (nested in branch.cond)", function()
        local ok = compile(branch(
            notx(lt(lit(1), lit(2))),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        expect(ok).to.exist()
    end)

    it("rejects let.at without 'ctx.' prefix", function()
        local ok, reason = compile(letx("flag", lit(true)))
        expect(ok).to.equal(nil)
        expect(reason:find("ctx%.")).to.exist()
    end)

    it("rejects loop without `max`", function()
        local ok, reason = compile(loopx(lit(true), letx("ctx.x", lit(1)), nil, "ctx.i"))
        expect(ok).to.equal(nil)
        expect(reason:find("max")).to.exist()
    end)

    it("rejects nested loop sharing counter path", function()
        local inner = loopx(lit(true), letx("ctx.x", lit(1)), 3, "ctx.i")
        local outer = loopx(lit(true), inner, 3, "ctx.i")
        local ok, reason = compile(outer)
        expect(ok).to.equal(nil)
        expect(reason:find("nested loop reuses counter")).to.exist()
    end)

    it("rejects call.flow not in eager registry", function()
        local ok, reason = compile(
            callx("missing", {}, "ctx.out"),
            { flows = { other = true } }
        )
        expect(ok).to.equal(nil)
        expect(reason:find("not in opts.flows registry")).to.exist()
    end)
end)

-- ── interpreter ─────────────────────────────────────────────────────

describe("flow.ir.exec", function()
    it("runs a single step and writes the out path", function()
        local compiled = compile(step("a", "ctx.x"))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(ctx.x.ref).to.equal("a")
        expect(#log).to.equal(1)
    end)

    it("runs a seq in order", function()
        local compiled = compile(seq(
            step("a", "ctx.x"),
            step("b", "ctx.y")
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(log[1].ref).to.equal("a")
        expect(log[2].ref).to.equal("b")
        expect(ctx.x.n).to.equal(1)
        expect(ctx.y.n).to.equal(2)
    end)

    it("branches on eq(path, lit)", function()
        local compiled = compile(branch(
            eq(path("$.ctx.status"), lit("ok")),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, { status = "ok" }, { dispatch = disp })
        expect(log[1].ref).to.equal("a")
        expect(ctx.done).to.exist()
        expect(ctx.retry).to.equal(nil)
    end)

    it("`and` evaluates short-circuit; first falsy returns false", function()
        local compiled = compile(branch(
            andx(
                eq(path("$.ctx.flag"), lit("ok")),
                eq(path("$.ctx.flag"), lit("ok"))
            ),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        local disp, log = make_recorder()
        -- ctx.flag is missing -> path returns nil -> eq returns false
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(log[1].ref).to.equal("b")
        expect(ctx.retry).to.exist()
        expect(ctx.done).to.equal(nil)
    end)

    it("`and` with 3 truthy args runs the then branch", function()
        local compiled = compile(branch(
            andx(lit(1), lit("x"), lit(true)),
            step("a", "ctx.done"),
            step("b", "ctx.retry")
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(log[1].ref).to.equal("a")
        expect(ctx.done).to.exist()
        expect(ctx.retry).to.equal(nil)
    end)

    it("`not` inverts truthiness (nil -> true, truthy -> false)", function()
        local compiled = compile(seq(
            branch(
                notx(path("$.ctx.absent")),
                step("a", "ctx.t1"),
                step("b", "ctx.f1")
            ),
            branch(
                notx(lit(true)),
                step("c", "ctx.t2"),
                step("d", "ctx.f2")
            )
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(log[1].ref).to.equal("a")
        expect(log[2].ref).to.equal("d")
        expect(ctx.t1).to.exist()
        expect(ctx.f1).to.equal(nil)
        expect(ctx.t2).to.equal(nil)
        expect(ctx.f2).to.exist()
    end)

    it("`lt` compares numbers and strings (lexicographic)", function()
        local compiled = compile(seq(
            branch(
                lt(lit(3), lit(5)),
                step("a", "ctx.num_lt"),
                step("b", "ctx.num_ge")
            ),
            branch(
                lt(lit("a"), lit("b")),
                step("c", "ctx.str_lt"),
                step("d", "ctx.str_ge")
            ),
            branch(
                lt(lit(5), lit(3)),
                step("e", "ctx.bad_lt"),
                step("f", "ctx.bad_ge")
            )
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(log[1].ref).to.equal("a")
        expect(log[2].ref).to.equal("c")
        expect(log[3].ref).to.equal("f")
        expect(ctx.num_lt).to.exist()
        expect(ctx.str_lt).to.exist()
        expect(ctx.bad_ge).to.exist()
    end)

    it("`let` binds a literal Expr to ctx", function()
        local compiled = compile(letx("ctx.greeting", lit("hi")))
        local ctx = exec(compiled, {})
        expect(ctx.greeting).to.equal("hi")
    end)

    it("`let` binds a computed Expr (eq → boolean)", function()
        local compiled = compile(letx("ctx.match", eq(lit(3), lit(3))))
        local ctx = exec(compiled, {})
        expect(ctx.match).to.equal(true)
    end)

    it("`loop` runs zero times when cond is false on first check", function()
        local compiled = compile(loopx(
            lit(false),
            letx("ctx.touched", lit(true)),
            5,
            "ctx.i"
        ))
        local ctx = exec(compiled, {})
        expect(ctx.i).to.equal(0)
        expect(ctx.touched).to.equal(nil)
    end)

    it("`loop` increments counter and exits when cond goes false", function()
        local compiled = compile(loopx(
            lt(path("$.ctx.i"), lit(3)),
            letx("ctx.touched", path("$.ctx.i")),
            5,
            "ctx.i"
        ))
        local ctx = exec(compiled, {})
        expect(ctx.i).to.equal(3)
        expect(ctx.touched).to.equal(3)
    end)

    it("`loop.max` guards an always-truthy cond", function()
        local compiled = compile(loopx(
            lit(true),
            letx("ctx.touched", path("$.ctx.i")),
            4,
            "ctx.i"
        ))
        local ctx = exec(compiled, {})
        expect(ctx.i).to.equal(4)
        expect(ctx.touched).to.equal(4)
    end)

    it("`call` invokes a sub-flow and merges sub-ctx under out", function()
        local sub_flow = compile(seq(
            letx("ctx.echo", path("$.ctx.x")),
            step("a", "ctx.result")
        ))
        local main = compile(callx("sub", { x = lit(42) }, "ctx.out"))
        local disp, log = make_recorder()
        local ctx = exec(main, {}, { dispatch = disp, flows = { sub = sub_flow } })
        expect(ctx.out.echo).to.equal(42)
        expect(ctx.out.result.ref).to.equal("a")
        expect(ctx.out.x).to.equal(42)
        expect(#log).to.equal(1)
    end)

    it("`call` raises on unknown flow at exec time (lazy mode)", function()
        local main = compile(callx("missing", {}, "ctx.out"))
        local ok, ex_err = pcall(function()
            exec(main, {}, { flows = {} })
        end)
        expect(ok).to.equal(false)
        expect(tostring(ex_err):find("not registered")).to.exist()
    end)

    it("`call` enforces max_call_depth on recursion", function()
        local rec = compile(callx("rec", {}, "ctx.r"))
        local ok, ex_err = pcall(function()
            exec(rec, {}, { flows = { rec = rec }, max_call_depth = 3 })
        end)
        expect(ok).to.equal(false)
        expect(tostring(ex_err):find("max_call_depth")).to.exist()
    end)

    it("runs a multi-stage IR (seq → seq → branch on a prior step's output)", function()
        local compiled = compile(seq(
            step("a", "ctx.x"),
            step("b", "ctx.y"),
            -- the recorder stub writes { ref = ..., n = ... } so the
            -- branch reads ctx.y.ref to verify a real path read can
            -- drive the decision.
            branch(
                eq(path("$.ctx.y.ref"), lit("b")),
                step("c", "ctx.done"),
                step("d", "ctx.retry")
            )
        ))
        local disp, log = make_recorder()
        local ctx = exec(compiled, {}, { dispatch = disp })
        expect(#log).to.equal(3)
        expect(log[3].ref).to.equal("c")
        expect(ctx.done).to.exist()
        expect(ctx.retry).to.equal(nil)
    end)
end)
