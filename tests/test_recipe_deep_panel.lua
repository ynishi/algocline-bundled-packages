--- Tests for recipe_deep_panel package.
--- Structure validation + smoke test against mocked alc + ab_mcts +
--- calibrate. The full tree-search reasoning path is NOT exercised —
--- this file covers Stage 1 abort, Stage 2 fan-out wiring, Stage 3
--- diversity, Stage 4 Condorcet expected-accuracy, Stage 5 calibrate
--- gate, and resume semantics.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ═══════════════════════════════════════════════════════════════════
-- Meta structure (static; no alc / LLM needed)
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_deep_panel.meta", function()
    local deep_panel = require("recipe_deep_panel")

    it("has correct name", function()
        expect(deep_panel.meta.name).to.equal("recipe_deep_panel")
    end)

    it("has version", function()
        expect(deep_panel.meta.version).to.exist()
    end)

    it("has description", function()
        expect(type(deep_panel.meta.description)).to.equal("string")
        expect(#deep_panel.meta.description > 0).to.equal(true)
    end)

    it("has category = recipe", function()
        expect(deep_panel.meta.category).to.equal("recipe")
    end)
end)

describe("recipe_deep_panel.ingredients", function()
    local deep_panel = require("recipe_deep_panel")

    it("is a non-empty list of strings", function()
        expect(type(deep_panel.ingredients)).to.equal("table")
        expect(#deep_panel.ingredients > 0).to.equal(true)
        for _, pkg in ipairs(deep_panel.ingredients) do
            expect(type(pkg)).to.equal("string")
        end
    end)

    it("contains flow, condorcet, ab_mcts, ensemble_div, calibrate",
        function()
            local want = { "flow", "condorcet", "ab_mcts",
                "ensemble_div", "calibrate" }
            for _, needle in ipairs(want) do
                local found = false
                for _, pkg in ipairs(deep_panel.ingredients) do
                    if pkg == needle then found = true end
                end
                expect(found).to.equal(true)
            end
        end)

    it("all ingredients can be required", function()
        for _, pkg_name in ipairs(deep_panel.ingredients) do
            local ok, pkg = pcall(require, pkg_name)
            expect(ok).to.equal(true)
            expect(type(pkg)).to.equal("table")
            expect(pkg.meta).to.exist()
        end
    end)
end)

describe("recipe_deep_panel.caveats", function()
    local deep_panel = require("recipe_deep_panel")

    it("is a non-empty list of strings", function()
        expect(type(deep_panel.caveats)).to.equal("table")
        expect(#deep_panel.caveats >= 3).to.equal(true)
        for _, c in ipairs(deep_panel.caveats) do
            expect(type(c)).to.equal("string")
        end
    end)

    it("mentions Anti-Jury", function()
        local found = false
        for _, c in ipairs(deep_panel.caveats) do
            if c:find("Anti%-Jury") or c:find("anti_jury") then
                found = true
            end
        end
        expect(found).to.equal(true)
    end)

    it("mentions cost scaling", function()
        local found = false
        for _, c in ipairs(deep_panel.caveats) do
            if c:find("Cost") or c:find("cost") or c:find("LLM calls") then
                found = true
            end
        end
        expect(found).to.equal(true)
    end)

    it("mentions resume replay semantics", function()
        local found = false
        for _, c in ipairs(deep_panel.caveats) do
            if c:find("[Rr]esume") then found = true end
        end
        expect(found).to.equal(true)
    end)
end)

describe("recipe_deep_panel.verified", function()
    local deep_panel = require("recipe_deep_panel")

    it("has theoretical_basis covering all four papers", function()
        local basis = deep_panel.verified.theoretical_basis
        expect(type(basis)).to.equal("table")
        expect(#basis >= 4).to.equal(true)
        local blob = table.concat(basis, "\n")
        expect(blob:find("AB%-MCTS") or blob:find("Inoue")).to_not.equal(nil)
        expect(blob:find("Condorcet")).to_not.equal(nil)
        expect(blob:find("Krogh")).to_not.equal(nil)
        expect(blob:find("Wang")).to_not.equal(nil)
    end)

    it("stage_coverage covers all 5 stages", function()
        local sc = deep_panel.verified.stage_coverage
        expect(type(sc)).to.equal("table")
        expect(#sc).to.equal(5)
        for i, entry in ipairs(sc) do
            expect(entry.stage).to.equal(i)
            expect(type(entry.name)).to.equal("string")
            expect(entry.status == "verified"
                or entry.status == "not_exercised"
                or entry.status == "theoretical_only").to.equal(true)
            expect(type(entry.evidence)).to.equal("table")
        end
    end)

    it("non-verified entries carry reason + to_verify", function()
        for _, entry in ipairs(deep_panel.verified.stage_coverage) do
            if entry.status ~= "verified" then
                expect(type(entry.reason)).to.equal("string")
                expect(type(entry.to_verify)).to.equal("string")
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Internal helpers (pure)
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_deep_panel._internal.tally_votes", function()
    local deep_panel = require("recipe_deep_panel")
    local tally = deep_panel._internal.tally_votes
    local norm = deep_panel._internal.default_normalizer

    it("unanimous: n_distinct=1, margin_gap=1", function()
        local r = tally({ "Tokyo", "tokyo", "TOKYO" }, norm)
        expect(r.n_distinct).to.equal(1)
        expect(r.plurality_fraction).to.equal(1.0)
        expect(r.margin_gap).to.equal(1.0)
    end)

    it("3-way tie: top_count=1, margin_gap=0", function()
        local r = tally({ "a", "b", "c" }, norm)
        expect(r.n_distinct).to.equal(3)
        expect(r.top_count).to.equal(1)
        expect(r.margin_gap).to.equal(0)
    end)

    it("2-1 split: top=2, runner_up=1, margin=1/3", function()
        local r = tally({ "x", "x", "y" }, norm)
        expect(r.top_count).to.equal(2)
        expect(r.runner_up).to.equal(1)
        expect(math.abs(r.margin_gap - 1/3) < 1e-9).to.equal(true)
    end)
end)

describe("recipe_deep_panel._internal.try_parse_numbers", function()
    local deep_panel = require("recipe_deep_panel")
    local parse = deep_panel._internal.try_parse_numbers

    it("all numeric strings → nums, true", function()
        local nums, ok = parse({ "10", "12.5", "-3" })
        expect(ok).to.equal(true)
        expect(nums[1]).to.equal(10)
        expect(nums[2]).to.equal(12.5)
        expect(nums[3]).to.equal(-3)
    end)

    it("raw numbers pass through", function()
        local nums, ok = parse({ 1, 2, 3 })
        expect(ok).to.equal(true)
        expect(nums[1]).to.equal(1)
    end)

    it("any non-numeric → nil, false", function()
        local _, ok = parse({ "10", "abc", "5" })
        expect(ok).to.equal(false)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- M.run input validation (no alc required; errors before any call)
-- ═══════════════════════════════════════════════════════════════════

describe("recipe_deep_panel.run (input validation)", function()
    local deep_panel = require("recipe_deep_panel")

    it("errors on missing ctx.task", function()
        local ok, err = pcall(deep_panel.run, {})
        expect(ok).to.equal(false)
        expect(err:find("task")).to.exist()
    end)

    it("errors on missing ctx.task_id", function()
        local ok, err = pcall(deep_panel.run, { task = "t" })
        expect(ok).to.equal(false)
        expect(err:find("task_id")).to.exist()
    end)

    it("errors on missing ctx.p_estimate", function()
        local ok, err = pcall(deep_panel.run, {
            task = "t", task_id = "id1",
        })
        expect(ok).to.equal(false)
        expect(err:find("p_estimate")).to.exist()
    end)

    it("errors on p_estimate out of (0, 1]", function()
        local ok = pcall(deep_panel.run, {
            task = "t", task_id = "id1", p_estimate = 0,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on even n_branches", function()
        local ok = pcall(deep_panel.run, {
            task = "t", task_id = "id1", p_estimate = 0.7, n_branches = 4,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on n_branches < 3", function()
        local ok = pcall(deep_panel.run, {
            task = "t", task_id = "id1", p_estimate = 0.7, n_branches = 1,
        })
        expect(ok).to.equal(false)
    end)

    it("errors on n_branches > default approaches without explicit list",
        function()
            local ok, err = pcall(deep_panel.run, {
                task = "t", task_id = "id1",
                p_estimate = 0.7, n_branches = 9,
            })
            expect(ok).to.equal(false)
            expect(err:find("approaches")).to.exist()
        end)

    it("errors on duplicate approaches", function()
        local ok, err = pcall(deep_panel.run, {
            task = "t", task_id = "id1", p_estimate = 0.7,
            n_branches = 3,
            approaches = { "same", "same", "different" },
        })
        expect(ok).to.equal(false)
        expect(err:find("duplicate") or err:find("Duplicate")).to_not.equal(nil)
    end)

    it("errors on #approaches != n_branches", function()
        local ok, err = pcall(deep_panel.run, {
            task = "t", task_id = "id1", p_estimate = 0.7,
            n_branches = 3,
            approaches = { "a", "b" },
        })
        expect(ok).to.equal(false)
        expect(err:find("approaches")).to.exist()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Smoke tests: full M.run with mocked alc + ab_mcts + calibrate
-- ═══════════════════════════════════════════════════════════════════

local function fresh_store() return {} end

local function install_stubs(store, options)
    options = options or {}

    _G.alc = {
        state = {
            get = function(k) return store[k] end,
            set = function(k, v) store[k] = v end,
        },
        log = function() end,
        stats = { record = function() end },
    }

    package.loaded["ab_mcts"] = {
        meta = { name = "ab_mcts" },
        run = function(payload)
            local slot = payload._flow_slot
            local answer
            if options.ab_mcts_answers then
                answer = options.ab_mcts_answers[slot]
            end
            if answer == nil then
                answer = "ans:" .. slot
            end
            local echoed_token = payload._flow_token
            if options.tamper_token_on_slot == slot then
                echoed_token = echoed_token .. "-xx"
            end
            return {
                result = {
                    answer     = answer,
                    best_score = (options.scores and options.scores[slot])
                        or 0.8,
                    tree_stats = {
                        total_nodes = 10,
                        budget = payload.budget or 8,
                        wider_decisions = 2,
                        deeper_decisions = 3,
                        max_depth = payload.max_depth or 3,
                        branching_ratio = 0.4,
                    },
                },
                _flow_token = echoed_token,
                _flow_slot  = slot,
            }
        end,
    }

    package.loaded["calibrate"] = {
        meta = { name = "calibrate" },
        assess = function(_ctx)
            return {
                result = {
                    answer = "meta",
                    confidence = options.confidence or 0.85,
                    total_llm_calls = 1,
                },
            }
        end,
    }

    for _, k in ipairs({
        "flow", "flow.util", "flow.state", "flow.token", "flow.llm",
        "recipe_deep_panel",
    }) do
        package.loaded[k] = nil
    end
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({
        "flow", "flow.util", "flow.state", "flow.token", "flow.llm",
        "recipe_deep_panel", "ab_mcts", "calibrate",
    }) do
        package.loaded[k] = nil
    end
end

-- ─── Stage 1 abort ───

describe("recipe_deep_panel.run (Stage 1 abort)", function()
    lust.after(reset)

    it("aborts with anti_jury=true when p < 0.5", function()
        local store = fresh_store()
        install_stubs(store)
        local deep_panel = require("recipe_deep_panel")
        local ctx = deep_panel.run({
            task = "t", task_id = "abort1",
            p_estimate = 0.3,
        })
        expect(ctx.result.aborted).to.equal(true)
        expect(ctx.result.anti_jury).to.equal(true)
        expect(ctx.result.answer).to.equal(nil)
        expect(ctx.result.total_llm_calls).to.equal(0)
        expect(ctx.result.abort_reason:find("Anti%-Jury")).to_not.equal(nil)
    end)

    it("aborts with anti_jury=false when p = 0.5 (coin-flip)", function()
        local store = fresh_store()
        install_stubs(store)
        local deep_panel = require("recipe_deep_panel")
        local ctx = deep_panel.run({
            task = "t", task_id = "abort2",
            p_estimate = 0.5,
        })
        expect(ctx.result.aborted).to.equal(true)
        expect(ctx.result.anti_jury).to.equal(false)
        expect(ctx.result.total_llm_calls).to.equal(0)
        expect(ctx.result.abort_reason:find("[Cc]oin%-flip")).to_not.equal(nil)
    end)

    it("result shape unified with main path (same fields present)",
        function()
            local store = fresh_store()
            install_stubs(store)
            local deep_panel = require("recipe_deep_panel")
            local ctx = deep_panel.run({
                task = "t", task_id = "abort3", p_estimate = 0.2,
            })
            -- Key fields that downstream consumers read should exist
            -- without having to branch on aborted.
            expect(ctx.result.answer).to.equal(nil)
            expect(ctx.result.confidence).to.equal(0)
            expect(ctx.result.panel_size).to.equal(0)
            expect(ctx.result.plurality_fraction).to.equal(0)
            expect(type(ctx.result.vote_counts)).to.equal("table")
            expect(type(ctx.result.branches)).to.equal("table")
            expect(ctx.result.needs_investigation).to.equal(true)
            expect(ctx.result.unanimous).to.equal(false)
            expect(type(ctx.result.stages)).to.equal("table")
        end)
end)

-- ─── Main path happy ───

describe("recipe_deep_panel.run (main path)", function()
    lust.after(reset)

    it("runs 5 stages end-to-end at n=3 and returns plurality answer",
        function()
            local store = fresh_store()
            install_stubs(store, {
                ab_mcts_answers = {
                    branch_1 = "Paris",
                    branch_2 = "Paris",
                    branch_3 = "London",
                },
                confidence = 0.9,
            })
            local deep_panel = require("recipe_deep_panel")
            local ctx = deep_panel.run({
                task = "Capital of France?",
                task_id = "main1",
                p_estimate = 0.85,
            })
            expect(ctx.result.aborted).to.equal(false)
            expect(ctx.result.answer).to.equal("Paris")
            expect(ctx.result.panel_size).to.equal(3)
            expect(ctx.result.n_distinct_answers).to.equal(2)
            expect(math.abs(ctx.result.plurality_fraction - 2/3) < 1e-9)
                .to.equal(true)
            expect(math.abs(ctx.result.margin_gap - 1/3) < 1e-9)
                .to.equal(true)
            expect(ctx.result.confidence).to.equal(0.9)
            expect(ctx.result.needs_investigation).to.equal(false)
            expect(#ctx.result.stages).to.equal(5)
            -- Total LLM cost: 3 branches × (2*8+1) + 1 calibrate = 52
            expect(ctx.result.total_llm_calls).to.equal(52)
        end)

    it("marks needs_investigation when confidence < threshold", function()
        local store = fresh_store()
        install_stubs(store, { confidence = 0.4 })
        local deep_panel = require("recipe_deep_panel")
        local ctx = deep_panel.run({
            task = "t", task_id = "main2",
            p_estimate = 0.7, confidence_threshold = 0.7,
        })
        expect(ctx.result.needs_investigation).to.equal(true)
        expect(ctx.result.confidence).to.equal(0.4)
    end)

    it("fires Stage 3b ensemble_div when ctx.ground_truth is numeric",
        function()
            local store = fresh_store()
            install_stubs(store, {
                ab_mcts_answers = {
                    branch_1 = "10", branch_2 = "12", branch_3 = "14",
                },
            })
            local deep_panel = require("recipe_deep_panel")
            local ctx = deep_panel.run({
                task = "pick a number",
                task_id = "main3",
                p_estimate = 0.7,
                ground_truth = 12,
            })
            expect(ctx.result.aborted).to.equal(false)
            expect(type(ctx.result.decomp)).to.equal("table")
            expect(ctx.result.decomp.identity_holds).to.equal(true)
            expect(ctx.result.decomp.A_bar > 0).to.equal(true)
        end)

    it("skips Stage 3b when ground_truth absent", function()
        local store = fresh_store()
        install_stubs(store)
        local deep_panel = require("recipe_deep_panel")
        local ctx = deep_panel.run({
            task = "t", task_id = "main4",
            p_estimate = 0.7,
        })
        expect(ctx.result.decomp).to.equal(nil)
        expect(ctx.result.diversity.decomp_status:find("skipped"))
            .to_not.equal(nil)
    end)

    it("skips Stage 3b when answers are not numeric despite ground_truth",
        function()
            local store = fresh_store()
            install_stubs(store, {
                ab_mcts_answers = {
                    branch_1 = "apple",
                    branch_2 = "banana",
                    branch_3 = "cherry",
                },
            })
            local deep_panel = require("recipe_deep_panel")
            local ctx = deep_panel.run({
                task = "t", task_id = "main5",
                p_estimate = 0.7, ground_truth = 42,
            })
            expect(ctx.result.decomp).to.equal(nil)
            expect(ctx.result.diversity.decomp_status:find("not all"))
                .to_not.equal(nil)
        end)
end)

-- ─── Token tampering ───

describe("recipe_deep_panel.run (token tampering)", function()
    lust.after(reset)

    it("errors when a branch echoes a tampered token", function()
        local store = fresh_store()
        install_stubs(store, { tamper_token_on_slot = "branch_2" })
        local deep_panel = require("recipe_deep_panel")
        local ok, err = pcall(deep_panel.run, {
            task = "t", task_id = "tamp1", p_estimate = 0.7,
        })
        expect(ok).to.equal(false)
        expect(tostring(err):find("branch_2")).to_not.equal(nil)
        expect(tostring(err):find("token/slot mismatch")).to_not.equal(nil)
    end)
end)

-- ─── Resume ───

describe("recipe_deep_panel.run (resume)", function()
    lust.after(reset)

    it("does not re-invoke ab_mcts for branches already persisted",
        function()
            local store = fresh_store()
            install_stubs(store, {
                ab_mcts_answers = {
                    branch_1 = "A", branch_2 = "A", branch_3 = "B",
                },
            })
            local deep_panel = require("recipe_deep_panel")
            deep_panel.run({
                task = "t", task_id = "res1", p_estimate = 0.7,
            })

            -- Second run: install stubs that count ab_mcts invocations.
            local ab_calls = 0
            install_stubs(store)
            local real_run = package.loaded["ab_mcts"].run
            package.loaded["ab_mcts"].run = function(p)
                ab_calls = ab_calls + 1
                return real_run(p)
            end
            local deep_panel2 = require("recipe_deep_panel")
            local ctx = deep_panel2.run({
                task = "t", task_id = "res1",
                p_estimate = 0.7, resume = true,
            })
            expect(ab_calls).to.equal(0)
            expect(ctx.result.answer).to.equal("A")
            expect(ctx.result.panel_size).to.equal(3)
        end)

    it("completes unfinished branches on resume", function()
        local store = fresh_store()
        install_stubs(store)
        -- Seed state manually to simulate: 2 of 3 branches already done.
        store["recipe_deep_panel:res2"] = {
            data = {
                branches = {
                    branch_1 = { approach = "a", answer = "X",
                        best_score = 0.9 },
                    branch_2 = { approach = "b", answer = "X",
                        best_score = 0.9 },
                },
                _token = "prev-token",
            },
            _token = "prev-token",
        }
        local deep_panel = require("recipe_deep_panel")
        local ctx = deep_panel.run({
            task = "t", task_id = "res2",
            p_estimate = 0.7, resume = true,
        })
        expect(ctx.result.panel_size).to.equal(3)
        expect(ctx.result.branches.branch_1.answer).to.equal("X")
        expect(ctx.result.branches.branch_2.answer).to.equal("X")
        expect(ctx.result.branches.branch_3.answer).to.equal("ans:branch_3")
    end)
end)

-- ─── Stage 4 plurality ───

describe("recipe_deep_panel.run (Stage 4 plurality)", function()
    lust.after(reset)

    it("expected_accuracy matches condorcet.prob_majority(n, p)",
        function()
            local store = fresh_store()
            install_stubs(store)
            local deep_panel = require("recipe_deep_panel")
            local condorcet = require("condorcet")
            local ctx = deep_panel.run({
                task = "t", task_id = "p4a",
                p_estimate = 0.7, n_branches = 3,
            })
            local expected = condorcet.prob_majority(3, 0.7)
            expect(math.abs(ctx.result.expected_accuracy - expected) < 1e-9)
                .to.equal(true)
        end)
end)
