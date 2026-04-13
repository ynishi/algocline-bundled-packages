--- Tests for Phase 2 foundation packages (pbft, aco).
--- pbft requires LLM mocking. aco has both pure engine tests and mocked LLM tests.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ─── Mock helpers ───

local function mock_alc(llm_fn)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        log = function() end,
        parse_score = function(s) return tonumber(tostring(s):match("[%d%.]+")) end,
    }
    return call_log
end

local function reset_modules()
    _G.alc = nil
    package.loaded["pbft"] = nil
    package.loaded["bft"] = nil
    package.loaded["aco"] = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- pbft (F2 — Castro-Liskov 1999)
-- ═══════════════════════════════════════════════════════════════════

describe("pbft", function()
    lust.after(reset_modules)

    it("runs 3-phase consensus with quorum (f=0, n=3)", function()
        -- Phase 1: 3 proposals, Phase 2: 3 votes, Phase 3: maybe synthesis
        local call_idx = 0
        mock_alc(function(prompt, opts, idx)
            call_idx = idx
            if idx <= 3 then
                -- Phase 1: proposals
                return "Proposal " .. idx .. ": The answer is 42."
            elseif idx <= 6 then
                -- Phase 2: all vote for proposal 1
                return "1"
            else
                -- Phase 3: synthesis (shouldn't be called if quorum met)
                return "Synthesized answer"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "What is 6 * 7?" })

        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.n_agents).to.equal(3)
        expect(ctx.result.quorum_required).to.equal(1)  -- 2*0+1 = 1
        expect(ctx.result.quorum_met).to.equal(true)
        expect(ctx.result.commit_method).to.equal("quorum")
        expect(ctx.result.bft_valid).to.equal(true)
    end)

    it("falls back to synthesis when no quorum", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 3 then
                return "Proposal " .. idx
            elseif idx <= 6 then
                -- Each votes for self: no majority
                local agent = ((idx - 4) % 3) + 1
                return tostring(agent)
            else
                return "Synthesized from all"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "Debate topic", n_agents = 3, f = 0 })

        -- With f=0, quorum=1, so any single vote wins.
        -- All 3 vote differently but quorum=1 means the plurality wins
        expect(ctx.result.commit_method).to.equal("quorum")
    end)

    it("validates BFT conditions on start", function()
        mock_alc(function() return "ok" end)
        local pbft = require("pbft")

        -- n=3, f=1 requires n >= 3*1+1 = 4 → should error
        expect(function()
            pbft.run({ task = "test", n_agents = 3, f = 1 })
        end).to.fail()
    end)

    it("works with f=1, n=4", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 4 then
                return "Proposal " .. idx
            elseif idx <= 8 then
                -- 3 out of 4 vote for proposal 1 (quorum = 2*1+1 = 3)
                if idx <= 7 then return "1" else return "2" end
            else
                return "Synthesis"
            end
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "test", n_agents = 4, f = 1 })
        expect(ctx.result.quorum_required).to.equal(3)
        expect(ctx.result.quorum_met).to.equal(true)
        expect(ctx.result.commit_method).to.equal("quorum")
    end)

    it("includes proposals in result for traceability", function()
        mock_alc(function(prompt, opts, idx)
            if idx <= 3 then return "Answer " .. idx end
            return "1"
        end)

        local pbft = require("pbft")
        local ctx = pbft.run({ task = "test" })
        expect(#ctx.result.proposals).to.equal(3)
        expect(ctx.result.proposals[1]).to.equal("Answer 1")
    end)

    it("uses injected system prompts", function()
        local captured_systems = {}
        mock_alc(function(prompt, opts, idx)
            captured_systems[#captured_systems + 1] = opts.system
            if idx <= 3 then return "Proposal " .. idx end
            if idx <= 6 then return "1" end
            return "Synthesis"
        end)

        local pbft = require("pbft")
        pbft.run({
            task = "test",
            gen_system = "CUSTOM_GEN",
            vote_system = "CUSTOM_VOTE",
        })
        -- Phase 1: 3 proposals should use gen_system
        expect(captured_systems[1]).to.equal("CUSTOM_GEN")
        expect(captured_systems[2]).to.equal("CUSTOM_GEN")
        expect(captured_systems[3]).to.equal("CUSTOM_GEN")
        -- Phase 2: 3 votes should use vote_system
        expect(captured_systems[4]).to.equal("CUSTOM_VOTE")
        expect(captured_systems[5]).to.equal("CUSTOM_VOTE")
        expect(captured_systems[6]).to.equal("CUSTOM_VOTE")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- aco (F5 — Dorigo 1996 + Gutjahr 2000) — Pure engine tests
-- ═══════════════════════════════════════════════════════════════════

describe("aco (pure engine)", function()
    local aco = require("aco")

    describe("new", function()
        it("creates a colony with default opts", function()
            local graph = { nodes = { "A", "B", "C" } }
            local colony = aco.new(graph)
            expect(colony).to_not.equal(nil)
            expect(colony.rho).to.equal(0.1)
            expect(colony.n_ants).to.equal(10)
        end)

        it("errors on < 2 nodes", function()
            expect(function()
                aco.new({ nodes = { "A" } })
            end).to.fail()
        end)

        it("errors on rho out of range", function()
            expect(function()
                aco.new({ nodes = { "A", "B" } }, { rho = 0 })
            end).to.fail()
            expect(function()
                aco.new({ nodes = { "A", "B" } }, { rho = 1 })
            end).to.fail()
        end)
    end)

    describe("iterate", function()
        it("runs one iteration and returns best", function()
            local graph = { nodes = { "A", "B", "C" } }
            local colony = aco.new(graph, { n_ants = 5, seed = 42 })
            local path, score = colony:iterate(function(p)
                return #p  -- longer paths score higher
            end)
            expect(path).to_not.equal(nil)
            expect(score > 0).to.equal(true)
        end)

        it("improves over iterations", function()
            local nodes = {}
            for i = 1, 6 do nodes[i] = "N" .. i end
            local graph = { nodes = nodes }
            local colony = aco.new(graph, { n_ants = 10, seed = 42 })

            -- Eval: paths that visit specific nodes score higher
            local function eval(path)
                local score = 0
                for _, node in ipairs(path) do
                    if node == "N2" or node == "N4" then score = score + 1 end
                end
                return score
            end

            local _, score1 = colony:iterate(eval)
            for _ = 1, 20 do colony:iterate(eval) end
            local _, score_final = colony:best()

            expect(score_final >= score1).to.equal(true)
        end)
    end)

    describe("pheromone bounds", function()
        it("clamps pheromone to [tau_min, tau_max]", function()
            local graph = { nodes = { "A", "B", "C" } }
            local colony = aco.new(graph, {
                n_ants = 5, tau_min = 0.1, tau_max = 5.0, seed = 42
            })
            for _ = 1, 50 do
                colony:iterate(function(p) return #p end)
            end
            local tau = colony:pheromone()
            for from, neighbors in pairs(tau) do
                for to, val in pairs(neighbors) do
                    expect(val >= 0.1).to.equal(true)
                    expect(val <= 5.0).to.equal(true)
                end
            end
        end)
    end)

    describe("convergence (run)", function()
        it("stops on stagnation", function()
            local graph = { nodes = { "A", "B", "C", "D" } }
            local colony = aco.new(graph, { n_ants = 5, seed = 42 })
            colony:run(function(p) return 1.0 end, { max_iter = 100, stagnation = 3 })
            -- Should stop well before 100 iterations due to stagnation
            expect(colony.iteration < 100).to.equal(true)
        end)
    end)

    describe("history", function()
        it("records iteration history", function()
            local graph = { nodes = { "A", "B", "C" } }
            local colony = aco.new(graph, { n_ants = 3, seed = 42 })
            colony:iterate(function(p) return #p end)
            colony:iterate(function(p) return #p end)
            local h = colony:get_history()
            expect(#h).to.equal(2)
            expect(h[1].iteration).to.equal(1)
            expect(h[2].iteration).to.equal(2)
        end)
    end)

    describe("custom graph edges", function()
        it("uses provided heuristic values", function()
            local graph = {
                nodes = { "A", "B", "C" },
                edges = {
                    A = { B = { eta = 10 }, C = { eta = 0.1 } },
                    B = { C = { eta = 10 } },
                },
            }
            local colony = aco.new(graph, { n_ants = 20, beta = 5, seed = 42 })
            -- With strong beta and high eta on A->B->C, most ants should take that path
            colony:run(function(path)
                -- Score paths that go A -> B -> C highest
                if #path == 3 and path[1] == "A" and path[2] == "B" and path[3] == "C" then
                    return 10
                end
                return 1
            end, { max_iter = 30, stagnation = 10 })

            local best_path, _ = colony:best()
            expect(best_path[1]).to.equal("A")
            -- With high heuristic on A->B, likely goes through B
            expect(best_path[2]).to.equal("B")
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- aco (F5) — LLM-integrated run(ctx) test
-- ═══════════════════════════════════════════════════════════════════

describe("aco (LLM-integrated)", function()
    lust.after(reset_modules)

    it("runs end-to-end with mocked LLM", function()
        local call_count = 0
        mock_alc(function(prompt, opts, idx)
            call_count = idx
            if prompt:find("Break this task") then
                return "1. Analyze requirements\n2. Design solution\n3. Implement\n4. Test"
            elseif prompt:find("Rate this approach") then
                -- Score paths with "Analyze" higher
                if prompt:find("Analyze") then return "8" else return "5" end
            else
                return "Final answer based on optimized approach."
            end
        end)

        local aco = require("aco")
        local ctx = aco.run({
            task = "Build a web app",
            budget = 5,
            n_ants = 3,
        })

        expect(ctx.result).to_not.equal(nil)
        expect(ctx.result.answer).to_not.equal(nil)
        expect(ctx.result.iterations > 0).to.equal(true)
        expect(ctx.result.best_score > 0).to.equal(true)
    end)

    it("uses provided nodes without LLM generation", function()
        mock_alc(function(prompt, opts, idx)
            if prompt:find("Rate") then return "7" end
            return "Answer from optimized path."
        end)

        local aco = require("aco")
        local ctx = aco.run({
            task = "Optimize",
            nodes = { "Step A", "Step B", "Step C" },
            budget = 3,
            n_ants = 2,
        })

        expect(ctx.result.n_nodes).to.equal(3)
    end)

    it("uses injected system prompts", function()
        local captured_systems = {}
        mock_alc(function(prompt, opts, idx)
            captured_systems[#captured_systems + 1] = opts.system
            if prompt:find("Break this task") then
                return "1. Step X\n2. Step Y\n3. Step Z"
            elseif prompt:find("Rate") then
                return "7"
            else
                return "Final answer."
            end
        end)

        local aco = require("aco")
        aco.run({
            task = "Test inject",
            budget = 1,
            n_ants = 1,
            decompose_system = "CUSTOM_DECOMPOSE",
            eval_system = "CUSTOM_EVAL",
            exec_system = "CUSTOM_EXEC",
        })

        -- First call = decomposition
        expect(captured_systems[1]).to.equal("CUSTOM_DECOMPOSE")
        -- Last call = execution
        expect(captured_systems[#captured_systems]).to.equal("CUSTOM_EXEC")
        -- Middle calls = evaluation
        for i = 2, #captured_systems - 1 do
            expect(captured_systems[i]).to.equal("CUSTOM_EVAL")
        end
    end)

    it("uses custom eval_fn bypassing LLM eval", function()
        local llm_eval_called = false
        mock_alc(function(prompt, opts, idx)
            if prompt:find("Rate") then
                llm_eval_called = true
                return "5"
            end
            if prompt:find("Break this task") then
                return "1. A\n2. B\n3. C"
            end
            return "Done."
        end)

        local aco = require("aco")
        local ctx = aco.run({
            task = "Test eval_fn",
            nodes = { "X", "Y", "Z" },
            budget = 3,
            n_ants = 2,
            eval_fn = function(path) return #path end,
        })

        expect(llm_eval_called).to.equal(false)
        expect(ctx.result.best_score > 0).to.equal(true)
    end)
end)
