--- Tests for dci (Prakash 2026, arXiv:2603.11781).
---
--- Coverage (plan.md §4.3 / issue §10):
---   1.  dci.meta — name / version / category / description
---   2.  ACT_CLASSES flatten == 14
---   3.  classify_act routes each act to its class
---   4.  role_persona yields non-empty prompt for 4 roles
---   5.  stage1_propose — 4 roles × 1 call, each role emits ≥ 1 act
---   6.  stage2_canonicalize — #result ≤ max_options
---   7.  stage6_converge — dominance
---   8.  stage6_converge — no_blocking
---   9.  stage6_converge — unconverged
---   10. stage7 FALLBACK_CASCADE_ORDER + call_log order
---   11. Stage 7 each stage I/O shape equals
---   12. decision_packet 5 components completeness
---   13. minority_report preservation on fallback
---   14. workspace 6 fields updated
---   15. M.run end-to-end (deliberated shape validate)
---   16. Card emission (auto_card=true)
---   17. Card fail-safe (alc.card == nil)
---   18. M._defaults aggregation
---   19. Card nested schema (body-key absent)

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function reset()
    package.loaded["dci"] = nil
    _G.alc = nil
end

-- Simple json_decode stub (Lua-table parse only; we feed it strings
-- already serialized by the test using the helper below).
local function make_alc_stub(llm_fn, card_stub)
    local call_log = {}
    local stub = {
        call_log = call_log,
        llm = function(prompt, opts)
            call_log[#call_log + 1] = {
                prompt = prompt,
                opts = opts,
            }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = setmetatable(
            { warn = function(_) end, info = function(_) end },
            { __call = function(_, _, _) end }
        ),
        json_decode = function(s)
            -- Use loadstring to parse a Lua-literal variant of JSON.
            -- The tests feed us strict Lua-table strings prefixed with
            -- "return ". If it's already a JSON string, fall back to a
            -- minimal hand-parser (we keep fixtures Lua-compatible for
            -- simplicity).
            if type(s) ~= "string" then return nil end
            local chunk, err = load("return " .. s, "jsonstub", "t", {})
            if not chunk then
                return nil, err
            end
            local ok, v = pcall(chunk)
            if not ok then return nil end
            return v
        end,
    }
    if card_stub then stub.card = card_stub end
    return stub
end

-- Build a Lua-literal object literal (our stub's json_decode parses
-- `return <literal>` via load). This lets fixtures stay readable.
local function j(obj)
    local function encode(v)
        local t = type(v)
        if t == "string" then
            return string.format("%q", v)
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        elseif t == "nil" then
            return "nil"
        elseif t == "table" then
            -- Detect array vs map
            local is_array = true
            local n = 0
            for k, _ in pairs(v) do
                n = n + 1
                if type(k) ~= "number" then is_array = false break end
            end
            local parts = {}
            if is_array then
                for i = 1, n do parts[#parts + 1] = encode(v[i]) end
                return "{" .. table.concat(parts, ",") .. "}"
            else
                for k, val in pairs(v) do
                    parts[#parts + 1] = "[" .. encode(k) .. "]="
                        .. encode(val)
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return "nil"
    end
    return encode(obj)
end

-- ═══════════════════════════════════════════════════════════════════
-- Test 1: meta
-- ═══════════════════════════════════════════════════════════════════

describe("dci.meta", function()
    lust.after(reset)

    it("has correct name", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d.meta.name).to.equal("dci")
    end)

    it("has version 0.1.0", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d.meta.version).to.equal("0.1.0")
    end)

    it("category is synthesis", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d.meta.category).to.equal("synthesis")
    end)

    it("description non-empty", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(#d.meta.description > 20).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 2: ACT_CLASSES flatten == 14
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.ACT_CLASSES", function()
    lust.after(reset)

    it("flattens to 14 acts", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        local flat = d._internal.flatten_acts(d._internal.ACT_CLASSES)
        expect(#flat).to.equal(14)
    end)

    it("has 6 classes", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        local n = 0
        for _ in pairs(d._internal.ACT_CLASSES) do n = n + 1 end
        expect(n).to.equal(6)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 3: classify_act routes each act
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.classify_act", function()
    lust.after(reset)

    it("routes frame → orienting", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d._internal.classify_act("frame")).to.equal("orienting")
    end)

    it("routes challenge → critical", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d._internal.classify_act("challenge")).to.equal("critical")
    end)

    it("routes recommend → decisional", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d._internal.classify_act("recommend")).to.equal("decisional")
    end)

    it("returns nil for unknown acts", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d._internal.classify_act("unknown_act")).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 4: role_persona returns non-empty for 4 roles
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.role_persona", function()
    lust.after(reset)

    it("returns non-empty prompt for each of 4 roles", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        for _, r in ipairs(d._internal.ROLES) do
            local p = d._internal.role_persona(r)
            expect(type(p)).to.equal("string")
            expect(#p > 10).to.equal(true)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 5: stage1_propose — 4 roles × 1 call, each role emits ≥ 1 act
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.stage1_propose", function()
    lust.after(reset)

    it("4 calls + each role yields ≥ 1 act", function()
        local stub = make_alc_stub(function(_, _, n)
            return j({
                acts = {
                    { type = "propose", content = "idea " .. n,
                      author = "role_" .. n },
                },
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local ws = d._internal.stage0_init("task")
        local acts = d._internal.stage1_propose("task", ws, 400)
        expect(#stub.call_log).to.equal(4)
        expect(#acts >= 4).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 6: stage2_canonicalize — #result ≤ max_options
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.stage2_canonicalize", function()
    lust.after(reset)

    it("caps option count at max_options", function()
        local stub = make_alc_stub(function()
            return j({
                options = {
                    { id = 1, content = "opt A", author = "integrator" },
                    { id = 2, content = "opt B", author = "integrator" },
                    { id = 3, content = "opt C", author = "integrator" },
                    { id = 4, content = "opt D", author = "integrator" },
                    { id = 5, content = "opt E", author = "integrator" },
                    { id = 6, content = "opt F", author = "integrator" },
                    { id = 7, content = "opt G", author = "integrator" },
                },
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local fake_acts = {
            { type = "propose", content = "a", author = "framer" },
            { type = "propose", content = "b", author = "explorer" },
        }
        local out = d._internal.stage2_canonicalize(fake_acts, 3)
        expect(#out <= 3).to.equal(true)
    end)

    it("pure-helper canonicalize caps correctly", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        local fake = {}
        for i = 1, 10 do
            fake[#fake + 1] = { type = "propose",
                content = "unique idea number " .. i }
        end
        local out = d._internal.canonicalize_options(fake, 3)
        expect(#out <= 3).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 7-9: stage6_converge — dominance / no_blocking / unconverged
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.stage6_converge", function()
    lust.after(reset)

    local function run_with_mode(mode)
        local stub = make_alc_stub(function()
            return j({
                mode = mode,
                ranking = {
                    { option_id = 1, score = 0.9, rationale = "top" },
                    { option_id = 2, score = 0.3, rationale = "weak" },
                },
                blocking_objections = {},
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = {
            { id = 1, content = "A", author = "framer" },
            { id = 2, content = "B", author = "explorer" },
        }
        return d._internal.stage6_converge("task", {}, options, nil, 400)
    end

    it("returns dominance mode on signal", function()
        local r = run_with_mode("dominance")
        expect(r.converged).to.equal(true)
        expect(r.mode).to.equal("dominance")
        expect(#r.ranking >= 2).to.equal(true)
    end)

    it("returns no_blocking mode on signal", function()
        local r = run_with_mode("no_blocking")
        expect(r.converged).to.equal(true)
        expect(r.mode).to.equal("no_blocking")
    end)

    it("returns unconverged on 'none' mode", function()
        local r = run_with_mode("none")
        expect(r.converged).to.equal(false)
        expect(r.mode).to.equal(nil)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 10: stage7 FALLBACK_CASCADE_ORDER constant + call_log order
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.stage7_fallback", function()
    lust.after(reset)

    it("FALLBACK_CASCADE_ORDER is exactly the 4 stages in order", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        local order = d._internal.FALLBACK_CASCADE_ORDER
        expect(#order).to.equal(4)
        expect(order[1]).to.equal("outranking")
        expect(order[2]).to.equal("minimax")
        expect(order[3]).to.equal("satisficing")
        expect(order[4]).to.equal("integrator_arbitration")
    end)

    it("calls stages in order when no stage converges early", function()
        -- Each stage returns converged=false except the last (which
        -- force-converges in impl). Prompt includes stage name.
        local stub = make_alc_stub(function(prompt)
            -- We inspect prompt later; return a non-converged ranking.
            return j({
                options = { { id = 1, content = "X" } },
                ranking = {
                    { option_id = 1, score = 0.5, rationale = "" },
                },
                converged = false,
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = {
            { id = 1, content = "A" }, { id = 2, content = "B" },
        }
        local out = d._internal.stage7_fallback("task", {}, options, 400)
        -- All 4 stages should have fired (last forces converge in impl).
        expect(#stub.call_log).to.equal(4)
        -- Verify order by prompt substring match
        local markers = { "outranking", "minimax", "satisficing",
            "integrator arbitration" }
        for i, m in ipairs(markers) do
            local p = (stub.call_log[i].prompt):lower()
            expect(p:find(m, 1, true) ~= nil).to.equal(true)
        end
        expect(out.stage_fired).to.equal("integrator_arbitration")
    end)

    it("early-terminates when a stage returns converged=true", function()
        local stub = make_alc_stub(function()
            return j({
                options = { { id = 1, content = "A" } },
                ranking = {
                    { option_id = 1, score = 0.9, rationale = "winner" },
                },
                converged = true,
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = { { id = 1, content = "A" } }
        local out = d._internal.stage7_fallback("task", {}, options, 400)
        expect(#stub.call_log).to.equal(1)  -- outranking only
        expect(out.stage_fired).to.equal("outranking")
        expect(out.calls_used).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 11: Stage 7 each stage returns same ranking shape
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal fallback stages — I/O shape parity", function()
    lust.after(reset)

    local function make_stub()
        return make_alc_stub(function()
            return j({
                options = { { id = 1, content = "X" } },
                ranking = {
                    { option_id = 1, score = 0.5, rationale = "r" },
                },
                converged = false,
            })
        end)
    end

    it("all 4 stages return {options, ranking} shape", function()
        _G.alc = make_stub()
        local d = require("dci")
        local initial = d._internal.initial_ranking_from_options({
            { id = 1, content = "A" }, { id = 2, content = "B" },
        })
        local stages = {
            d._internal.fallback_outranking,
            d._internal.fallback_minimax,
            d._internal.fallback_satisficing,
            d._internal.fallback_integrator_arbitration,
        }
        for _, fn in ipairs(stages) do
            _G.alc = make_stub()
            local out = fn("task", {}, initial, 400)
            expect(type(out.options)).to.equal("table")
            expect(type(out.ranking)).to.equal("table")
            expect(out.ranking[1]).to_not.equal(nil)
            expect(out.ranking[1].option_id ~= nil).to.equal(true)
            expect(out.ranking[1].score ~= nil).to.equal(true)
            expect(out.ranking[1].rationale ~= nil).to.equal(true)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 12: decision_packet 5 components completeness
-- ═══════════════════════════════════════════════════════════════════

describe("dci._internal.stage8_finalize", function()
    lust.after(reset)

    it("all 5 fields non-nil even when LLM returns minimal JSON", function()
        local stub = make_alc_stub(function()
            return j({
                answer = "chosen",
                rationale = "because",
                evidence = { "cite1" },
                residual_objections = {},
                next_actions = {},
                reopen_triggers = {},
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = {
            { id = 1, content = "A", author = "framer" },
            { id = 2, content = "B", author = "explorer" },
        }
        local selected = { option_id = 1, score = 0.9, rationale = "" }
        local ws = d._internal.stage0_init("task")
        local packet = d._internal.stage8_finalize("task", ws, selected,
            options, {}, 400)
        expect(packet.selected_option).to_not.equal(nil)
        expect(packet.selected_option.answer).to_not.equal(nil)
        expect(packet.selected_option.rationale).to_not.equal(nil)
        expect(packet.selected_option.evidence).to_not.equal(nil)
        expect(packet.residual_objections).to_not.equal(nil)
        expect(packet.minority_report).to_not.equal(nil)
        expect(packet.next_actions).to_not.equal(nil)
        expect(packet.reopen_triggers).to_not.equal(nil)
    end)

    it("nil fields in LLM output become empty arrays / strings", function()
        local stub = make_alc_stub(function()
            -- LLM returns only 'answer'; all others nil.
            return j({ answer = "X" })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = {
            { id = 1, content = "A" }, { id = 2, content = "B" },
        }
        local selected = { option_id = 1, score = 0, rationale = "" }
        local ws = d._internal.stage0_init("task")
        local packet = d._internal.stage8_finalize("task", ws, selected,
            options, {}, 400)
        expect(type(packet.selected_option.evidence)).to.equal("table")
        expect(type(packet.residual_objections)).to.equal("table")
        expect(type(packet.next_actions)).to.equal("table")
        expect(type(packet.reopen_triggers)).to.equal("table")
        expect(type(packet.minority_report)).to.equal("table")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 13: minority_report preservation on fallback
-- ═══════════════════════════════════════════════════════════════════

describe("dci.minority_report preservation", function()
    lust.after(reset)

    it("stage8 retains non-selected options as minority_report", function()
        local stub = make_alc_stub(function()
            return j({
                answer = "A chosen",
                rationale = "",
                evidence = {},
                residual_objections = {},
                next_actions = {},
                reopen_triggers = {},
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local options = {
            { id = 1, content = "A pro", author = "framer" },
            { id = 2, content = "B con", author = "explorer" },
            { id = 3, content = "C neutral", author = "challenger" },
        }
        local selected = { option_id = 1, score = 0.9, rationale = "top" }
        local ws = d._internal.stage0_init("task")
        local packet = d._internal.stage8_finalize("task", ws, selected,
            options, {}, 400)
        -- Non-selected: B and C preserved
        expect(#packet.minority_report >= 2).to.equal(true)
        local positions = {}
        for _, m in ipairs(packet.minority_report) do
            positions[#positions + 1] = m.position
        end
        local joined = table.concat(positions, "|")
        expect(joined:find("B con", 1, true) ~= nil).to.equal(true)
        expect(joined:find("C neutral", 1, true) ~= nil).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 14: workspace 6 fields updated after stage1
-- ═══════════════════════════════════════════════════════════════════

describe("dci workspace 6 fields", function()
    lust.after(reset)

    it("stage0_init produces all 6 fields with safe defaults", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        local ws = d._internal.stage0_init("my task")
        expect(ws.problem_view).to.equal("my task")
        expect(type(ws.key_frames)).to.equal("table")
        expect(type(ws.emerging_ideas)).to.equal("table")
        expect(type(ws.tensions)).to.equal("table")
        expect(ws.synthesis_in_progress).to.equal("")
        expect(type(ws.next_actions)).to.equal("table")
    end)

    it("stage1_propose accumulates key_frames and emerging_ideas", function()
        local call_count = 0
        local stub = make_alc_stub(function()
            call_count = call_count + 1
            return j({
                acts = {
                    { type = "frame", content = "frame " .. call_count,
                      author = "framer" },
                    { type = "propose", content = "idea " .. call_count,
                      author = "framer" },
                },
            })
        end)
        _G.alc = stub
        local d = require("dci")
        local ws = d._internal.stage0_init("task")
        d._internal.stage1_propose("task", ws, 400)
        expect(#ws.key_frames >= 1).to.equal(true)
        expect(#ws.emerging_ideas >= 1).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 15: M.run end-to-end (deliberated shape validates)
-- ═══════════════════════════════════════════════════════════════════

describe("dci.run end-to-end (mocked)", function()
    lust.after(reset)

    it("produces a valid deliberated shape", function()
        local call_count = 0
        -- Fixture cycle: stage1 (4), stage2 (1), stage3 (4), stage4 (4),
        -- stage5 (4), stage6 (1 converged=dominance), stage8 (1).
        local stub = make_alc_stub(function(prompt, _, n)
            call_count = n
            if prompt:find("Stage 6", 1, true)
                or prompt:find("convergence test", 1, true)
            then
                return j({
                    mode = "dominance",
                    ranking = {
                        { option_id = 1, score = 0.9, rationale = "dom" },
                        { option_id = 2, score = 0.3, rationale = "weak" },
                    },
                    blocking_objections = {},
                })
            elseif prompt:find("Stage 8", 1, true)
                or prompt:find("finalize the decision packet", 1, true)
            then
                return j({
                    answer = "Option A",
                    rationale = "best",
                    evidence = { "cite" },
                    residual_objections = {},
                    next_actions = { "follow-up 1" },
                    reopen_triggers = {},
                })
            elseif prompt:find("canonicalize", 1, true) then
                return j({
                    options = {
                        { id = 1, content = "Option A",
                          author = "integrator" },
                        { id = 2, content = "Option B",
                          author = "integrator" },
                    },
                })
            elseif prompt:find("Stage 5", 1, true)
                or prompt:find("revise and compress", 1, true)
            then
                return j({
                    options = {
                        { id = 1, content = "Option A" },
                        { id = 2, content = "Option B" },
                    },
                })
            else
                -- stage1/stage3/stage4: return a generic act
                return j({
                    acts = {
                        { type = "propose", content = "act " .. n,
                          author = "role_" .. n },
                    },
                })
            end
        end)
        _G.alc = stub
        local d = require("dci")
        local S = require("alc_shapes")

        local ctx = { task = "Should we X?" }
        d.run(ctx)

        expect(ctx.result).to_not.equal(nil)
        expect(type(ctx.result.answer)).to.equal("string")
        expect(ctx.result.convergence).to_not.equal(nil)
        local ok, reason = S.check(ctx.result, S.deliberated)
        if not ok then
            error("deliberated shape failed: " .. tostring(reason))
        end
        expect(ok).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 16: Card emission (auto_card=true)
-- ═══════════════════════════════════════════════════════════════════

describe("dci.run — Card emission", function()
    lust.after(reset)

    it("sets ctx.result.card_id from stubbed alc.card.create", function()
        local create_args, sampled_args
        local create_calls, sample_calls = 0, 0

        local card_stub = {
            create = function(args)
                create_calls = create_calls + 1
                create_args = args
                return { card_id = "stub_card_42" }
            end,
            write_samples = function(id, list)
                sample_calls = sample_calls + 1
                sampled_args = { id = id, list = list }
            end,
        }

        local stub = make_alc_stub(function(prompt, _, n)
            if prompt:find("Stage 6", 1, true)
                or prompt:find("convergence test", 1, true)
            then
                return j({
                    mode = "dominance",
                    ranking = {
                        { option_id = 1, score = 0.9, rationale = "dom" },
                    },
                    blocking_objections = {},
                })
            elseif prompt:find("Stage 8", 1, true)
                or prompt:find("finalize the decision packet", 1, true)
            then
                return j({
                    answer = "A",
                    rationale = "",
                    evidence = {},
                    residual_objections = {},
                    next_actions = {},
                    reopen_triggers = {},
                })
            elseif prompt:find("canonicalize", 1, true)
                or prompt:find("revise and compress", 1, true)
            then
                return j({
                    options = { { id = 1, content = "A" } },
                })
            else
                return j({
                    acts = {
                        { type = "propose", content = "x",
                          author = "r" .. n },
                    },
                })
            end
        end, card_stub)
        _G.alc = stub

        local d = require("dci")
        local ctx = { task = "q", auto_card = true }
        d.run(ctx)
        expect(ctx.result.card_id).to.equal("stub_card_42")
        expect(create_calls).to.equal(1)
        expect(sample_calls >= 1).to.equal(true)
        -- pkg.name default prefix
        expect(create_args.pkg.name:sub(1, 4)).to.equal("dci_")
    end)

    it("card_pkg override is respected", function()
        local captured_name
        local card_stub = {
            create = function(args)
                captured_name = args.pkg.name
                return { card_id = "ok" }
            end,
            write_samples = function() end,
        }
        local stub = make_alc_stub(function(prompt)
            if prompt:find("Stage 6", 1, true) then
                return j({
                    mode = "dominance",
                    ranking = { { option_id = 1, score = 0.9, rationale = "" } },
                    blocking_objections = {},
                })
            elseif prompt:find("Stage 8", 1, true) then
                return j({
                    answer = "A", rationale = "", evidence = {},
                    residual_objections = {}, next_actions = {},
                    reopen_triggers = {},
                })
            elseif prompt:find("canonicalize", 1, true)
                or prompt:find("revise and compress", 1, true)
            then
                return j({
                    options = { { id = 1, content = "A" } },
                })
            else
                return j({
                    acts = { { type = "propose", content = "x",
                        author = "r" } },
                })
            end
        end, card_stub)
        _G.alc = stub
        local d = require("dci")
        local ctx = { task = "q", auto_card = true,
            card_pkg = "my_custom_pkg" }
        d.run(ctx)
        expect(captured_name).to.equal("my_custom_pkg")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 17: Card fail-safe (alc.card absent)
-- ═══════════════════════════════════════════════════════════════════

describe("dci.run — Card fail-safe", function()
    lust.after(reset)

    it("alc.card absent → card_id nil, no exception, warn logged", function()
        local warn_count = 0
        local stub = make_alc_stub(function(prompt)
            if prompt:find("Stage 6", 1, true) then
                return j({
                    mode = "dominance",
                    ranking = { { option_id = 1, score = 0.9, rationale = "" } },
                    blocking_objections = {},
                })
            elseif prompt:find("Stage 8", 1, true) then
                return j({
                    answer = "A", rationale = "", evidence = {},
                    residual_objections = {}, next_actions = {},
                    reopen_triggers = {},
                })
            elseif prompt:find("canonicalize", 1, true)
                or prompt:find("revise and compress", 1, true)
            then
                return j({
                    options = { { id = 1, content = "A" } },
                })
            else
                return j({
                    acts = { { type = "propose", content = "x",
                        author = "r" } },
                })
            end
        end)
        stub.log = setmetatable(
            {
                warn = function(_) warn_count = warn_count + 1 end,
                info = function(_) end,
            },
            { __call = function() end }
        )
        _G.alc = stub
        -- Explicitly no .card
        _G.alc.card = nil
        local d = require("dci")
        local ctx = { task = "q", auto_card = true }
        local ok = pcall(d.run, ctx)
        expect(ok).to.equal(true)
        expect(ctx.result.card_id).to.equal(nil)
        expect(warn_count >= 1).to.equal(true)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 18: M._defaults aggregation (magic numbers not hard-coded)
-- ═══════════════════════════════════════════════════════════════════

describe("dci._defaults", function()
    lust.after(reset)

    it("has correct values per paper §5 Table 1 / Appendix A", function()
        _G.alc = make_alc_stub(function() return "" end)
        local d = require("dci")
        expect(d._defaults.max_rounds).to.equal(2)
        expect(d._defaults.max_options).to.equal(5)
        expect(d._defaults.num_finalists).to.equal(3)
        expect(d._defaults.gen_tokens).to.equal(400)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Test 19: Card nested schema (body-key absent; nested pkg/scenario/dci)
-- ═══════════════════════════════════════════════════════════════════

describe("dci — Card IF nested schema", function()
    lust.after(reset)

    it("alc.card.create receives nested form without body key", function()
        local captured
        local card_stub = {
            create = function(args)
                captured = args
                return { card_id = "ok" }
            end,
            write_samples = function() end,
        }
        local stub = make_alc_stub(function(prompt)
            if prompt:find("Stage 6", 1, true) then
                return j({
                    mode = "dominance",
                    ranking = { { option_id = 1, score = 0.9, rationale = "" } },
                    blocking_objections = {},
                })
            elseif prompt:find("Stage 8", 1, true) then
                return j({
                    answer = "Foo", rationale = "", evidence = {},
                    residual_objections = {}, next_actions = {},
                    reopen_triggers = {},
                })
            elseif prompt:find("canonicalize", 1, true)
                or prompt:find("revise and compress", 1, true)
            then
                return j({
                    options = { { id = 1, content = "A" } },
                })
            else
                return j({
                    acts = { { type = "propose", content = "x",
                        author = "r" } },
                })
            end
        end, card_stub)
        _G.alc = stub
        local d = require("dci")
        local ctx = { task = "q", auto_card = true }
        d.run(ctx)
        expect(captured).to_not.equal(nil)
        -- body key must not be present (optimize / conformal_vote BP)
        expect(captured.body).to.equal(nil)
        -- nested pkg / scenario
        expect(type(captured.pkg)).to.equal("table")
        expect(type(captured.pkg.name)).to.equal("string")
        expect(type(captured.scenario)).to.equal("table")
        expect(type(captured.scenario.name)).to.equal("string")
        -- pkg-specific top-level 'dci'
        expect(type(captured.dci)).to.equal("table")
        expect(captured.dci.answer).to.equal("Foo")
        expect(type(captured.dci.convergence)).to.equal("string")
        expect(type(captured.dci.residual_objections_count)).to.equal("number")
        expect(type(captured.dci.minority_count)).to.equal("number")
    end)
end)
