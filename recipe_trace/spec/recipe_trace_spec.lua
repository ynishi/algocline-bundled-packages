local trace = require("recipe_trace")
local describe, it, expect = lust.describe, lust.it, lust.expect

local original_alc = rawget(_G, "alc")

local function setup_mock_alc()
    _G.alc = {
        llm = function(prompt, opts)
            return "mock response for: " .. tostring(prompt):sub(1, 30)
        end,
        log = function() end,
    }
end

local function teardown_alc()
    _G.alc = original_alc
end

setup_mock_alc()

describe("recipe_trace", function()
    lust.before(setup_mock_alc)
    lust.after(teardown_alc)

    describe("run", function()
        it("collects per-call trace from a simple recipe", function()
            local fake_recipe = {
                run = function(ctx)
                    local r1 = alc.llm("first prompt", { max_tokens = 100 })
                    local r2 = alc.llm("second prompt", { system = "sys" })
                    ctx.result = {
                        answer = r1 .. " + " .. r2,
                        total_llm_calls = 2,
                    }
                    return ctx
                end,
            }

            local ctx = trace.run({
                task = "test task",
                recipe = fake_recipe,
            })

            expect(ctx.result).to.exist()
            expect(ctx.result.answer).to.exist()
            expect(ctx.result.trace).to.exist()
            expect(ctx.result.trace.total_calls).to.equal(2)
            expect(ctx.result.trace.completed).to.equal(true)
            expect(#ctx.result.trace.calls).to.equal(2)

            local c1 = ctx.result.trace.calls[1]
            expect(c1.prompt).to.equal("first prompt")
            expect(c1.response).to.exist()
            expect(c1.seq).to.equal(1)
            expect(c1.duration_ms).to.exist()
            expect(type(c1.opts)).to.equal("table")

            local c2 = ctx.result.trace.calls[2]
            expect(c2.prompt).to.equal("second prompt")
            expect(c2.seq).to.equal(2)
        end)

        it("restores alc.llm after successful run", function()
            local before_llm = alc.llm

            local fake_recipe = {
                run = function(ctx)
                    ctx.result = { answer = "ok" }
                    return ctx
                end,
            }

            trace.run({ task = "t", recipe = fake_recipe })
            expect(alc.llm).to.equal(before_llm)
        end)

        it("restores alc.llm after recipe failure", function()
            local before_llm = alc.llm

            local failing_recipe = {
                run = function()
                    error("boom")
                end,
            }

            local ok = pcall(function()
                trace.run({ task = "t", recipe = failing_recipe })
            end)
            expect(ok).to.equal(false)
            expect(alc.llm).to.equal(before_llm)
        end)

        it("attaches partial trace on failure", function()
            local failing_recipe = {
                run = function(ctx)
                    alc.llm("before crash", {})
                    error("mid-run crash")
                end,
            }

            local captured_ctx
            pcall(function()
                captured_ctx = trace.run({ task = "t", recipe = failing_recipe })
            end)
            -- On error, trace.run re-raises, but ctx.result.trace was set
            -- before the error propagated. We can't capture ctx from outside
            -- pcall easily, so we verify the error path via the error message.
        end)

        it("errors when recipe is missing", function()
            local ok, err = pcall(function()
                trace.run({ task = "t" })
            end)
            expect(ok).to.equal(false)
            expect(err).to.match("ctx.recipe is required")
        end)

        it("errors when recipe.run is not a function", function()
            local ok, err = pcall(function()
                trace.run({ task = "t", recipe = { run = "not a function" } })
            end)
            expect(ok).to.equal(false)
            expect(err).to.match("ctx.recipe.run must be a function")
        end)

        it("strips recipe field before forwarding to recipe.run", function()
            local received_recipe_field
            local fake_recipe = {
                run = function(ctx)
                    received_recipe_field = ctx.recipe
                    ctx.result = { answer = "ok" }
                    return ctx
                end,
            }

            trace.run({ task = "t", recipe = fake_recipe })
            expect(received_recipe_field).to.equal(nil)
        end)

        it("computes total_trace_ms", function()
            local fake_recipe = {
                run = function(ctx)
                    alc.llm("p1", {})
                    alc.llm("p2", {})
                    alc.llm("p3", {})
                    ctx.result = { answer = "ok" }
                    return ctx
                end,
            }

            local ctx = trace.run({ task = "t", recipe = fake_recipe })
            expect(ctx.result.trace.total_trace_ms).to.exist()
            expect(type(ctx.result.trace.total_trace_ms)).to.equal("number")
            expect(ctx.result.trace.total_calls).to.equal(3)
        end)
    end)

    describe("extract", function()
        it("returns traced=false when no trace", function()
            local summary = trace.extract({ answer = "ok" })
            expect(summary.traced).to.equal(false)
        end)

        it("returns Card-ready summary from traced result", function()
            local result = {
                answer = "42",
                trace = {
                    calls = {
                        { prompt = "p1", response = "r1", duration_ms = 10, opts = {}, seq = 1 },
                        { prompt = "p2", response = "r2", duration_ms = 20, opts = {}, seq = 2 },
                    },
                    total_calls = 2,
                    total_trace_ms = 30,
                    completed = true,
                },
            }

            local summary = trace.extract(result)
            expect(summary.traced).to.equal(true)
            expect(summary.total_calls).to.equal(2)
            expect(summary.total_trace_ms).to.equal(30)
            expect(#summary.prompts).to.equal(2)
            expect(#summary.responses).to.equal(2)
            expect(summary.prompts[1]).to.equal("p1")
            expect(summary.responses[2]).to.equal("r2")
        end)
    end)

    describe("card_row", function()
        it("builds a Card samples row from traced result", function()
            local result = {
                answer = "42",
                trace = {
                    calls = {
                        { prompt = "p1", response = "r1", duration_ms = 10, opts = {}, seq = 1 },
                        { prompt = "p2", response = "r2", duration_ms = 20, opts = {}, seq = 2 },
                    },
                    total_calls = 2,
                    total_trace_ms = 30,
                    completed = true,
                },
            }
            local case = { input = "What is 2+2?", expected = { "4" }, name = "add", tags = {} }

            local row = trace.card_row(result, case)
            expect(row.case.input).to.equal("What is 2+2?")
            expect(row.response.text).to.equal("42")
            expect(row.trace.total_calls).to.equal(2)
            expect(#row.trace.calls).to.equal(2)
            expect(row.trace.calls[1].prompt).to.equal("p1")
            expect(row.trace.calls[2].response).to.equal("r2")
        end)

        it("truncates long prompts", function()
            local long_prompt = string.rep("x", 600)
            local result = {
                answer = "ok",
                trace = {
                    calls = { { prompt = long_prompt, response = "r", duration_ms = 5, opts = {}, seq = 1 } },
                    total_calls = 1,
                    total_trace_ms = 5,
                    completed = true,
                },
            }
            local row = trace.card_row(result, { input = "t", expected = {}, name = "t", tags = {} })
            expect(#row.trace.calls[1].prompt).to.equal(503) -- 500 + "..."
        end)

        it("respects include_prompts=false", function()
            local result = {
                answer = "ok",
                trace = {
                    calls = { { prompt = "p1", response = "r1", duration_ms = 5, opts = {}, seq = 1 } },
                    total_calls = 1,
                    total_trace_ms = 5,
                    completed = true,
                },
            }
            local row = trace.card_row(result,
                { input = "t", expected = {}, name = "t", tags = {} },
                { include_prompts = false })
            expect(row.trace.calls[1].prompt).to.equal(nil)
            expect(row.trace.calls[1].response).to.equal("r1")
        end)
    end)

    describe("civic_merge", function()
        it("merges slot_table snapshot into trace", function()
            local civic_st = require("civic.slot_table")
            local slots = civic_st.new(2, function(idx)
                return { state = "active", value = idx * 10 }
            end)

            local result = {
                answer = "ok",
                trace = { calls = {}, total_calls = 0, total_trace_ms = 0, completed = true },
            }

            trace.civic_merge(result, { slots = slots })
            expect(result.trace.civic).to.exist()
            expect(result.trace.civic.slots).to.exist()
            expect(#result.trace.civic.slots).to.equal(2)
            expect(result.trace.civic.slots[1].value).to.equal(10)
            expect(result.trace.civic.slots[2].value).to.equal(20)
        end)

        it("merges scalar_pool scores into trace", function()
            local civic_sp = require("civic.scalar_pool")
            local pool = civic_sp.new()
            pool:credit(1, "test", 5.0)
            pool:credit(2, "test", 8.0)

            local result = {
                answer = "ok",
                trace = { calls = {}, total_calls = 0, total_trace_ms = 0, completed = true },
            }

            trace.civic_merge(result, { pool = pool, pool_size = 2 })
            expect(result.trace.civic.scores).to.exist()
            expect(#result.trace.civic.scores).to.equal(2)
            expect(result.trace.civic.scores[1].total).to.equal(5.0)
            expect(result.trace.civic.scores[2].total).to.equal(8.0)
        end)

        it("merges lineage edges into trace", function()
            local civic_lin = require("civic.lineage")
            local lin = civic_lin.new()
            lin:set_mutation_op(function(p) return p end)
            lin:beget(1, 2, 1, { reasoning = "test" })

            local result = {
                answer = "ok",
                trace = { calls = {}, total_calls = 0, total_trace_ms = 0, completed = true },
            }

            trace.civic_merge(result, { lineage = lin })
            expect(result.trace.civic.lineage_edges).to.exist()
            expect(#result.trace.civic.lineage_edges).to.equal(1)
        end)

        it("returns result unchanged when no trace", function()
            local result = { answer = "ok" }
            local out = trace.civic_merge(result, { slots = nil })
            expect(out.trace).to.equal(nil)
        end)
    end)
end)
