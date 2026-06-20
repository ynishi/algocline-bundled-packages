--- Nested control-flow composition for flow.ir (map × switch × try ×
--- return_early). The per-axis specs (ir_map_reduce_spec /
--- ir_switch_try_return_spec / ir_once_spec etc.) cover each Node in
--- isolation; this spec covers the *interaction* — body-of-X holds a
--- Y holds a Z — which is where compile-time walk dispatch, exec-time
--- scope propagation, and the return_early sentinel unwind can drift
--- independently of the per-axis happy paths.
---
--- Scenarios covered:
---   1. map body contains a switch (per-item branching, results collected)
---   2. map body contains a try that catches a fail (per-iteration rescue)
---   3. switch case body contains a map (case body is a sub-pipeline)
---   4. reduce body contains a switch (accumulator updated by per-item case)
---   5. return_early inside seq(map, after_step) unwinds past the
---      tail step (sanity: the existing return_early/seq test pattern
---      still holds when the leading step is a map, not a let).

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

-- ── 1. map body contains a switch ───────────────────────────────────

describe("flow.ir nested: map body × switch", function()
    it("per-item switch produces different collected values", function()
        local ir = fresh()
        local node = ir.compile(ir.map({
            in_ = ir.lit({ "red", "blue", "green" }),
            bind = "ctx.it",
            body = ir.switch({
                on = ir.path("$.ctx.it"),
                cases = {
                    { match = ir.lit("red"),
                      body  = ir["let"]({ at = "ctx.r", value = ir.lit(1) }) },
                    { match = ir.lit("blue"),
                      body  = ir["let"]({ at = "ctx.r", value = ir.lit(2) }) },
                },
                else_ = ir["let"]({ at = "ctx.r", value = ir.lit(99) }),
            }),
            collect = "ctx.r",
            out = "ctx.codes",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(#ctx.codes).to.equal(3)
        expect(ctx.codes[1]).to.equal(1)
        expect(ctx.codes[2]).to.equal(2)
        expect(ctx.codes[3]).to.equal(99)
    end)
end)

-- ── 2. map body contains a try that catches a fail ──────────────────

describe("flow.ir nested: map body × try × fail", function()
    it("per-iteration fail is caught and a sentinel is collected", function()
        local ir = fresh()
        -- For each item, run a switch: if it == "bad" then fail, else let r = it.
        -- Wrap that in try with a catch that sets r = -1.
        local node = ir.compile(ir.map({
            in_ = ir.lit({ "a", "bad", "c" }),
            bind = "ctx.it",
            body = ir["try"]({
                body = ir.switch({
                    on = ir.path("$.ctx.it"),
                    cases = {
                        { match = ir.lit("bad"),
                          body  = ir["fail"]({ message = ir.lit("boom") }) },
                    },
                    else_ = ir["let"]({ at = "ctx.r", value = ir.path("$.ctx.it") }),
                }),
                catch = ir["let"]({ at = "ctx.r", value = ir.lit("-1") }),
            }),
            collect = "ctx.r",
            out = "ctx.values",
        }))
        local ctx = ir.exec(node, {}, {})
        expect(#ctx.values).to.equal(3)
        expect(ctx.values[1]).to.equal("a")
        expect(ctx.values[2]).to.equal("-1")
        expect(ctx.values[3]).to.equal("c")
    end)
end)

-- ── 3. switch case body contains a map ──────────────────────────────

describe("flow.ir nested: switch case body × map", function()
    it("matching case runs a map and writes its out", function()
        local ir = fresh()
        local node = ir.compile(ir.switch({
            on = ir.path("$.ctx.mode"),
            cases = {
                { match = ir.lit("double"),
                  body  = ir.map({
                      in_ = ir.lit({ 1, 2, 3 }),
                      bind = "ctx.it",
                      body = ir["let"]({
                          at = "ctx.r",
                          value = ir.mul(ir.path("$.ctx.it"), ir.lit(2)),
                      }),
                      collect = "ctx.r",
                      out = "ctx.doubled",
                  }) },
            },
            else_ = ir["let"]({ at = "ctx.doubled", value = ir.lit({}) }),
        }))
        local ctx = ir.exec(node, { mode = "double" }, {})
        expect(#ctx.doubled).to.equal(3)
        expect(ctx.doubled[1]).to.equal(2)
        expect(ctx.doubled[2]).to.equal(4)
        expect(ctx.doubled[3]).to.equal(6)
    end)
end)

-- ── 4. reduce body contains a switch ────────────────────────────────

describe("flow.ir nested: reduce body × switch", function()
    it("per-item switch decides increment magnitude", function()
        local ir = fresh()
        -- Items are color tags; sum +1 for red, +10 for blue, +0 otherwise.
        local node = ir.compile(ir.reduce({
            in_ = ir.lit({ "red", "blue", "green", "red" }),
            init = ir.lit(0),
            acc = "ctx.sum",
            bind = "ctx.it",
            body = ir.switch({
                on = ir.path("$.ctx.it"),
                cases = {
                    { match = ir.lit("red"),
                      body  = ir["let"]({
                          at = "ctx.sum",
                          value = ir.add(ir.path("$.ctx.sum"), ir.lit(1)),
                      }) },
                    { match = ir.lit("blue"),
                      body  = ir["let"]({
                          at = "ctx.sum",
                          value = ir.add(ir.path("$.ctx.sum"), ir.lit(10)),
                      }) },
                },
                -- no else_: green is a no-op
            }),
            out = "ctx.total",
        }))
        local ctx = ir.exec(node, {}, {})
        -- 1 (red) + 10 (blue) + 0 (green) + 1 (red) = 12
        expect(ctx.total).to.equal(12)
    end)
end)

-- ── 5. return_early inside seq(map, after_step) ─────────────────────

describe("flow.ir nested: seq × map then return_early skips tail", function()
    it("return_early after the map unwinds past the tail step", function()
        local ir = fresh()
        local node = ir.compile(ir.seq(
            ir.map({
                in_ = ir.lit({ 1, 2, 3 }),
                bind = "ctx.it",
                body = ir["let"]({
                    at = "ctx.r",
                    value = ir.mul(ir.path("$.ctx.it"), ir.lit(10)),
                }),
                collect = "ctx.r",
                out = "ctx.tens",
            }),
            ir.return_early({ out = "ctx.early", value = ir.lit("yes") }),
            ir["let"]({ at = "ctx.after", value = ir.lit("should-not-run") })
        ))
        local ctx = ir.exec(node, {}, {})
        expect(#ctx.tens).to.equal(3)
        expect(ctx.tens[3]).to.equal(30)
        expect(ctx.early).to.equal("yes")
        expect(ctx.after).to.equal(nil)
    end)
end)

-- ── walk: nested children_of descends both layers ───────────────────

describe("flow.ir nested: walk descends through composed nodes", function()
    it("ir.walk visits both outer map body and inner switch case bodies", function()
        local ir = fresh()
        local inner_red = ir["let"]({ at = "ctx.r", value = ir.lit(1) })
        local inner_else = ir["let"]({ at = "ctx.r", value = ir.lit(99) })
        local sw = ir.switch({
            on = ir.path("$.ctx.it"),
            cases = { { match = ir.lit("red"), body = inner_red } },
            else_ = inner_else,
        })
        local node = ir.map({
            in_ = ir.lit({ "red" }),
            bind = "ctx.it",
            body = sw,
            collect = "ctx.r",
            out = "ctx.o",
        })
        local seen = {}
        ir.walk(node, function(n) seen[n] = true end)
        expect(seen[node]).to.equal(true)
        expect(seen[sw]).to.equal(true)
        expect(seen[inner_red]).to.equal(true)
        expect(seen[inner_else]).to.equal(true)
    end)
end)
