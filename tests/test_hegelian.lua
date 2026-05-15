--- Tests for hegelian (Abdali 2025 Hegelian dialectical self-reflection).
---
--- Coverage:
---   * M.meta / M.spec / M._defaults / M._theta_range structural
---   * temperature_at: paper formula τ(i) = τ_0 · exp(-θ · i)
---   * build_thesis_prompt / build_antithesis_prompt / build_synthesis_prompt:
---     default template + override + input validation
---   * M.run end-to-end with mock alc: bootstrap thesis + N iterations,
---     LLM call count, iteration log shape, thesis-carry-forward invariant
---
--- All pure helpers are unit-tested without `alc` mocks. `run` uses a
--- minimal `_G.alc` stub that captures call args, opts, and call order.

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

for _, name in ipairs({ "hegelian", "alc_shapes", "alc_shapes.t",
                       "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["hegelian"] = nil
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
        return fixtures[idx] or string.format("response_%d", idx)
    end

    stub.log = function() end

    return stub, call_log
end

-- ─── M.meta / M.spec / M._defaults / M._theta_range ───

describe("hegelian.meta", function()
    lust.after(reset)

    it("declares name / version / description / category", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("hegelian")
        expect(m.meta.version).to.equal("0.1.0")
        expect(type(m.meta.description)).to.equal("string")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("hegelian.spec", function()
    lust.after(reset)

    it("exposes 5 entries: 4 pure helpers + run", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m.spec).to_not.equal(nil)
        expect(m.spec.entries).to_not.equal(nil)
        expect(m.spec.entries.temperature_at).to_not.equal(nil)
        expect(m.spec.entries.build_thesis_prompt).to_not.equal(nil)
        expect(m.spec.entries.build_antithesis_prompt).to_not.equal(nil)
        expect(m.spec.entries.build_synthesis_prompt).to_not.equal(nil)
        expect(m.spec.entries.run).to_not.equal(nil)
    end)

    it("pure entries use args (direct-args mode), run uses input", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m.spec.entries.temperature_at.args).to_not.equal(nil)
        expect(m.spec.entries.build_thesis_prompt.args).to_not.equal(nil)
        expect(m.spec.entries.run.input).to_not.equal(nil)
        expect(m.spec.entries.run.result).to_not.equal(nil)
    end)
end)

describe("hegelian._defaults", function()
    lust.after(reset)

    it("matches Abdali 2025 Table 1 (L) values: tau_0=0.7, tau_a=0.5, N=5", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m._defaults.tau_0).to.equal(0.7)
        expect(m._defaults.tau_a).to.equal(0.5)
        expect(m._defaults.N).to.equal(5)
    end)

    it("theta default 0.3 is within paper-stated range [0.1, 0.5]", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m._defaults.theta).to.equal(0.3)
        expect(m._defaults.theta >= m._theta_range.min).to.equal(true)
        expect(m._defaults.theta <= m._theta_range.max).to.equal(true)
    end)

    it("gen_tokens default present (infrastructure (X))", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m._defaults.gen_tokens).to.equal(600)
    end)
end)

describe("hegelian._theta_range", function()
    lust.after(reset)

    it("exposes (L) Abdali Table 1 range [0.1, 0.5]", function()
        _G.alc = {}
        local m = require("hegelian")
        expect(m._theta_range.min).to.equal(0.1)
        expect(m._theta_range.max).to.equal(0.5)
    end)
end)

-- ─── temperature_at: τ(i) = τ_0 · exp(-θ · i) ───

describe("hegelian.temperature_at", function()
    lust.after(reset)

    it("returns tau_0 unchanged at i=0 (no decay)", function()
        _G.alc = {}
        local m = require("hegelian")
        local tau = m.temperature_at({ iteration = 0, tau_0 = 0.7, theta = 0.3 })
        expect(tau).to.equal(0.7)
    end)

    it("applies decay τ_0 · exp(-θ·i) at i=1", function()
        _G.alc = {}
        local m = require("hegelian")
        local tau = m.temperature_at({ iteration = 1, tau_0 = 0.7, theta = 0.3 })
        local expected = 0.7 * math.exp(-0.3)
        expect(math.abs(tau - expected) < 1e-9).to.equal(true)
    end)

    it("applies cumulative decay at i=5", function()
        _G.alc = {}
        local m = require("hegelian")
        local tau = m.temperature_at({ iteration = 5, tau_0 = 0.7, theta = 0.3 })
        local expected = 0.7 * math.exp(-1.5)
        expect(math.abs(tau - expected) < 1e-9).to.equal(true)
    end)

    it("respects custom tau_0", function()
        _G.alc = {}
        local m = require("hegelian")
        local tau = m.temperature_at({ iteration = 2, tau_0 = 1.0, theta = 0.3 })
        local expected = 1.0 * math.exp(-0.6)
        expect(math.abs(tau - expected) < 1e-9).to.equal(true)
    end)

    it("respects custom theta within range", function()
        _G.alc = {}
        local m = require("hegelian")
        local tau = m.temperature_at({ iteration = 3, tau_0 = 0.7, theta = 0.5 })
        local expected = 0.7 * math.exp(-1.5)
        expect(math.abs(tau - expected) < 1e-9).to.equal(true)
    end)

    it("rejects theta above paper range max", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, { iteration = 0, tau_0 = 0.7, theta = 0.6 })
        expect(ok).to.equal(false)
        expect(err:match("theta must be in")).to_not.equal(nil)
    end)

    it("rejects theta below paper range min", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, { iteration = 0, tau_0 = 0.7, theta = 0.05 })
        expect(ok).to.equal(false)
        expect(err:match("theta must be in")).to_not.equal(nil)
    end)

    it("rejects negative iteration", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, { iteration = -1, tau_0 = 0.7, theta = 0.3 })
        expect(ok).to.equal(false)
        expect(err:match("iteration must be")).to_not.equal(nil)
    end)

    it("rejects non-integer iteration", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, { iteration = 1.5, tau_0 = 0.7, theta = 0.3 })
        expect(ok).to.equal(false)
        expect(err:match("iteration must be")).to_not.equal(nil)
    end)

    it("rejects non-positive tau_0", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, { iteration = 0, tau_0 = 0, theta = 0.3 })
        expect(ok).to.equal(false)
        expect(err:match("tau_0 must be > 0")).to_not.equal(nil)
    end)

    it("rejects non-table args", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.temperature_at, "not a table")
        expect(ok).to.equal(false)
        expect(err:match("args must be a table")).to_not.equal(nil)
    end)
end)

-- ─── build_thesis_prompt ───

describe("hegelian.build_thesis_prompt", function()
    lust.after(reset)

    it("uses default template embedding task", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_thesis_prompt({ task = "Solve X" })
        expect(pp.prompt:match("Task: Solve X")).to_not.equal(nil)
        expect(type(pp.system)).to.equal("string")
        expect(#pp.system > 0).to.equal(true)
    end)

    it("uses default system prompt by default", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_thesis_prompt({ task = "Q" })
        expect(pp.system:match("skilled advocate")).to_not.equal(nil)
    end)

    it("accepts ctx-style override template", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_thesis_prompt({
            task = "Q",
            thesis_prompt = "CUSTOM: %s",
        })
        expect(pp.prompt).to.equal("CUSTOM: Q")
    end)

    it("accepts ctx-style override system prompt", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_thesis_prompt({
            task = "Q",
            system_thesis = "Custom system",
        })
        expect(pp.system).to.equal("Custom system")
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_thesis_prompt, {})
        expect(ok).to.equal(false)
        expect(err:match("task must be a non%-empty string")).to_not.equal(nil)
    end)

    it("rejects empty task", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_thesis_prompt, { task = "" })
        expect(ok).to.equal(false)
        expect(err:match("task must be a non%-empty string")).to_not.equal(nil)
    end)
end)

-- ─── build_antithesis_prompt ───

describe("hegelian.build_antithesis_prompt", function()
    lust.after(reset)

    it("uses default template embedding task + thesis", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_antithesis_prompt({
            task = "Solve X",
            thesis = "X is true",
        })
        expect(pp.prompt:match("Task: Solve X")).to_not.equal(nil)
        expect(pp.prompt:match("X is true")).to_not.equal(nil)
    end)

    it("uses default system prompt (devil's advocate framing)", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_antithesis_prompt({ task = "Q", thesis = "T" })
        expect(pp.system:match("devil")).to_not.equal(nil)
    end)

    it("accepts ctx-style override template", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_antithesis_prompt({
            task = "Q",
            thesis = "T",
            antithesis_prompt = "ARGUE AGAINST %s. THESIS: %s",
        })
        expect(pp.prompt).to.equal("ARGUE AGAINST Q. THESIS: T")
    end)

    it("rejects missing thesis", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_antithesis_prompt, { task = "Q" })
        expect(ok).to.equal(false)
        expect(err:match("thesis must be a non%-empty string")).to_not.equal(nil)
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_antithesis_prompt, { thesis = "T" })
        expect(ok).to.equal(false)
        expect(err:match("task must be a non%-empty string")).to_not.equal(nil)
    end)
end)

-- ─── build_synthesis_prompt ───

describe("hegelian.build_synthesis_prompt", function()
    lust.after(reset)

    it("embeds task / thesis / antithesis / iteration labels", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_synthesis_prompt({
            task = "Solve X",
            thesis = "T position",
            antithesis = "A position",
            iteration = 0,
        })
        expect(pp.prompt:match("Task: Solve X")).to_not.equal(nil)
        expect(pp.prompt:match("T position")).to_not.equal(nil)
        expect(pp.prompt:match("A position")).to_not.equal(nil)
        expect(pp.prompt:match("T_0")).to_not.equal(nil)
        expect(pp.prompt:match("A_0")).to_not.equal(nil)
        expect(pp.prompt:match("T_1")).to_not.equal(nil)
    end)

    it("uses default system prompt (master synthesizer framing)", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_synthesis_prompt({
            task = "Q", thesis = "T", antithesis = "A", iteration = 0,
        })
        expect(pp.system:match("synthesizer")).to_not.equal(nil)
    end)

    it("accepts ctx-style override template", function()
        _G.alc = {}
        local m = require("hegelian")
        local pp = m.build_synthesis_prompt({
            task = "Q", thesis = "T", antithesis = "A", iteration = 2,
            synthesis_prompt = "TASK=%s i=%d T=%s i=%d A=%s NEXT=%d",
        })
        expect(pp.prompt).to.equal("TASK=Q i=2 T=T i=2 A=A NEXT=3")
    end)

    it("rejects missing antithesis", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_synthesis_prompt, {
            task = "Q", thesis = "T", iteration = 0,
        })
        expect(ok).to.equal(false)
        expect(err:match("antithesis must be a non%-empty string")).to_not.equal(nil)
    end)

    it("rejects negative iteration", function()
        _G.alc = {}
        local m = require("hegelian")
        local ok, err = pcall(m.build_synthesis_prompt, {
            task = "Q", thesis = "T", antithesis = "A", iteration = -1,
        })
        expect(ok).to.equal(false)
        expect(err:match("iteration must be")).to_not.equal(nil)
    end)
end)

-- ─── M.run end-to-end ───

describe("hegelian.run", function()
    lust.after(reset)

    it("rejects missing ctx.task", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("task must be a non%-empty string")).to_not.equal(nil)
    end)

    it("default config (N=5) makes 1 + 2*5 = 11 LLM calls", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Solve X" })
        expect(#log).to.equal(11)
    end)

    it("custom N=3 makes 1 + 2*3 = 7 LLM calls", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 3 })
        expect(#log).to.equal(7)
    end)

    it("N=1 makes 1 + 2*1 = 3 LLM calls", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 1 })
        expect(#log).to.equal(3)
    end)

    it("returns ctx.result with paper-aligned fields", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ctx = m.run({ task = "Q", N = 2 })
        expect(type(ctx.result)).to.equal("table")
        expect(type(ctx.result.answer)).to.equal("string")
        expect(type(ctx.result.thesis_0)).to.equal("string")
        expect(type(ctx.result.iterations)).to.equal("table")
        expect(type(ctx.result.final_synthesis)).to.equal("string")
        expect(ctx.result.N).to.equal(2)
        expect(#ctx.result.iterations).to.equal(2)
    end)

    it("answer aliases final_synthesis (last S_i)", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ctx = m.run({ task = "Q", N = 2 })
        expect(ctx.result.answer).to.equal(ctx.result.final_synthesis)
    end)

    it("iteration log records i / antithesis / tau_i / synthesis per iteration", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ctx = m.run({ task = "Q", N = 3, tau_0 = 0.7, theta = 0.3 })
        for i = 1, 3 do
            local entry = ctx.result.iterations[i]
            expect(entry.iteration).to.equal(i - 1)
            expect(type(entry.antithesis)).to.equal("string")
            expect(type(entry.synthesis)).to.equal("string")
            local expected_tau = 0.7 * math.exp(-0.3 * (i - 1))
            expect(math.abs(entry.tau_i - expected_tau) < 1e-9).to.equal(true)
        end
    end)

    it("thesis-carry-forward: iteration i synthesis becomes thesis at i+1", function()
        local stub, log = make_alc_stub({
            fixtures = {
                "T_0_text",
                "A_0_text", "S_0_text",
                "A_1_text", "S_1_text",
            },
        })
        _G.alc = stub
        local m = require("hegelian")
        local ctx = m.run({ task = "Q", N = 2 })
        -- Bootstrap thesis is T_0
        expect(ctx.result.thesis_0).to.equal("T_0_text")
        -- Iteration 0 should see T_0 in antithesis prompt
        expect(log[2].prompt:match("T_0_text")).to_not.equal(nil)
        -- Iteration 1 should see S_0_text (the synthesis from iter 0) as thesis
        expect(log[4].prompt:match("S_0_text")).to_not.equal(nil)
    end)

    it("bootstrap LLM call uses tau_0 temperature", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 1, tau_0 = 0.9 })
        expect(log[1].opts.temperature).to.equal(0.9)
    end)

    it("antithesis LLM call uses tau_a temperature (fixed across iterations)", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 3, tau_a = 0.4 })
        -- Antithesis calls are at log[2], log[4], log[6]
        expect(log[2].opts.temperature).to.equal(0.4)
        expect(log[4].opts.temperature).to.equal(0.4)
        expect(log[6].opts.temperature).to.equal(0.4)
    end)

    it("synthesis LLM call uses annealed temperature τ(i) per Algorithm 1", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 3, tau_0 = 0.7, theta = 0.3 })
        -- Synthesis calls are at log[3], log[5], log[7], for i=0,1,2
        expect(math.abs(log[3].opts.temperature - 0.7 * math.exp(0)) < 1e-9).to.equal(true)
        expect(math.abs(log[5].opts.temperature - 0.7 * math.exp(-0.3)) < 1e-9).to.equal(true)
        expect(math.abs(log[7].opts.temperature - 0.7 * math.exp(-0.6)) < 1e-9).to.equal(true)
    end)

    it("propagates gen_tokens to max_tokens", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 1, gen_tokens = 800 })
        for i = 1, #log do
            expect(log[i].opts.max_tokens).to.equal(800)
        end
    end)

    it("rejects N=0", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = 0 })
        expect(ok).to.equal(false)
        expect(err:match("N must be a positive integer")).to_not.equal(nil)
    end)

    it("rejects N=-1", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = -1 })
        expect(ok).to.equal(false)
        expect(err:match("N must be a positive integer")).to_not.equal(nil)
    end)

    it("rejects non-integer N", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = 2.5 })
        expect(ok).to.equal(false)
        expect(err:match("N must be a positive integer")).to_not.equal(nil)
    end)

    it("rejects tau_0 <= 0", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", tau_0 = 0 })
        expect(ok).to.equal(false)
        expect(err:match("tau_0 must be > 0")).to_not.equal(nil)
    end)

    it("rejects theta outside paper range", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", theta = 0.7 })
        expect(ok).to.equal(false)
        expect(err:match("theta must be in")).to_not.equal(nil)
    end)

    it("rejects gen_tokens <= 0", function()
        local stub = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", gen_tokens = 0 })
        expect(ok).to.equal(false)
        expect(err:match("gen_tokens must be a positive integer")).to_not.equal(nil)
    end)

    it("errors when bootstrap thesis returns empty string", function()
        local stub = make_alc_stub({ fixtures = { "" } })
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = 1 })
        expect(ok).to.equal(false)
        expect(err:match("bootstrap thesis")).to_not.equal(nil)
    end)

    it("errors when antithesis returns empty string mid-iteration", function()
        local stub = make_alc_stub({
            fixtures = { "T_0", "" },  -- bootstrap OK, antithesis empty
        })
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = 1 })
        expect(ok).to.equal(false)
        expect(err:match("antithesis at iteration 0")).to_not.equal(nil)
    end)

    it("errors when synthesis returns empty string", function()
        local stub = make_alc_stub({
            fixtures = { "T_0", "A_0", "" },
        })
        _G.alc = stub
        local m = require("hegelian")
        local ok, err = pcall(m.run, { task = "Q", N = 1 })
        expect(ok).to.equal(false)
        expect(err:match("synthesis at iteration 0")).to_not.equal(nil)
    end)

    it("uses default system prompts by default", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({ task = "Q", N = 1 })
        -- Bootstrap (thesis): "skilled advocate"
        expect(log[1].opts.system:match("skilled advocate")).to_not.equal(nil)
        -- Antithesis: "devil"
        expect(log[2].opts.system:match("devil")).to_not.equal(nil)
        -- Synthesis: "synthesizer"
        expect(log[3].opts.system:match("synthesizer")).to_not.equal(nil)
    end)

    it("accepts ctx system_thesis / system_antithesis / system_synthesis overrides", function()
        local stub, log = make_alc_stub()
        _G.alc = stub
        local m = require("hegelian")
        m.run({
            task = "Q", N = 1,
            system_thesis = "T_SYS",
            system_antithesis = "A_SYS",
            system_synthesis = "S_SYS",
        })
        expect(log[1].opts.system).to.equal("T_SYS")
        expect(log[2].opts.system).to.equal("A_SYS")
        expect(log[3].opts.system).to.equal("S_SYS")
    end)
end)
