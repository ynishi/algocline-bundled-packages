--- Tests for aot package (Atom of Thoughts, Teng et al. 2025
--- arXiv:2502.12018, NeurIPS 2025). DAG decompose → contract → solve
--- with Markov property (history discard between iterations).
---
--- Covers:
---   - Algorithm 1 line correspondence (decompose / split / contract /
---     solve sequence, depth budget fixed on i=0 only)
---   - parse_ok field surfaces silent decompose failures
---   - nested dispatch via M.<entry> (monkey-patch marker tests)
---   - per-knob overrides (consistency_yes_token, consistency_tokens,
---     selector_tokens, prompt templates)
---   - AoT* §5 variant (N runs + selector)
---
--- Run via:
---   just alc-pkg-test-file aot/spec/aot_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

--- json_decode stub that parses Lua-literal strings (sibling pattern to
--- dci). Test fixtures feed Lua-table literals, which is sufficient for
--- exercising the pkg's parse_subquestions path.
local function lua_literal_decode(s)
    if type(s) ~= "string" then return nil end
    local chunk = load("return " .. s, "aot_stub_json", "t", {})
    if not chunk then return nil end
    local ok, v = pcall(chunk)
    if not ok then return nil end
    return v
end

local function reset()
    _G.alc = nil
    package.loaded["aot"] = nil
end

--- Build a mock alc with prompt-substring routing.
---   opts.decompose_responses — sequence of strings returned by
---     successive decompose calls (Lua-literal subquestions object).
---   opts.contract_response   — string returned by contract calls
---     (default "contracted_q").
---   opts.solve_response      — string returned by solve calls
---     (default "final_ans").
---   opts.consistency_response — string returned by consistency_check
---     (default "yes").
---   opts.selector_response   — string returned by AoT* selector
---     (default "1").
local function mock_alc(opts)
    opts = opts or {}
    local decompose_responses = opts.decompose_responses or {}
    local decompose_idx = 0
    local call_log = {}
    local c = {
        decompose = 0,
        contract = 0,
        solve = 0,
        consistency = 0,
        selector = 0,
    }
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            if prompt:find("Return ONLY valid JSON", 1, true) then
                c.decompose = c.decompose + 1
                decompose_idx = decompose_idx + 1
                local resp = decompose_responses[decompose_idx]
                if resp == nil then
                    -- Default: minimal 2-node DAG with one indep + one dep.
                    return "{subquestions={{id=1,text=[[a]],depend={}},{id=2,text=[[b]],depend={1}}}}"
                end
                return resp
            elseif prompt:find("Independent subquestions", 1, true) then
                c.contract = c.contract + 1
                return opts.contract_response or "contracted_q"
            elseif prompt:find('Reply with just "yes" or "no"', 1, true) then
                c.consistency = c.consistency + 1
                return opts.consistency_response or "yes"
            elseif prompt:find("Select the best candidate", 1, true) then
                c.selector = c.selector + 1
                return opts.selector_response or "1"
            else
                c.solve = c.solve + 1
                return opts.solve_response or "final_ans"
            end
        end,
        json_decode = lua_literal_decode,
        log = setmetatable(
            { warn = function(_) end, info = function(_) end },
            { __call = function(_, _, _) end }
        ),
    }
    return call_log, c
end

-- ============================================================
-- meta + spec exposure
-- ============================================================

describe("aot.meta", function()
    reset()
    mock_alc()
    local m = require("aot")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("aot")
        expect(m.meta.version).to.equal("0.2.0")
        expect(m.meta.category).to.equal("reasoning")
    end)
end)

describe("aot.spec", function()
    reset()
    mock_alc()
    local m = require("aot")
    it("exposes decompose / split_indep_dep / get_max_path_length / contract / solve / run", function()
        for _, entry in ipairs({
            "decompose", "split_indep_dep", "get_max_path_length",
            "contract", "solve", "run",
        }) do
            expect(m.spec.entries[entry]).to_not.equal(nil)
            expect(m.spec.entries[entry].input).to_not.equal(nil)
            expect(m.spec.entries[entry].result).to_not.equal(nil)
        end
    end)
end)

-- ============================================================
-- split_indep_dep (paper §3.3 lines 8-9)
-- ============================================================

describe("aot.split_indep_dep", function()
    it("empty list → empty indep + dep", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.split_indep_dep({ subquestions = {} })
        expect(#ctx.result.indep).to.equal(0)
        expect(#ctx.result.dep).to.equal(0)
    end)

    it("all independent (depend = []) → all in indep", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.split_indep_dep({
            subquestions = {
                { id = 1, text = "a", depend = {} },
                { id = 2, text = "b", depend = {} },
            },
        })
        expect(#ctx.result.indep).to.equal(2)
        expect(#ctx.result.dep).to.equal(0)
    end)

    it("mixed → split by depend non-empty", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.split_indep_dep({
            subquestions = {
                { id = 1, text = "a", depend = {} },
                { id = 2, text = "b", depend = { 1 } },
                { id = 3, text = "c", depend = {} },
            },
        })
        expect(#ctx.result.indep).to.equal(2)
        expect(#ctx.result.dep).to.equal(1)
        expect(ctx.result.dep[1].id).to.equal(2)
    end)
end)

-- ============================================================
-- get_max_path_length (paper §3.3 line 6; node-count metric)
-- ============================================================

describe("aot.get_max_path_length", function()
    it("empty list → 0", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.get_max_path_length({ subquestions = {} })
        expect(ctx.result.max_path_length).to.equal(0)
    end)

    it("single independent node → 1", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.get_max_path_length({
            subquestions = { { id = 1, text = "a", depend = {} } },
        })
        expect(ctx.result.max_path_length).to.equal(1)
    end)

    it("linear chain 1 → 2 → 3 → 4 → 4", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.get_max_path_length({
            subquestions = {
                { id = 1, text = "a", depend = {} },
                { id = 2, text = "b", depend = { 1 } },
                { id = 3, text = "c", depend = { 2 } },
                { id = 4, text = "d", depend = { 3 } },
            },
        })
        expect(ctx.result.max_path_length).to.equal(4)
    end)

    it("parallel independent nodes → 1", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.get_max_path_length({
            subquestions = {
                { id = 1, text = "a", depend = {} },
                { id = 2, text = "b", depend = {} },
                { id = 3, text = "c", depend = {} },
            },
        })
        expect(ctx.result.max_path_length).to.equal(1)
    end)

    it("two parallel chains of unequal length → longer one wins", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ctx = m.get_max_path_length({
            subquestions = {
                { id = 1, text = "a", depend = {} },
                { id = 2, text = "b", depend = { 1 } },
                { id = 3, text = "c", depend = {} },
                { id = 4, text = "d", depend = { 3 } },
                { id = 5, text = "e", depend = { 4 } },
            },
        })
        expect(ctx.result.max_path_length).to.equal(3)
    end)
end)

-- ============================================================
-- decompose (parse_ok contract)
-- ============================================================

describe("aot.decompose", function()
    it("errors when ctx.question is missing", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ok = pcall(m.decompose, {})
        expect(ok).to.equal(false)
    end)

    it("parses well-formed JSON-like decomposition, parse_ok=true", function()
        reset()
        mock_alc({
            decompose_responses = {
                "{subquestions={{id=1,text=[[A]],depend={}},{id=2,text=[[B]],depend={1}}}}",
            },
        })
        local m = require("aot")
        local ctx = m.decompose({ question = "Q" })
        expect(#ctx.result.subquestions).to.equal(2)
        expect(ctx.result.subquestions[1].id).to.equal(1)
        expect(ctx.result.subquestions[2].depend[1]).to.equal(1)
        expect(ctx.result.parse_ok).to.equal(true)
    end)

    it("unparseable response → empty subquestions, raw preserved, parse_ok=false", function()
        reset()
        mock_alc({ decompose_responses = { "rambling prose with no JSON" } })
        local m = require("aot")
        local ctx = m.decompose({ question = "Q" })
        expect(#ctx.result.subquestions).to.equal(0)
        expect(ctx.result.raw).to.equal("rambling prose with no JSON")
        expect(ctx.result.parse_ok).to.equal(false)
    end)

    it("payload without subquestions key → parse_ok=false", function()
        reset()
        mock_alc({ decompose_responses = { "{other_key={1,2,3}}" } })
        local m = require("aot")
        local ctx = m.decompose({ question = "Q" })
        expect(#ctx.result.subquestions).to.equal(0)
        expect(ctx.result.parse_ok).to.equal(false)
    end)
end)

-- ============================================================
-- contract / solve
-- ============================================================

describe("aot.contract", function()
    it("errors when required inputs missing", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ok = pcall(m.contract, { indep = {}, dep = {} })
        expect(ok).to.equal(false)
    end)

    it("returns contracted_question from LLM (single call)", function()
        reset()
        local log, c = mock_alc({ contract_response = "new_q" })
        local m = require("aot")
        local ctx = m.contract({
            question = "Q",
            indep = { { id = 1, text = "a", depend = {} } },
            dep = { { id = 2, text = "b", depend = { 1 } } },
        })
        expect(ctx.result.contracted_question).to.equal("new_q")
        expect(c.contract).to.equal(1)
    end)
end)

describe("aot.solve", function()
    it("errors when ctx.question missing", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ok = pcall(m.solve, {})
        expect(ok).to.equal(false)
    end)

    it("returns answer from LLM", function()
        reset()
        mock_alc({ solve_response = "ans_text" })
        local m = require("aot")
        local ctx = m.solve({ question = "Q_final" })
        expect(ctx.result.answer).to.equal("ans_text")
    end)
end)

-- ============================================================
-- run — Algorithm 1 end-to-end
-- ============================================================

describe("aot.run — Algorithm 1 basics", function()
    it("errors when ctx.task is missing", function()
        reset()
        mock_alc()
        local m = require("aot")
        local ok = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)

    it("default run: D=2 → 2 decompose + 2 contract + 1 solve = 5 calls", function()
        reset()
        local response = "{subquestions={{id=1,text=[[a]],depend={}},{id=2,text=[[b]],depend={1}}}}"
        local log, c = mock_alc({
            decompose_responses = { response, response },
        })
        local m = require("aot")
        local ctx = m.run({ task = "Q" })
        expect(c.decompose).to.equal(2)
        expect(c.contract).to.equal(2)
        expect(c.solve).to.equal(1)
        expect(#log).to.equal(5)
        expect(ctx.result.depth_used).to.equal(2)
        expect(ctx.result.initial_depth_budget).to.equal(2)
        expect(ctx.result.final_answer).to.equal("final_ans")
    end)

    it("max_depth cap shrinks initial_depth_budget enforcement", function()
        reset()
        local response = "{subquestions={"
            .. "{id=1,text=[[a]],depend={}},"
            .. "{id=2,text=[[b]],depend={1}},"
            .. "{id=3,text=[[c]],depend={2}},"
            .. "{id=4,text=[[d]],depend={3}}"
            .. "}}"
        local log, c = mock_alc({
            decompose_responses = { response, response },
        })
        local m = require("aot")
        -- Initial D = 4 (linear chain 1→2→3→4), capped to 2.
        local ctx = m.run({ task = "Q", max_depth = 2 })
        expect(c.decompose).to.equal(2)
        expect(c.contract).to.equal(2)
        expect(ctx.result.depth_used).to.equal(2)
        expect(ctx.result.initial_depth_budget).to.equal(4)
    end)

    it("unparseable first decompose → parse_ok=false → solve current question directly (0 iterations)", function()
        reset()
        local log, c = mock_alc({ decompose_responses = { "garbage" } })
        local m = require("aot")
        local ctx = m.run({ task = "Q" })
        expect(c.decompose).to.equal(1)
        expect(c.contract).to.equal(0)
        expect(c.solve).to.equal(1)
        expect(ctx.result.depth_used).to.equal(0)
        expect(ctx.result.final_question).to.equal("Q")
    end)

    it("consistency_check=true with 'no' verdict aborts iteration loop", function()
        reset()
        local response = "{subquestions={{id=1,text=[[a]],depend={}},{id=2,text=[[b]],depend={1}}}}"
        local _, c = mock_alc({
            decompose_responses = { response, response },
            consistency_response = "no",
        })
        local m = require("aot")
        local ctx = m.run({ task = "Q", consistency_check = true })
        expect(c.consistency).to.equal(1)
        expect(c.contract).to.equal(1)
        expect(ctx.result.depth_used).to.equal(0)
    end)

    it("consistency_yes_token override propagates ('OK' instead of 'yes')", function()
        reset()
        local response = "{subquestions={{id=1,text=[[a]],depend={}},{id=2,text=[[b]],depend={1}}}}"
        local _, c = mock_alc({
            decompose_responses = { response, response },
            consistency_response = "OK to proceed", -- contains 'ok' not 'yes'
        })
        local m = require("aot")
        local ctx = m.run({
            task = "Q",
            consistency_check = true,
            consistency_yes_token = "ok",
        })
        -- Should keep iterating because 'ok' matches.
        expect(c.consistency).to.equal(2) -- one per iteration
        expect(c.contract).to.equal(2)
        expect(ctx.result.depth_used).to.equal(2)
    end)

    it("AoT* final_aggregation_runs=3 triggers 3 runs + 1 selector", function()
        reset()
        local response = "{subquestions={{id=1,text=[[a]],depend={}},{id=2,text=[[b]],depend={1}}}}"
        local _, c = mock_alc({
            decompose_responses = {
                response, response, -- run 1: 2 iterations
                response, response, -- run 2
                response, response, -- run 3
            },
            selector_response = "2",
        })
        local m = require("aot")
        local ctx = m.run({ task = "Q", final_aggregation_runs = 3 })
        expect(c.solve).to.equal(3) -- one per run
        expect(c.selector).to.equal(1)
        expect(ctx.result.final_answer).to.equal("final_ans")
    end)
end)

-- ============================================================
-- run — nested dispatch via M.<entry>
-- ============================================================

describe("aot.run — nested dispatch via M.<entry>", function()
    it("M.run calls through M.decompose (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("aot")
        local marker = 0
        local orig = m.decompose
        m.decompose = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q" })
        -- default 2-node DAG → D=2 → 2 decompose calls
        expect(marker).to.equal(2)
    end)

    it("M.run calls through M.contract (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("aot")
        local marker = 0
        local orig = m.contract
        m.contract = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q" })
        -- D=2 → 2 contract calls
        expect(marker).to.equal(2)
    end)

    it("M.run calls through M.solve (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("aot")
        local marker = 0
        local orig = m.solve
        m.solve = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q" })
        expect(marker).to.equal(1)
    end)

    it("M.run calls through M.split_indep_dep (table lookup, not closure)", function()
        reset()
        mock_alc()
        local m = require("aot")
        local marker = 0
        local orig = m.split_indep_dep
        m.split_indep_dep = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q" })
        -- One split per iteration → D=2 → 2 splits
        expect(marker).to.equal(2)
    end)

    it("M.run calls through M.get_max_path_length once (first iteration only)", function()
        reset()
        mock_alc()
        local m = require("aot")
        local marker = 0
        local orig = m.get_max_path_length
        m.get_max_path_length = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({ task = "Q" })
        -- Algorithm 1 line 6 fixes D on the first iteration only.
        expect(marker).to.equal(1)
    end)
end)

reset()
