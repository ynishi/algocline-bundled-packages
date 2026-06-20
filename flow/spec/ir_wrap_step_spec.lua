--- Tests for flow.ir wrap_step Node (v0.8.0).
---
--- Covers 4 canonical cases (matching draft-wrap-step-node.md §4):
---   - default raise on verify mismatch
---   - on_mismatch fallback Node executed on mismatch
---   - bound = false (default) — in-memory cycle, no state required
---   - bound = true            — session-spanning via state.data._flow_req_<slot>
--- Plus compile-time shape checks and slot-Expr (concat) integration.

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

-- mock alc.state before requiring flow (state.lua reads it on save)
local function mock_alc_state()
    local store = {}
    _G.alc = {
        state = {
            get = function(key) return store[key] end,
            set = function(key, val) store[key] = val end,
        },
        log = function() end,
    }
    return store
end

local function reset_modules()
    _G.alc = nil
    for _, k in ipairs({
        "flow", "flow.util", "flow.state", "flow.token",
        "flow.ir", "flow.ir.interpreter",
    }) do
        package.loaded[k] = nil
    end
end

-- ── helpers ─────────────────────────────────────────────────────────

local function fresh_ir()
    reset_modules()
    mock_alc_state()
    return require("flow.ir"), require("flow.state")
end

local function letx(at, value)
    return { kind = "let", at = at, value = value }
end

-- echo-dispatcher: echoes _flow_token / _flow_slot from the wrapped
-- payload, optionally tampered.
local function make_dispatcher(opts)
    opts = opts or {}
    return function(_ref, input)
        local res = { ok = true, ref = _ref }
        if input then
            res._flow_token = opts.tamper_token or input._flow_token
            res._flow_slot  = opts.tamper_slot  or input._flow_slot
            res.payload_seen = input
        end
        return res
    end
end

-- ── compile ─────────────────────────────────────────────────────────

describe("flow.ir.compile wrap_step", function()
    it("accepts a minimal wrap_step (literal slot, no in_, no on_mismatch)", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("gate"),
            ref  = "pkg.run",
            out  = "ctx.gate_out",
        })
        local ok = ir.compile(node)
        expect(ok).to.exist()
    end)

    it("rejects out without 'ctx.' prefix", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "p", out = "bad.out",
        })
        local _, reason = ir.compile(node)
        expect(reason:find("wrap_step%.out must start with 'ctx%.'")).to.exist()
    end)

    it("rejects empty ref", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "", out = "ctx.o",
        })
        local _, reason = ir.compile(node)
        expect(reason:find("wrap_step%.ref: required non%-empty")).to.exist()
    end)

    it("descends into slot Expr (validates path root)", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.path("$.bad.s"), ref = "p", out = "ctx.o",
        })
        local _, reason = ir.compile(node)
        expect(reason:find("Expr%.path%.at must start")).to.exist()
    end)

    it("descends into on_mismatch Node", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "p", out = "ctx.o",
            on_mismatch = letx("bad.x", ir.lit(1)),  -- bad write path
        })
        local _, reason = ir.compile(node)
        expect(reason:find("let%.at must start")).to.exist()
    end)

    it("eager opts.refs registry check", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "missing", out = "ctx.o",
        })
        local _, reason = ir.compile(node, { refs = { other = true } })
        expect(reason:find("not in opts%.refs registry")).to.exist()
    end)
end)

-- ── exec: default raise (no on_mismatch) ────────────────────────────

describe("flow.ir.exec wrap_step — default raise", function()
    it("writes raw result on verify PASS (echo matches)", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("root_gate"), ref = "pkg.run",
            in_  = ir.lit({ task = "x" }),
            out  = "ctx.root_out",
        })
        local ctx = ir.exec(node, {}, { dispatch = make_dispatcher() })
        expect(ctx.root_out.ok).to.equal(true)
        -- echoed metadata is present (fail-open contract holds)
        expect(ctx.root_out._flow_slot).to.equal("root_gate")
    end)

    it("raises on token tamper when on_mismatch is absent", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("gate"), ref = "p", out = "ctx.o",
            in_  = ir.lit({}),
        })
        local d = make_dispatcher({ tamper_token = "WRONG" })
        expect(function()
            ir.exec(node, {}, { dispatch = d })
        end).to.fail()
    end)

    it("raises on slot tamper", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("gate"), ref = "p", out = "ctx.o",
            in_  = ir.lit({}),
        })
        local d = make_dispatcher({ tamper_slot = "other" })
        expect(function()
            ir.exec(node, {}, { dispatch = d })
        end).to.fail()
    end)

    it("rejects non-string slot at exec time", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit(123), ref = "p", out = "ctx.o",
        })
        expect(function()
            ir.exec(node, {}, { dispatch = make_dispatcher() })
        end).to.fail()
    end)

    it("rejects empty-string slot at exec time", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit(""), ref = "p", out = "ctx.o",
        })
        expect(function()
            ir.exec(node, {}, { dispatch = make_dispatcher() })
        end).to.fail()
    end)
end)

-- ── exec: on_mismatch fallback ──────────────────────────────────────

describe("flow.ir.exec wrap_step — on_mismatch", function()
    it("runs fallback Node on mismatch instead of raising", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "p",
            in_  = ir.lit({}),
            out  = "ctx.gate_out",
            on_mismatch = letx("ctx.fallback_fired", ir.lit(true)),
        })
        local ctx = ir.exec(node, {}, {
            dispatch = make_dispatcher({ tamper_token = "X" }),
        })
        expect(ctx.fallback_fired).to.equal(true)
        -- The failing result is surfaced to ctx.out so the fallback can inspect
        expect(ctx.gate_out._flow_token).to.equal("X")
    end)

    it("does NOT run fallback when verify PASSes", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "p",
            in_  = ir.lit({}),
            out  = "ctx.o",
            on_mismatch = letx("ctx.fallback_fired", ir.lit(true)),
        })
        local ctx = ir.exec(node, {}, { dispatch = make_dispatcher() })
        expect(ctx.fallback_fired).to.equal(nil)
    end)
end)

-- ── exec: bound = true (session-spanning) ───────────────────────────

describe("flow.ir.exec wrap_step — bound = true", function()
    it("requires opts.state when bound=true", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.lit("g"), ref = "p", out = "ctx.o", bound = true,
        })
        expect(function()
            ir.exec(node, {}, { dispatch = make_dispatcher() })
        end).to.fail()
    end)

    it("persists + auto-deletes req on verify PASS", function()
        local ir, flow_state = fresh_ir()
        local st = flow_state.new({ key_prefix = "test", id = "ws1" })
        local node = ir.wrap_step({
            slot = ir.lit("gate"), ref = "p",
            in_  = ir.lit({}), out = "ctx.gate_out", bound = true,
        })
        local ctx = ir.exec(node, {}, {
            dispatch = make_dispatcher(),
            state    = st,
        })
        expect(ctx.gate_out.ok).to.equal(true)
        -- req auto-deleted after successful verify
        expect(st.data[flow_state.REQ_PREFIX .. "gate"]).to.equal(nil)
    end)

    it("retains persisted req on verify mismatch (caller can inspect)", function()
        local ir, flow_state = fresh_ir()
        local st = flow_state.new({ key_prefix = "test", id = "ws2" })
        local node = ir.wrap_step({
            slot = ir.lit("gate"), ref = "p",
            in_  = ir.lit({}), out = "ctx.gate_out", bound = true,
            on_mismatch = letx("ctx.fired", ir.lit(true)),
        })
        local ctx = ir.exec(node, {}, {
            dispatch = make_dispatcher({ tamper_token = "X" }),
            state    = st,
        })
        expect(ctx.fired).to.equal(true)
        -- req kept so caller can retry / inspect
        expect(st.data[flow_state.REQ_PREFIX .. "gate"]).to.exist()
    end)
end)

-- ── slot Expr integration (concat) ──────────────────────────────────

describe("flow.ir.exec wrap_step — dynamic slot via concat", function()
    it("computes slot from concat(lit, path)", function()
        local ir = fresh_ir()
        local node = ir.wrap_step({
            slot = ir.concat(ir.lit("branch_"), ir.path("$.ctx.i")),
            ref  = "p",
            in_  = ir.lit({}),
            out  = "ctx.branch_out",
        })
        local ctx = ir.exec(node, { i = "3" }, {
            dispatch = make_dispatcher(),
        })
        expect(ctx.branch_out._flow_slot).to.equal("branch_3")
    end)
end)

-- cleanup global state pollution
reset_modules()
