--- Tests for moa v0.2.0 (Wang 2024 Mixture-of-Agents, paper-explicit).
---
--- Coverage:
---   * M.meta / M.spec / M._defaults structural
---   * AS_PROMPT_TEMPLATE verbatim from Wang 2024 Table 1
---   * build_proposer_prompt: layer-1 (no prev) + layer-2+ (with prev)
---     + override + validation
---   * build_aggregator_prompt: AS_PROMPT application + override + reject
---     empty / non-table
---   * M._internal.format_responses_for_aggregator: numbered listing
---   * M._internal.resolve_proposers: proposers path (paper) / personas
---     path (alt) / neither (reject)
---   * M.run end-to-end with mock alc: L · (n+1) LLM call count, layer
---     records shape, x_{i+1} = y_i propagation (prev aggregated visible
---     in next layer's proposer prompts), model id propagation,
---     temperature / max_tokens propagation, error paths

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

for _, name in ipairs({ "moa", "alc_shapes", "alc_shapes.t",
                       "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["moa"] = nil
    _G.alc = nil
end

local function make_alc_stub(opts)
    opts = opts or {}
    local fixtures = opts.fixtures or {}
    local call_log = {}

    local stub = {}
    stub.llm = function(prompt, llm_opts)
        call_log[#call_log + 1] = {
            prompt = prompt,
            opts = llm_opts,
        }
        local idx = #call_log
        if type(fixtures) == "function" then
            return fixtures(idx, prompt, llm_opts)
        end
        return fixtures[idx] or string.format("response_%d", idx)
    end

    stub.log = function() end

    return stub, call_log
end

-- ─── M.meta / M.spec / M._defaults ───

describe("moa.meta", function()
    lust.after(reset)

    it("declares name / version 0.2.0 / category aggregation", function()
        _G.alc = {}
        local m = require("moa")
        expect(m.meta.name).to.equal("moa")
        expect(m.meta.version).to.equal("0.2.0")
        expect(m.meta.category).to.equal("aggregation")
    end)
end)

describe("moa.spec", function()
    lust.after(reset)

    it("exposes 3 entries: 2 pure helpers + run", function()
        _G.alc = {}
        local m = require("moa")
        expect(type(m.spec.entries.build_proposer_prompt)).to.equal("table")
        expect(type(m.spec.entries.build_aggregator_prompt)).to.equal("table")
        expect(type(m.spec.entries.run)).to.equal("table")
    end)

    it("pure entries use args (direct-args), run uses input", function()
        _G.alc = {}
        local m = require("moa")
        local e = m.spec.entries
        expect(e.build_proposer_prompt.args).to_not.equal(nil)
        expect(e.build_proposer_prompt.input).to.equal(nil)
        expect(e.build_aggregator_prompt.args).to_not.equal(nil)
        expect(e.run.input).to_not.equal(nil)
        expect(e.run.args).to.equal(nil)
    end)
end)

describe("moa._defaults", function()
    lust.after(reset)

    it("matches Wang 2024 §3 (L) values: n_layers=3, n_proposers=6", function()
        _G.alc = {}
        local m = require("moa")
        expect(m._defaults.n_layers).to.equal(3)
        expect(m._defaults.n_proposers).to.equal(6)
    end)

    it("temperature default 0.7 (X paper not fixed, matches single-proposer ablation)", function()
        _G.alc = {}
        local m = require("moa")
        expect(m._defaults.temperature).to.equal(0.7)
    end)

    it("proposer_tokens=512, aggregator_tokens=2048 (X infrastructure)", function()
        _G.alc = {}
        local m = require("moa")
        expect(m._defaults.proposer_tokens).to.equal(512)
        expect(m._defaults.aggregator_tokens).to.equal(2048)
    end)
end)

describe("moa.AS_PROMPT_TEMPLATE", function()
    lust.after(reset)

    it("includes Wang 2024 Table 1 verbatim opening", function()
        _G.alc = {}
        local m = require("moa")
        expect(m.AS_PROMPT_TEMPLATE:find(
            "You have been provided with a set of responses from various open%-source models",
            1)).to_not.equal(nil)
    end)

    it("instructs to critically evaluate / synthesize", function()
        _G.alc = {}
        local m = require("moa")
        expect(m.AS_PROMPT_TEMPLATE:find("critically evaluate", 1, true))
            .to_not.equal(nil)
        expect(m.AS_PROMPT_TEMPLATE:find("synthesize these responses", 1, true))
            .to_not.equal(nil)
    end)

    it("has %s slot for the proposer responses block", function()
        _G.alc = {}
        local m = require("moa")
        expect(m.AS_PROMPT_TEMPLATE:find("%%s", 1)).to_not.equal(nil)
    end)
end)

-- ─── build_proposer_prompt ───

describe("moa.build_proposer_prompt", function()
    lust.after(reset)

    it("layer-1 (no aggregated_prev): includes task only", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_proposer_prompt({ task = "Q" })
        expect(r.prompt:find("Q", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("prior aggregated", 1, true)).to.equal(nil)
        expect(type(r.system)).to.equal("string")
    end)

    it("layer-2+ (with aggregated_prev): includes prev as context", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_proposer_prompt({
            task = "Q",
            aggregated_prev = "previous-synth",
        })
        expect(r.prompt:find("Q", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("previous-synth", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("prior aggregated", 1, true)).to_not.equal(nil)
    end)

    it("respects custom proposer_prompt override (2 %s: task, prev)", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_proposer_prompt({
            task = "T",
            aggregated_prev = "P",
            proposer_prompt = "TASK=%s PREV=%s",
        })
        expect(r.prompt).to.equal("TASK=T PREV=P")
    end)

    it("respects custom system_prompt", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_proposer_prompt({
            task = "T",
            system_prompt = "Custom S",
        })
        expect(r.system).to.equal("Custom S")
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("moa")
        local ok = pcall(m.build_proposer_prompt, {})
        expect(ok).to.equal(false)
    end)
end)

-- ─── build_aggregator_prompt ───

describe("moa.build_aggregator_prompt", function()
    lust.after(reset)

    it("applies AS_PROMPT_TEMPLATE to proposer responses", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_aggregator_prompt({
            proposer_responses = { "Resp1", "Resp2", "Resp3" },
        })
        -- AS_PROMPT opening present
        expect(r.prompt:find("You have been provided with a set of responses",
            1, true)).to_not.equal(nil)
        -- Numbered listing
        expect(r.prompt:find("1. Resp1", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("2. Resp2", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("3. Resp3", 1, true)).to_not.equal(nil)
    end)

    it("accepts custom aggregator_prompt override (1 %s: responses block)", function()
        _G.alc = {}
        local m = require("moa")
        local r = m.build_aggregator_prompt({
            proposer_responses = { "A" },
            aggregator_prompt = "RESPS=[%s]",
        })
        expect(r.prompt:find("RESPS=%[", 1)).to_not.equal(nil)
        expect(r.prompt:find("A", 1, true)).to_not.equal(nil)
    end)

    it("rejects empty proposer_responses", function()
        _G.alc = {}
        local m = require("moa")
        local ok = pcall(m.build_aggregator_prompt, { proposer_responses = {} })
        expect(ok).to.equal(false)
    end)

    it("rejects non-table args", function()
        _G.alc = {}
        local m = require("moa")
        local ok = pcall(m.build_aggregator_prompt, "string")
        expect(ok).to.equal(false)
    end)
end)

-- ─── M._internal helpers ───

describe("moa._internal.format_responses_for_aggregator", function()
    lust.after(reset)

    it("numbers responses 1., 2., …", function()
        _G.alc = {}
        local m = require("moa")
        local s = m._internal.format_responses_for_aggregator({ "x", "y" })
        expect(s:find("1. x", 1, true)).to_not.equal(nil)
        expect(s:find("2. y", 1, true)).to_not.equal(nil)
    end)
end)

describe("moa._internal.resolve_proposers", function()
    lust.after(reset)

    it("returns proposers as-is when given (paper-faithful path)", function()
        _G.alc = {}
        local m = require("moa")
        local specs, path = m._internal.resolve_proposers({
            proposers = { { model = "m1" }, { model = "m2" } },
        })
        expect(#specs).to.equal(2)
        expect(specs[1].model).to.equal("m1")
        expect(path).to.equal("proposers")
    end)

    it("wraps personas as { system = persona } (alt path)", function()
        _G.alc = {}
        local m = require("moa")
        local specs, path = m._internal.resolve_proposers({
            personas = { "Analyst", "Critic" },
        })
        expect(#specs).to.equal(2)
        expect(specs[1].system).to.equal("Analyst")
        expect(specs[2].system).to.equal("Critic")
        expect(path).to.equal("personas")
    end)

    it("rejects when neither proposers nor personas given", function()
        _G.alc = {}
        local m = require("moa")
        local ok, err = pcall(m._internal.resolve_proposers, { task = "T" })
        expect(ok).to.equal(false)
        expect(err:match("REQUIRED")).to_not.equal(nil)
    end)

    it("rejects empty proposers array", function()
        _G.alc = {}
        local m = require("moa")
        local ok = pcall(m._internal.resolve_proposers, { proposers = {} })
        expect(ok).to.equal(false)
    end)

    it("rejects non-string persona", function()
        _G.alc = {}
        local m = require("moa")
        local ok = pcall(m._internal.resolve_proposers, { personas = { "ok", 42 } })
        expect(ok).to.equal(false)
    end)
end)

-- ─── M.run end-to-end ───

describe("moa.run", function()
    lust.after(reset)

    it("personas path L=2 × n=2 makes L·(n+1)=6 LLM calls", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        local ctx = m.run({
            task = "T",
            personas = { "A", "B" },
            n_layers = 2,
        })
        expect(ctx.result.total_llm_calls).to.equal(6)
        expect(#call_log).to.equal(6)
        expect(ctx.result.n_layers).to.equal(2)
        expect(ctx.result.n_proposers).to.equal(2)
    end)

    it("proposers path L=1 × n=3 makes 4 LLM calls", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        local ctx = m.run({
            task = "T",
            proposers = { { model = "m1" }, { model = "m2" }, { model = "m3" } },
            n_layers = 1,
        })
        expect(ctx.result.total_llm_calls).to.equal(4)
        expect(ctx.result.n_proposers).to.equal(3)
    end)

    it("layer aggregator output becomes next layer's aggregated_prev (x_{i+1}=y_i)", function()
        local fixtures = {
            -- layer 1: 2 proposers + aggregator
            "L1_P1", "L1_P2", "L1_AGG",
            -- layer 2: 2 proposers + aggregator
            "L2_P1", "L2_P2", "L2_AGG",
        }
        local alc_stub, call_log = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("moa")
        m.run({
            task = "T",
            personas = { "PA", "PB" },
            n_layers = 2,
        })
        -- Calls 4 and 5 are layer-2 proposers; they should see L1_AGG.
        expect(call_log[4].prompt:find("L1_AGG", 1, true)).to_not.equal(nil)
        expect(call_log[4].prompt:find("prior aggregated", 1, true))
            .to_not.equal(nil)
        expect(call_log[5].prompt:find("L1_AGG", 1, true)).to_not.equal(nil)
        -- Calls 1 and 2 are layer-1 proposers; they should NOT see any
        -- prior aggregated (it doesn't exist yet).
        expect(call_log[1].prompt:find("prior aggregated", 1, true))
            .to.equal(nil)
    end)

    it("final answer is the last layer's aggregator output", function()
        local fixtures = {
            "p1a", "p1b", "AGG_L1",
            "p2a", "p2b", "AGG_L2",
            "p3a", "p3b", "AGG_FINAL",
        }
        local alc_stub = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("moa")
        local ctx = m.run({
            task = "T",
            personas = { "A", "B" },
            n_layers = 3,
        })
        expect(ctx.result.answer).to.equal("AGG_FINAL")
        expect(#ctx.result.layers).to.equal(3)
        expect(ctx.result.layers[1].aggregated).to.equal("AGG_L1")
        expect(ctx.result.layers[2].aggregated).to.equal("AGG_L2")
        expect(ctx.result.layers[3].aggregated).to.equal("AGG_FINAL")
    end)

    it("layer records contain per-proposer outputs in order", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        local ctx = m.run({
            task = "T",
            personas = { "A", "B" },
            n_layers = 1,
        })
        expect(#ctx.result.layers).to.equal(1)
        expect(#ctx.result.layers[1].proposers).to.equal(2)
        expect(ctx.result.layers[1].proposers[1].proposer).to.equal(1)
        expect(ctx.result.layers[1].proposers[2].proposer).to.equal(2)
        expect(type(ctx.result.layers[1].proposers[1].text)).to.equal("string")
    end)

    it("propagates model id from proposers spec to LLM opts", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        m.run({
            task = "T",
            proposers = { { model = "modelA" }, { model = "modelB" } },
            n_layers = 1,
        })
        expect(call_log[1].opts.model).to.equal("modelA")
        expect(call_log[2].opts.model).to.equal("modelB")
        -- Aggregator call (3rd) has no model: caller's responsibility.
        expect(call_log[3].opts.model).to.equal(nil)
    end)

    it("propagates per-proposer system prompt", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        m.run({
            task = "T",
            proposers = {
                { model = "m1", system = "SysA" },
                { model = "m2", system = "SysB" },
            },
            n_layers = 1,
        })
        expect(call_log[1].opts.system).to.equal("SysA")
        expect(call_log[2].opts.system).to.equal("SysB")
    end)

    it("propagates temperature / max_tokens to LLM opts", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("moa")
        m.run({
            task = "T",
            personas = { "A", "B" },
            n_layers = 1,
            temperature = 0.4,
            proposer_tokens = 333,
            aggregator_tokens = 777,
        })
        -- Proposer calls (1, 2)
        for i = 1, 2 do
            expect(call_log[i].opts.temperature).to.equal(0.4)
            expect(call_log[i].opts.max_tokens).to.equal(333)
        end
        -- Aggregator call (3)
        expect(call_log[3].opts.temperature).to.equal(0.4)
        expect(call_log[3].opts.max_tokens).to.equal(777)
    end)

    it("rejects when neither proposers nor personas given", function()
        _G.alc = make_alc_stub()
        local m = require("moa")
        local ok = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
    end)

    it("rejects missing task", function()
        _G.alc = make_alc_stub()
        local m = require("moa")
        local ok = pcall(m.run, { personas = { "A" } })
        expect(ok).to.equal(false)
    end)

    it("rejects n_layers < 1", function()
        _G.alc = make_alc_stub()
        local m = require("moa")
        local ok = pcall(m.run, { task = "T", personas = { "A" }, n_layers = 0 })
        expect(ok).to.equal(false)
    end)

    it("rejects when alc host is unavailable", function()
        _G.alc = nil
        package.loaded["moa"] = nil
        local m = require("moa")
        local ok, err = pcall(m.run, { task = "T", personas = { "A" } })
        expect(ok).to.equal(false)
        expect(err:match("alc host")).to_not.equal(nil)
    end)
end)
