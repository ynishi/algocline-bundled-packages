local describe, it, expect = lust.describe, lust.it, lust.expect

local recipe = require("recipe_evolve_reason")
local civic  = require("civic")

describe("recipe_evolve_reason — meta", function()
    it("M.meta has required fields", function()
        expect(recipe.meta.name).to.equal("recipe_evolve_reason")
        expect(recipe.meta.version).to.be.a("string")
        expect(recipe.meta.description).to.be.a("string")
        expect(recipe.meta.category).to.equal("recipe")
    end)

    it("M.spec.entries.run exists", function()
        expect(recipe.spec.entries.run).to.be.a("table")
        expect(recipe.spec.entries.run.result).to.equal("evolved_reason")
    end)

    it("M.ingredients includes civic", function()
        local found = false
        for _, v in ipairs(recipe.ingredients) do
            if v == "civic" then found = true end
        end
        expect(found).to.equal(true)
    end)

    it("M.caveats is a non-empty table", function()
        expect(recipe.caveats).to.be.a("table")
        expect(#recipe.caveats >= 1).to.equal(true)
    end)
end)

describe("recipe_evolve_reason — parameter validation", function()
    it("rejects missing task", function()
        local ok, err = pcall(recipe.run, {})
        expect(ok).to.equal(false)
        expect(err).to.match("ctx.task is required")
    end)

    it("rejects pop_size < 2", function()
        local ok, err = pcall(recipe.run, { task = "test", pop_size = 1 })
        expect(ok).to.equal(false)
        expect(err).to.match("pop_size must be >= 2")
    end)

    it("rejects max_gen < 1", function()
        local ok, err = pcall(recipe.run, { task = "test", max_gen = 0 })
        expect(ok).to.equal(false)
        expect(err).to.match("max_gen must be >= 1")
    end)

    it("rejects elite_ratio = 0", function()
        local ok, err = pcall(recipe.run, { task = "test", elite_ratio = 0 })
        expect(ok).to.equal(false)
        expect(err).to.match("elite_ratio must be in")
    end)

    it("rejects elite_ratio = 1", function()
        local ok, err = pcall(recipe.run, { task = "test", elite_ratio = 1 })
        expect(ok).to.equal(false)
        expect(err).to.match("elite_ratio must be in")
    end)
end)

describe("recipe_evolve_reason — civic integration (pure)", function()
    it("civic.slot_table creates population correctly", function()
        local slots = civic.slot_table.new(4, function(idx)
            return { state = "active", reasoning = "r" .. idx }
        end)
        expect(slots:size()).to.equal(4)
        expect(slots:get(1).reasoning).to.equal("r1")
        expect(slots:get(4).state).to.equal("active")
    end)

    it("civic.scalar_pool accumulates peer scores", function()
        local pool = civic.scalar_pool.new()
        pool:credit(1, "peer_gen1", 8)
        pool:credit(1, "peer_gen1", 7)
        pool:credit(2, "peer_gen1", 3)
        expect(pool:total(1)).to.equal(15)
        expect(pool:total(2)).to.equal(3)
    end)

    it("civic.transition_rules selects elites by threshold", function()
        local rules = civic.transition_rules.new()
        local threshold = 10
        rules:add("active", "elite", function(payload, ctx)
            return ctx.score >= threshold
        end)
        rules:add("active", "eliminated", function(payload, ctx)
            return ctx.score < threshold
        end)

        local elite = rules:apply(
            { state = "active" }, { score = 15 }
        )
        expect(elite.state).to.equal("elite")

        local elim = rules:apply(
            { state = "active" }, { score = 5 }
        )
        expect(elim.state).to.equal("eliminated")
    end)

    it("civic.lineage tracks parent-child with mutation", function()
        local lin = civic.lineage.new()
        lin:set_mutation_op(function(parent_payload)
            return {
                state = "active",
                reasoning = parent_payload.reasoning .. " (improved)",
            }
        end)
        local child = lin:beget(1, 2, 1, {
            state = "elite",
            reasoning = "original",
        })
        expect(child.reasoning).to.equal("original (improved)")
        expect(lin:parent(2)).to.equal(1)
        expect(#lin:edges()).to.equal(1)
    end)

    it("civic.knowledge_channel transfers insight", function()
        local kchan = civic.knowledge_channel.new()
        kchan:set_transform(function(payload, ctx)
            return { insight = "key: " .. payload.reasoning:sub(1, 10) }
        end)
        local result = kchan:transfer(1, 2, { reasoning = "long reasoning text here" })
        expect(result.insight).to.equal("key: long reaso")
    end)
end)

describe("recipe_evolve_reason — evolution flow (mocked alc)", function()
    local call_count = 0
    local original_llm

    lust.before(function()
        call_count = 0
        math.randomseed(12345)
        original_llm = rawget(_G, "alc") and alc.llm or nil
        if not rawget(_G, "alc") then
            rawset(_G, "alc", {})
        end
        alc.llm = function(prompt, opts)
            call_count = call_count + 1
            if prompt:match("Score each reasoning") then
                return "Score_A: 7\nScore_B: 5"
            elseif prompt:match("Extract the single most important") then
                return "The key insight is to use induction."
            elseif prompt:match("Improve this reasoning") then
                return "Improved reasoning: step 1, step 2, conclusion."
            else
                return "Step 1: analyze. Step 2: derive. Answer: 42."
            end
        end
    end)

    lust.after(function()
        if original_llm then
            alc.llm = original_llm
        end
    end)

    it("runs a full evolution with pop_size=4, max_gen=2", function()
        local ctx = recipe.run({
            task = "What is 6 * 7?",
            pop_size = 4,
            max_gen = 2,
            elite_ratio = 0.5,
            gen_tokens = 100,
        })

        expect(ctx.result).to.be.a("table")
        expect(ctx.result.pop_size).to.equal(4)
        expect(ctx.result.generations).to.equal(2)
        expect(ctx.result.total_llm_calls > 0).to.equal(true)
        expect(ctx.result.best_idx >= 1).to.equal(true)
        expect(ctx.result.best_idx <= 4).to.equal(true)
        expect(ctx.result.answer).to.be.a("string")
        expect(#ctx.result.answer > 0).to.equal(true)
    end)

    it("gen_history records per-generation selection", function()
        local ctx = recipe.run({
            task = "Prove sqrt(2) is irrational.",
            pop_size = 4,
            max_gen = 2,
            elite_ratio = 0.5,
        })

        expect(ctx.result.gen_history).to.be.a("table")
        expect(ctx.result.gen_history[1]).to.be.a("table")
        expect(ctx.result.gen_history[1].elites).to.be.a("table")
        local n_elites = #ctx.result.gen_history[1].elites
        local n_elim   = #ctx.result.gen_history[1].eliminated
        expect(n_elites + n_elim).to.equal(4)
        expect(n_elites >= 1).to.equal(true)
        expect(n_elim >= 1).to.equal(true)
    end)

    it("lineage_edges records parent-child relationships", function()
        local ctx = recipe.run({
            task = "test",
            pop_size = 4,
            max_gen = 2,
            elite_ratio = 0.5,
        })

        local edges = ctx.result.lineage_edges
        expect(edges).to.be.a("table")
        expect(#edges >= 1).to.equal(true)
        expect(edges[1].parent).to.be.a("number")
        expect(edges[1].child).to.be.a("number")
    end)

    it("inherit=false skips knowledge channel", function()
        call_count = 0
        local ctx_with = recipe.run({
            task = "test",
            pop_size = 4,
            max_gen = 2,
            elite_ratio = 0.5,
            inherit = true,
        })
        local calls_with = call_count

        call_count = 0
        local ctx_without = recipe.run({
            task = "test",
            pop_size = 4,
            max_gen = 2,
            elite_ratio = 0.5,
            inherit = false,
        })
        local calls_without = call_count

        expect(calls_with > calls_without).to.equal(true)
    end)

    it("pop_size=2, max_gen=1 is minimal viable config", function()
        local ctx = recipe.run({
            task = "1+1?",
            pop_size = 2,
            max_gen = 1,
            elite_ratio = 0.5,
        })
        expect(ctx.result.pop_size).to.equal(2)
        expect(ctx.result.generations).to.equal(1)
        expect(ctx.result.total_llm_calls >= 3).to.equal(true)
    end)
end)
