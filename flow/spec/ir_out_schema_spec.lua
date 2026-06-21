--- Tests for flow.ir step.out_schema / wrap_step.out_schema:
--- Schema-as-Data dispatcher contract.
---
--- Covers (a) legacy path — out_schema absent, any result accepted
--- (back-compat with all pre-D1 spec); (b) strict happy path — declared
--- shape matches, IR Expr can path into structured ctx; (c) strict reject
--- — dispatcher returns malformed value, exec raises with slot-tagged
--- message; (d) wrap_step on_mismatch path bypasses out_schema (caller
--- handles the verify-fail result directly).

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

local ir      = require("flow.ir")
local compile = ir.compile
local exec    = ir.exec
local T       = require("alc_shapes.t")

local VERDICT_SCHEMA = T.shape({
    status  = T.one_of({ "pass", "fail", "abstain" }),
    payload = T.table:is_optional(),
    reason  = T.string:is_optional(),
}, { open = false })

local function dispatch_const(result)
    return function(_ref, _input) return result end
end

-- ── (a) legacy: out_schema absent ──────────────────────────────────

describe("flow.ir step: legacy path (out_schema absent)", function()
    it("accepts any string result (back-compat with pre-D1 step)", function()
        local def = ir.step({ ref = "gate", out = "ctx.r" })
        local ctx = exec(def, {}, { dispatch = dispatch_const("DONE path=alpha") })
        expect(ctx.r).to.equal("DONE path=alpha")
    end)

    it("accepts table result without schema check", function()
        local def = ir.step({ ref = "gate", out = "ctx.r" })
        local ctx = exec(def, {}, {
            dispatch = dispatch_const({ status = "pass" }),
        })
        expect(ctx.r.status).to.equal("pass")
    end)
end)

-- ── (b) strict happy path: out_schema matches ──────────────────────

describe("flow.ir step: out_schema strict happy path", function()
    it("accepts a result matching the declared shape", function()
        local def = ir.step({
            ref        = "verdict_gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        local ctx = exec(def, {}, {
            dispatch = dispatch_const({ status = "pass", reason = "ok" }),
        })
        expect(ctx.verdict.status).to.equal("pass")
        expect(ctx.verdict.reason).to.equal("ok")
    end)

    it("downstream Expr can path into structured ctx (routing-as-Data)", function()
        local def = ir.seq(
            ir.step({
                ref        = "verdict_gate",
                out        = "ctx.verdict",
                out_schema = VERDICT_SCHEMA,
            }),
            ir.branch({
                cond  = ir.eq(ir.path("$.ctx.verdict.status"), ir.lit("pass")),
                then_ = { kind = "let", at = "ctx.took", value = ir.lit("then") },
                else_ = { kind = "let", at = "ctx.took", value = ir.lit("else") },
            })
        )
        local ctx = exec(def, {}, { dispatch = dispatch_const({ status = "pass" }) })
        expect(ctx.took).to.equal("then")
    end)

    it("compile passes when out_schema is a valid alc_shapes T value", function()
        local def = ir.step({
            ref        = "gate",
            out        = "ctx.r",
            out_schema = VERDICT_SCHEMA,
        })
        local compiled, reason = compile(def)
        expect(reason).to.equal(nil)
        expect(compiled).to.equal(def)
    end)
end)

-- ── (c) strict reject: shape mismatch ──────────────────────────────

describe("flow.ir step: out_schema strict reject", function()
    it("raises when dispatcher returns a non-table (shape mismatch)", function()
        local def = ir.step({
            ref        = "verdict_gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        expect(function()
            exec(def, {}, { dispatch = dispatch_const("DONE") })
        end).to.fail()
    end)

    it("raises when result table is missing a required field", function()
        local def = ir.step({
            ref        = "verdict_gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        expect(function()
            exec(def, {}, { dispatch = dispatch_const({ reason = "no status" }) })
        end).to.fail()
    end)

    it("raises when an enum field has an unknown value", function()
        local def = ir.step({
            ref        = "verdict_gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        expect(function()
            exec(def, {}, { dispatch = dispatch_const({ status = "unknown" }) })
        end).to.fail()
    end)

    it("error message names the step ref + 'out_schema mismatch'", function()
        local def = ir.step({
            ref        = "verdict_gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        local ok, err = pcall(exec, def, {}, {
            dispatch = dispatch_const("DONE"),
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("step 'verdict_gate'")).to.exist()
        expect(tostring(err):find("out_schema mismatch")).to.exist()
    end)
end)

-- ── compile-time shape check ───────────────────────────────────────

describe("flow.ir step: out_schema compile-time shape check", function()
    it("rejects out_schema of wrong type (non-table)", function()
        -- Raw IR Def: out_schema must be a table when present
        -- (alc_shapes T.table:is_optional() in the discriminated schema).
        local def = {
            kind       = "step",
            ref        = "gate",
            out        = "ctx.r",
            out_schema = "not a table",
        }
        local _, reason = compile(def)
        expect(reason ~= nil).to.equal(true)
    end)
end)

-- ── wrap_step: out_schema on verify-success path ───────────────────

describe("flow.ir wrap_step: out_schema strict (verify success)", function()
    it("accepts result matching the schema after verify succeeds", function()
        local def = ir.wrap_step({
            slot       = ir.lit("v1"),
            ref        = "gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        -- fail-open echo verify: dispatcher returns a table without
        -- _flow_token; verify returns true (fail-open), then out_schema
        -- is enforced on the result.
        local ctx = exec(def, {}, {
            dispatch = dispatch_const({ status = "abstain" }),
        })
        expect(ctx.verdict.status).to.equal("abstain")
    end)

    it("raises on schema mismatch after verify succeeds", function()
        local def = ir.wrap_step({
            slot       = ir.lit("v1"),
            ref        = "gate",
            out        = "ctx.verdict",
            out_schema = VERDICT_SCHEMA,
        })
        expect(function()
            exec(def, {}, { dispatch = dispatch_const({ status = "unknown" }) })
        end).to.fail()
    end)
end)

-- ── (d) wrap_step on_mismatch path bypasses out_schema ─────────────

describe("flow.ir wrap_step: on_mismatch bypasses out_schema", function()
    it("on_mismatch path stores raw result without schema validation", function()
        -- Token-bearing verify: dispatcher MUST echo _flow_token to pass.
        -- We omit echo → verify_bound fails when bound=true. Use stateless
        -- variant with a wrong-token echo to force mismatch.
        local def = ir.wrap_step({
            slot        = ir.lit("v1"),
            ref         = "gate",
            out         = "ctx.verdict",
            out_schema  = VERDICT_SCHEMA,
            on_mismatch = { kind = "let", at = "ctx.fallback",
                value = ir.lit("handled") },
        })
        -- Dispatch echoes a wrong _flow_token → verify mismatch → on_mismatch
        -- fires. ctx.verdict gets the raw (non-conforming) result; out_schema
        -- is intentionally NOT enforced on this path.
        local raw_result = { _flow_token = "wrong-token", garbage = true }
        local ctx = exec(def, {}, { dispatch = dispatch_const(raw_result) })
        expect(ctx.verdict.garbage).to.equal(true)
        expect(ctx.fallback).to.equal("handled")
    end)
end)
