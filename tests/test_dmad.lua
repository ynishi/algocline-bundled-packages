--- Tests for dmad v0.2.0 (Du 2023 Multi-Agent Debate, paper-explicit).
---
--- Coverage:
---   * M.meta / M.spec / M._defaults structural
---   * DEFAULT_INIT_TEMPLATE / DEFAULT_DEBATE_PREFIX/AGENT_BLOCK/SUFFIX
---     verbatim from Du repo gsm/gen_gsm.py
---   * build_init_prompt: default template + override + input validation
---   * build_debate_prompt: prefix/agent_block/suffix path + full-template
---     override path + per-agent block concatenation
---   * extract_boxed: \boxed{} extraction + last-match preference + fallback
---   * aggregate_majority: strict majority / first-wins tie-break (eval_gsm.py
---     :most_frequent semantics) / tally shape / empty reject
---   * M.run end-to-end with mock alc: N·(R+1) call count, debate_log shape,
---     responses[r+1][i] indexing, last_answers / tally / total_llm_calls,
---     "other agents" exclusion of self in debate prompts
---   * Hegelian path is gone: dialectic_mode parameter is silently ignored
---     (open shape), no thesis/antithesis/synthesis fields in result

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

for _, name in ipairs({ "dmad", "alc_shapes", "alc_shapes.t",
                       "alc_shapes.check", "alc_shapes.reflect" }) do
    package.loaded[name] = nil
end

local function reset()
    package.loaded["dmad"] = nil
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
        return fixtures[idx] or string.format("\\boxed{%d}", idx)
    end

    stub.log = function() end

    return stub, call_log
end

-- ─── M.meta / M.spec / M._defaults ───

describe("dmad.meta", function()
    lust.after(reset)

    it("declares name / version / description / category", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.meta.name).to.equal("dmad")
        expect(m.meta.version).to.equal("0.2.0")
        expect(m.meta.category).to.equal("reasoning")
        expect(type(m.meta.description)).to.equal("string")
    end)
end)

describe("dmad.spec", function()
    lust.after(reset)

    it("exposes 5 entries: 4 pure helpers + run", function()
        _G.alc = {}
        local m = require("dmad")
        local entries = m.spec.entries
        expect(type(entries.run)).to.equal("table")
        expect(type(entries.build_init_prompt)).to.equal("table")
        expect(type(entries.build_debate_prompt)).to.equal("table")
        expect(type(entries.extract_boxed)).to.equal("table")
        expect(type(entries.aggregate_majority)).to.equal("table")
    end)

    it("pure entries use args (direct-args), run uses input", function()
        _G.alc = {}
        local m = require("dmad")
        local e = m.spec.entries
        expect(e.build_init_prompt.args).to_not.equal(nil)
        expect(e.build_init_prompt.input).to.equal(nil)
        expect(e.build_debate_prompt.args).to_not.equal(nil)
        expect(e.extract_boxed.args).to_not.equal(nil)
        expect(e.aggregate_majority.args).to_not.equal(nil)
        expect(e.run.input).to_not.equal(nil)
        expect(e.run.args).to.equal(nil)
    end)
end)

describe("dmad._defaults", function()
    lust.after(reset)

    it("matches Du 2023 repo gen_gsm.py (L): n_agents=3, n_rounds=2", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m._defaults.n_agents).to.equal(3)
        expect(m._defaults.n_rounds).to.equal(2)
    end)

    it("gen_tokens default 500 (X infrastructure)", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m._defaults.gen_tokens).to.equal(500)
    end)

    it("temperature default nil (X, paper not fixed)", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m._defaults.temperature).to.equal(nil)
    end)
end)

-- ─── Verbatim templates ───

describe("dmad.DEFAULT_INIT_TEMPLATE", function()
    lust.after(reset)

    it("matches Du repo gen_gsm.py verbatim (includes \\boxed{answer} sentinel)", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.DEFAULT_INIT_TEMPLATE:find("Can you solve the following math problem%?", 1)).to_not.equal(nil)
        expect(m.DEFAULT_INIT_TEMPLATE:find("Explain your reasoning", 1)).to_not.equal(nil)
        expect(m.DEFAULT_INIT_TEMPLATE:find("\\boxed{answer}", 1, true)).to_not.equal(nil)
        expect(m.DEFAULT_INIT_TEMPLATE:find("%%s", 1)).to_not.equal(nil)
    end)
end)

describe("dmad.DEFAULT_DEBATE_*", function()
    lust.after(reset)

    it("prefix matches Du repo construct_message opening", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.DEFAULT_DEBATE_PREFIX).to.equal(
            "These are the solutions to the problem from other agents: "
        )
    end)

    it("agent_block wraps each other-response between 'One agent solution' markers", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.DEFAULT_DEBATE_AGENT_BLOCK:find("One agent solution", 1, true)).to_not.equal(nil)
        expect(m.DEFAULT_DEBATE_AGENT_BLOCK:find("%%s", 1)).to_not.equal(nil)
    end)

    it("agent_block wraps the response in triple backticks (Du repo gen_gsm.py::construct_message)", function()
        _G.alc = {}
        local m = require("dmad")
        -- Du repo builds per-agent body as:
        --   "\n\n One agent solution: ```{}```"
        -- The Lua transcription must preserve the triple-backtick fence,
        -- not strip it. Earlier versions had `"\n\n One agent solution:
        -- \n\n %s \n\n"` which dropped the wrapper.
        expect(m.DEFAULT_DEBATE_AGENT_BLOCK).to.equal("\n\n One agent solution: ```%s```")
        -- And verify the formatted result wraps the response with the
        -- backticks the LLM is expected to see.
        local formatted = string.format(m.DEFAULT_DEBATE_AGENT_BLOCK, "ANSWER")
        expect(formatted:find("```ANSWER```", 1, true)).to_not.equal(nil)
    end)

    it("build_debate_prompt embeds each other-response in triple backticks", function()
        _G.alc = {}
        local m = require("dmad")
        local pair = m.build_debate_prompt({
            task = "What is 2+2?",
            other_responses = { "FOUR", "QUATRE" },
        })
        expect(pair.prompt:find("```FOUR```", 1, true)).to_not.equal(nil)
        expect(pair.prompt:find("```QUATRE```", 1, true)).to_not.equal(nil)
    end)

    it("suffix asks for updated answer + repeats task + \\boxed{} sentinel", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.DEFAULT_DEBATE_SUFFIX:find("Using the solutions from other agents", 1, true)).to_not.equal(nil)
        expect(m.DEFAULT_DEBATE_SUFFIX:find("original math problem is", 1, true)).to_not.equal(nil)
        expect(m.DEFAULT_DEBATE_SUFFIX:find("\\boxed{answer}", 1, true)).to_not.equal(nil)
        expect(m.DEFAULT_DEBATE_SUFFIX:find("%%s", 1)).to_not.equal(nil)
    end)
end)

-- ─── build_init_prompt ───

describe("dmad.build_init_prompt", function()
    lust.after(reset)

    it("embeds task into default INIT_TEMPLATE", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_init_prompt({ task = "What is 2+2?" })
        expect(r.prompt:find("What is 2+2?", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("Can you solve the following math problem?", 1, true)).to_not.equal(nil)
        expect(type(r.system)).to.equal("string")
    end)

    it("accepts custom init_prompt override", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_init_prompt({
            task = "X",
            init_prompt = "Custom INIT: %s",
        })
        expect(r.prompt).to.equal("Custom INIT: X")
    end)

    it("accepts custom system_prompt override", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_init_prompt({
            task = "X",
            system_prompt = "Custom system",
        })
        expect(r.system).to.equal("Custom system")
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("dmad")
        local ok, err = pcall(m.build_init_prompt, {})
        expect(ok).to.equal(false)
        expect(err:match("task")).to_not.equal(nil)
    end)

    it("rejects non-table args", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.build_init_prompt, "string")
        expect(ok).to.equal(false)
    end)
end)

-- ─── build_debate_prompt ───

describe("dmad.build_debate_prompt", function()
    lust.after(reset)

    it("concatenates per-agent blocks between prefix and suffix", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_debate_prompt({
            task = "Q",
            other_responses = { "A1", "A2" },
        })
        -- prefix present
        expect(r.prompt:find(m.DEFAULT_DEBATE_PREFIX, 1, true)).to_not.equal(nil)
        -- both agent answers present with "One agent solution" wrapper
        local first_marker = r.prompt:find("One agent solution", 1, true)
        local second_marker = r.prompt:find("One agent solution",
            first_marker + 1, true)
        expect(first_marker).to_not.equal(nil)
        expect(second_marker).to_not.equal(nil)
        expect(r.prompt:find("A1", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("A2", 1, true)).to_not.equal(nil)
        -- task footer present
        expect(r.prompt:find("Q", 1, true)).to_not.equal(nil)
    end)

    it("accepts full debate_prompt override (2 %s slots: others / task)", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_debate_prompt({
            task = "T",
            other_responses = { "R1" },
            debate_prompt = "OTHERS=[%s] TASK=[%s]",
        })
        expect(r.prompt:find("OTHERS=", 1, true)).to_not.equal(nil)
        expect(r.prompt:find("TASK=%[T%]", 1)).to_not.equal(nil)
        expect(r.prompt:find("R1", 1, true)).to_not.equal(nil)
    end)

    it("respects custom system_prompt", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.build_debate_prompt({
            task = "T",
            other_responses = { "R1" },
            system_prompt = "Custom S",
        })
        expect(r.system).to.equal("Custom S")
    end)

    it("rejects empty other_responses", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.build_debate_prompt, { task = "T", other_responses = {} })
        expect(ok).to.equal(false)
    end)

    it("rejects missing task", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.build_debate_prompt, { other_responses = { "x" } })
        expect(ok).to.equal(false)
    end)
end)

-- ─── extract_boxed ───

describe("dmad.extract_boxed", function()
    lust.after(reset)

    it("extracts content from \\boxed{...}", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.extract_boxed({ text = "blah \\boxed{42} done" })).to.equal("42")
    end)

    it("prefers the LAST \\boxed{...} when multiple present", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.extract_boxed({
            text = "intermediate \\boxed{99} final \\boxed{42}",
        })).to.equal("42")
    end)

    it("trims whitespace inside the brace", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.extract_boxed({ text = "\\boxed{  7  }" })).to.equal("7")
    end)

    it("falls back to trimmed raw text when no \\boxed{} present", function()
        _G.alc = {}
        local m = require("dmad")
        expect(m.extract_boxed({ text = "   the answer is 12   " }))
            .to.equal("the answer is 12")
    end)

    it("rejects missing text", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.extract_boxed, {})
        expect(ok).to.equal(false)
    end)
end)

-- ─── aggregate_majority ───

describe("dmad.aggregate_majority", function()
    lust.after(reset)

    it("returns strict-majority winner", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.aggregate_majority({ answers = { "A", "B", "A" } })
        expect(r.answer).to.equal("A")
        expect(r.count).to.equal(2)
    end)

    it("tally is sorted by (count desc, first-occurrence asc)", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.aggregate_majority({ answers = { "X", "Y", "Y", "Z", "X", "X" } })
        expect(r.tally[1].answer).to.equal("X")
        expect(r.tally[1].count).to.equal(3)
        expect(r.tally[2].answer).to.equal("Y")
        expect(r.tally[2].count).to.equal(2)
        expect(r.tally[3].answer).to.equal("Z")
        expect(r.tally[3].count).to.equal(1)
    end)

    it("breaks ties by first-occurrence (eval_gsm.py:most_frequent semantics)", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.aggregate_majority({ answers = { "B", "A", "B", "A" } })
        -- Both B and A have count=2. B occurred first, so B wins.
        expect(r.answer).to.equal("B")
        expect(r.count).to.equal(2)
    end)

    it("handles single-answer input", function()
        _G.alc = {}
        local m = require("dmad")
        local r = m.aggregate_majority({ answers = { "only" } })
        expect(r.answer).to.equal("only")
        expect(r.count).to.equal(1)
        expect(#r.tally).to.equal(1)
    end)

    it("rejects empty answers", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.aggregate_majority, { answers = {} })
        expect(ok).to.equal(false)
    end)

    it("rejects non-string answer", function()
        _G.alc = {}
        local m = require("dmad")
        local ok = pcall(m.aggregate_majority, { answers = { "a", 42 } })
        expect(ok).to.equal(false)
    end)
end)

-- ─── M.run end-to-end ───

describe("dmad.run", function()
    lust.after(reset)

    it("default config (N=3 / R=2) makes N·(R+1)=9 LLM calls", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "What is 1+1?" })
        expect(ctx.result.total_llm_calls).to.equal(9)
        expect(#call_log).to.equal(9)
        expect(ctx.result.n_agents).to.equal(3)
        expect(ctx.result.n_rounds).to.equal(2)
    end)

    it("custom N=2 / R=1 makes 4 LLM calls", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "X", n_agents = 2, n_rounds = 1 })
        expect(ctx.result.total_llm_calls).to.equal(4)
        expect(ctx.result.n_agents).to.equal(2)
        expect(ctx.result.n_rounds).to.equal(1)
    end)

    it("init round prompts use INIT_TEMPLATE (no other-agent text)", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        -- First 2 calls are init prompts
        for i = 1, 2 do
            expect(call_log[i].prompt:find(
                "Can you solve the following math problem%?", 1)).to_not.equal(nil)
            expect(call_log[i].prompt:find("These are the solutions", 1,
                true)).to.equal(nil)
        end
    end)

    it("debate round prompts include other agents' previous-round answers", function()
        local fixtures = {
            -- init: agent 1, agent 2
            "\\boxed{A1_init}", "\\boxed{A2_init}",
            -- debate r=1: agent 1, agent 2
            "\\boxed{A1_r1}", "\\boxed{A2_r1}",
        }
        local alc_stub, call_log = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        -- Call 3 is agent 1's debate prompt: should contain A2_init but NOT A1_init.
        local p3 = call_log[3].prompt
        expect(p3:find("These are the solutions", 1, true)).to_not.equal(nil)
        expect(p3:find("A2_init", 1, true)).to_not.equal(nil)
        expect(p3:find("A1_init", 1, true)).to.equal(nil)
        -- Call 4 is agent 2's debate prompt: should contain A1_init but NOT A2_init.
        local p4 = call_log[4].prompt
        expect(p4:find("A1_init", 1, true)).to_not.equal(nil)
        expect(p4:find("A2_init", 1, true)).to.equal(nil)
    end)

    it("aggregates last_answers via extract_boxed then majority vote", function()
        local fixtures = {
            -- init (3 agents)
            "x", "y", "z",
            -- debate r=1
            "x", "y", "z",
            -- debate r=2 (final, all converge to same answer)
            "\\boxed{42}", "\\boxed{42}", "\\boxed{99}",
        }
        local alc_stub = make_alc_stub({ fixtures = fixtures })
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "T" })  -- default N=3, R=2
        expect(ctx.result.answer).to.equal("42")
        expect(ctx.result.last_answers[1]).to.equal("42")
        expect(ctx.result.last_answers[2]).to.equal("42")
        expect(ctx.result.last_answers[3]).to.equal("99")
        expect(ctx.result.tally[1].answer).to.equal("42")
        expect(ctx.result.tally[1].count).to.equal(2)
    end)

    it("responses array is [R+1] × [N], 1-based round index in Lua", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "T", n_agents = 2, n_rounds = 2 })
        expect(#ctx.result.responses).to.equal(3)  -- init + 2 rounds
        for r = 1, 3 do
            expect(#ctx.result.responses[r]).to.equal(2)
            for i = 1, 2 do
                expect(type(ctx.result.responses[r][i])).to.equal("string")
            end
        end
    end)

    it("debate_log is flat chronological list of (agent, round, text) tuples", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        -- 4 entries: 2 init (round=0) + 2 debate (round=1)
        expect(#ctx.result.debate_log).to.equal(4)
        expect(ctx.result.debate_log[1].agent).to.equal(1)
        expect(ctx.result.debate_log[1].round).to.equal(0)
        expect(ctx.result.debate_log[2].agent).to.equal(2)
        expect(ctx.result.debate_log[2].round).to.equal(0)
        expect(ctx.result.debate_log[3].agent).to.equal(1)
        expect(ctx.result.debate_log[3].round).to.equal(1)
        expect(ctx.result.debate_log[4].agent).to.equal(2)
        expect(ctx.result.debate_log[4].round).to.equal(1)
    end)

    it("propagates gen_tokens to max_tokens in LLM opts", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1, gen_tokens = 777 })
        for _, c in ipairs(call_log) do
            expect(c.opts.max_tokens).to.equal(777)
        end
    end)

    it("omits temperature in LLM opts when not specified (paper default)", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        for _, c in ipairs(call_log) do
            expect(c.opts.temperature).to.equal(nil)
        end
    end)

    it("passes temperature through when specified", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1, temperature = 0.5 })
        for _, c in ipairs(call_log) do
            expect(c.opts.temperature).to.equal(0.5)
        end
    end)

    it("uses default system_prompt by default", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        expect(call_log[1].opts.system).to.equal(m.DEFAULT_SYSTEM_PROMPT)
    end)

    it("accepts custom system_prompt", function()
        local alc_stub, call_log = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        m.run({ task = "T", n_agents = 2, n_rounds = 1, system_prompt = "CUSTOM" })
        for _, c in ipairs(call_log) do
            expect(c.opts.system).to.equal("CUSTOM")
        end
    end)

    it("rejects missing task", function()
        _G.alc = make_alc_stub()
        local m = require("dmad")
        local ok = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)

    it("rejects n_agents < 2", function()
        _G.alc = make_alc_stub()
        local m = require("dmad")
        local ok = pcall(m.run, { task = "T", n_agents = 1 })
        expect(ok).to.equal(false)
    end)

    it("rejects n_rounds < 1", function()
        _G.alc = make_alc_stub()
        local m = require("dmad")
        local ok = pcall(m.run, { task = "T", n_rounds = 0 })
        expect(ok).to.equal(false)
    end)

    it("rejects non-integer n_agents", function()
        _G.alc = make_alc_stub()
        local m = require("dmad")
        local ok = pcall(m.run, { task = "T", n_agents = 2.5 })
        expect(ok).to.equal(false)
    end)

    it("rejects when alc host is unavailable", function()
        _G.alc = nil
        package.loaded["dmad"] = nil
        local m = require("dmad")
        local ok, err = pcall(m.run, { task = "T" })
        expect(ok).to.equal(false)
        expect(err:match("alc host")).to_not.equal(nil)
    end)
end)

-- ─── Hegelian path is gone ───

describe("dmad.run (Hegelian path removed)", function()
    lust.after(reset)

    it("result shape is Du-only — no thesis/antithesis/synthesis fields", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({ task = "T", n_agents = 2, n_rounds = 1 })
        expect(ctx.result.thesis).to.equal(nil)
        expect(ctx.result.antithesis).to.equal(nil)
        expect(ctx.result.synthesis).to.equal(nil)
        expect(ctx.result.rebuttal).to.equal(nil)
    end)

    it("does not branch on dialectic_mode (extra field silently ignored)", function()
        local alc_stub = make_alc_stub()
        _G.alc = alc_stub
        local m = require("dmad")
        local ctx = m.run({
            task = "T", n_agents = 2, n_rounds = 1,
            dialectic_mode = "hegelian",
        })
        -- Same shape regardless: 2*(1+1)=4 calls, Du fields present.
        expect(ctx.result.total_llm_calls).to.equal(4)
        expect(type(ctx.result.responses)).to.equal("table")
        expect(type(ctx.result.last_answers)).to.equal("table")
    end)
end)
