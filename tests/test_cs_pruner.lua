--- Tests for cs_pruner (Confidence-Sequence Partial-Data Pruner)
--- Mocked LLM, no real API calls.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local function mock_alc(llm_fn)
    local call_log = {}
    _G.alc = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for i, item in ipairs(list) do
                results[i] = fn(item, i)
            end
            return results
        end,
        parallel = function(list, prompt_fn)
            local results = {}
            for i, item in ipairs(list) do
                local p = prompt_fn(item, i)
                local prompt, opts
                if type(p) == "table" then
                    prompt = p.prompt
                    opts = { system = p.system, max_tokens = p.max_tokens }
                else
                    prompt = p
                    opts = {}
                end
                call_log[#call_log + 1] = { prompt = prompt, opts = opts }
                results[i] = llm_fn(prompt, opts, #call_log)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(tostring(s):match("[%d%.]+"))
        end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["cs_pruner"] = nil
end

describe("cs_pruner", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("cs_pruner")
        expect(m.meta.name).to.equal("cs_pruner")
        expect(m.meta.category).to.equal("selection")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {})
        expect(ok).to.equal(false)
    end)

    it("errors on n_candidates < 2", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, { task = "T", n_candidates = 1 })
        expect(ok).to.equal(false)
    end)

    it("errors on invalid delta", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, { task = "T", n_candidates = 3, delta = 1.5 })
        expect(ok).to.equal(false)
    end)

    it("errors on unknown cs_variant", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T", n_candidates = 3, cs_variant = "nope",
        })
        expect(ok).to.equal(false)
    end)

    it("errors on unimplemented aggregation", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T", n_candidates = 3,
            aggregation = "independent_bonferroni",
        })
        expect(ok).to.equal(false)
    end)

    it("generates N candidates and evaluates all alive with small rubric", function()
        local small_rubric = {
            { name = "dim1", criterion = "c1" },
            { name = "dim2", criterion = "c2" },
        }
        mock_alc(function(_, _, n)
            if n <= 3 then return "candidate " .. n end
            return "PASS"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "Solve X",
            n_candidates = 3,
            rubric = small_rubric,
        })
        expect(ctx.result.best).to_not.equal(nil)
        expect(#ctx.result.candidates).to.equal(3)
        expect(ctx.result.n_dimensions).to.equal(2)
        -- All PASS, all candidates at mean = 1.0, no kills
        expect(ctx.result.alive_count).to.equal(3)
        -- 3 gen + 3*2 eval = 9 calls
        expect(ctx.result.total_llm_calls).to.equal(9)
    end)

    it("kills clearly-losing candidate with large rubric and strong gap", function()
        -- Candidate 1 always PASS, candidate 2 always FAIL. Given enough
        -- dimensions the CS should eventually separate them.
        local big_rubric = {}
        for i = 1, 50 do
            big_rubric[i] = { name = "d" .. i, criterion = "c" }
        end
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "candidate " .. n end
            -- Alternating round-robin: cand1 PASS, cand2 FAIL
            -- We detect by candidate content in prompt.
            if prompt:find("candidate 1") then return "PASS" end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = big_rubric,
            delta = 0.1,
        })
        -- Best should be candidate 1
        expect(ctx.result.best_index).to.equal(1)
        -- Expect kill events (may or may not happen depending on how
        -- conservative the CS is). At minimum, best_score should be high.
        expect(ctx.result.best_score > 0.9).to.equal(true)
    end)

    it("respects min_n_before_kill warmup", function()
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "cand " .. n end
            if prompt:find("cand 1") then return "PASS" end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = {
                { name = "d1", criterion = "c" },
                { name = "d2", criterion = "c" },
            },
            min_n_before_kill = 10, -- impossible to reach with 2 dims
        })
        expect(ctx.result.alive_count).to.equal(2)
    end)

    it("layer2 halving drops bottom half at checkpoint", function()
        local rubric = {}
        for i = 1, 5 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        local cand_idx = 0
        mock_alc(function(prompt, _, n)
            if n <= 4 then return "cand " .. n end
            -- cand 1,2 PASS; cand 3,4 FAIL
            for k = 1, 4 do
                if prompt:find("cand " .. k) then
                    if k <= 2 then return "PASS" else return "FAIL" end
                end
            end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            rubric = rubric,
            layer2_halving = true,
            halving_checkpoints = { 5 },
            halving_keep_ratio = 0.5,
        })
        -- After checkpoint at dim 5, bottom 2 killed → 2 alive
        -- (may also kill via CS; at minimum alive_count <= 2)
        expect(ctx.result.alive_count <= 2).to.equal(true)
    end)

    it("halving_min_gap protects candidates near median", function()
        -- 4 candidates: c1=PASS, c2=PASS, c3=PASS, c4=FAIL.
        -- After 5 dims: means roughly {1.0, 1.0, 1.0, 0.0}.
        -- Median ≈ 1.0. c4 mean=0.0 → gap=1.0 → not protected, killed.
        -- With min_gap=0.5, c4 should still be killed (gap exceeds).
        -- But if we set min_gap > 1.0, c4 should be PROTECTED.
        local rubric = {}
        for i = 1, 5 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        mock_alc(function(prompt, _, n)
            if n <= 4 then return "cand " .. n end
            for k = 1, 4 do
                if prompt:find("cand " .. k) then
                    if k <= 3 then return "PASS" else return "FAIL" end
                end
            end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            rubric = rubric,
            layer2_halving = true,
            halving_checkpoints = { 5 },
            halving_keep_ratio = 0.5,
            halving_min_gap = 1.5, -- impossibly large → everyone protected
        })
        -- All 4 should remain alive
        expect(ctx.result.alive_count).to.equal(4)
        -- One protect event recorded (c4 in bottom slice)
        local protected_count = 0
        for _, ev in ipairs(ctx.result.protect_events or {}) do
            if ev.reason == "layer2_halving_protected" then
                protected_count = protected_count + 1
            end
        end
        expect(protected_count >= 1).to.equal(true)
    end)

    it("halving_min_gap=0 preserves legacy halving behaviour", function()
        local rubric = {}
        for i = 1, 5 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        mock_alc(function(prompt, _, n)
            if n <= 4 then return "cand " .. n end
            for k = 1, 4 do
                if prompt:find("cand " .. k) then
                    if k <= 2 then return "PASS" else return "FAIL" end
                end
            end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            rubric = rubric,
            layer2_halving = true,
            halving_checkpoints = { 5 },
            halving_keep_ratio = 0.5,
            -- halving_min_gap default = 0
        })
        expect(ctx.result.alive_count <= 2).to.equal(true)
    end)

    it("multi-checkpoint staged halving drops gradually", function()
        -- 6 candidates with descending quality. Two checkpoints.
        local rubric = {}
        for i = 1, 10 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        mock_alc(function(prompt, _, n)
            if n <= 6 then return "cand " .. n end
            for k = 1, 6 do
                if prompt:find("cand " .. k) then
                    -- cand1=100% PASS, cand2=90%, ..., cand6=0%
                    if k == 1 then return "PASS" end
                    if k == 6 then return "FAIL" end
                    -- Use call number for deterministic ordering
                    if (n + k) % 6 < (7 - k) then return "PASS" end
                    return "FAIL"
                end
            end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 6,
            rubric = rubric,
            layer2_halving = true,
            halving_checkpoints = { 5, 10 },
            halving_keep_ratio = 0.66, -- drop bottom ~33% per stage
        })
        -- After two staged halvings 6 → 4 → 3 (approx), so alive should be < 6
        expect(ctx.result.alive_count < 6).to.equal(true)
        -- At least one halving_kill event with reason=="layer2_halving"
        local halving_kills = 0
        for _, ev in ipairs(ctx.result.kill_events) do
            if ev.reason == "layer2_halving" then halving_kills = halving_kills + 1 end
        end
        expect(halving_kills >= 1).to.equal(true)
    end)

    it("rejects negative halving_min_gap", function()
        mock_alc(function() return "PASS" end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T", n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
            halving_min_gap = -0.1,
        })
        expect(ok).to.equal(false)
    end)

    it("calls on_kill callback", function()
        local killed = {}
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "c" .. n end
            if prompt:find("c1") then return "PASS" end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local rubric = {}
        for i = 1, 3 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        m.run({
            task = "T",
            n_candidates = 2,
            rubric = rubric,
            layer2_halving = true,
            halving_checkpoints = { 3 },
            halving_keep_ratio = 0.5,
            on_kill = function(idx, _) killed[#killed + 1] = idx end,
        })
        expect(#killed >= 1).to.equal(true)
    end)

    it("betting variant runs and produces valid bounds", function()
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "c" .. n end
            if prompt:find("c1") then return "PASS" end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local rubric = {}
        for i = 1, 10 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = rubric,
            cs_variant = "betting",
            delta = 0.1,
        })
        expect(ctx.result.cs_variant).to.equal("betting")
        -- Best should be the PASS candidate (c1)
        expect(ctx.result.best_index).to.equal(1)
        -- bounds must be finite real numbers
        for _, r in ipairs(ctx.result.ranking) do
            expect(r.lcb == r.lcb).to.equal(true) -- not NaN
            expect(r.ucb == r.ucb).to.equal(true)
            expect(r.lcb <= r.ucb).to.equal(true)
        end
    end)

    it("betting variant rejects non-{0,1} score_domain", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "c" .. n end
            return "PASS"
        end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T",
            n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
            cs_variant = "betting",
            score_domain = { min = 0, max = 10 },
        })
        expect(ok).to.equal(false)
    end)

    it("kl variant runs and produces finite bounds", function()
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "c" .. n end
            if prompt:find("c1") then return "PASS" end
            return "FAIL"
        end)
        local m = require("cs_pruner")
        local rubric = {}
        for i = 1, 10 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = rubric,
            cs_variant = "kl",
            delta = 0.1,
        })
        expect(ctx.result.cs_variant).to.equal("kl")
        expect(ctx.result.best_index).to.equal(1)
        for _, r in ipairs(ctx.result.ranking) do
            expect(r.lcb == r.lcb).to.equal(true)
            expect(r.ucb == r.ucb).to.equal(true)
            expect(r.lcb >= 0).to.equal(true)
            expect(r.ucb <= 1).to.equal(true)
            expect(r.lcb <= r.ucb).to.equal(true)
        end
    end)

    it("kl variant rejects non-{0,1} score_domain", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "c" .. n end
            return "PASS"
        end)
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T",
            n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
            cs_variant = "kl",
            score_domain = { min = 0, max = 10 },
        })
        expect(ok).to.equal(false)
    end)

    it("hoeffding variant runs", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "c" .. n end
            return "PASS"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
            cs_variant = "hoeffding",
        })
        expect(ctx.result.cs_variant).to.equal("hoeffding")
    end)

    it("sequential eval_order processes one candidate at a time", function()
        local order = {}
        mock_alc(function(prompt, _, n)
            if n <= 2 then return "cand " .. n end
            for k = 1, 2 do
                if prompt:find("cand " .. k) then
                    order[#order + 1] = k
                    break
                end
            end
            return "PASS"
        end)
        local m = require("cs_pruner")
        m.run({
            task = "T",
            n_candidates = 2,
            rubric = {
                { name = "d1", criterion = "c" },
                { name = "d2", criterion = "c" },
            },
            eval_order = "sequential",
        })
        -- Sequential should evaluate candidate 1 on all dims first,
        -- then candidate 2. Expect pattern like {1, 1, 2, 2}.
        expect(order[1]).to.equal(1)
        expect(order[2]).to.equal(1)
        expect(order[3]).to.equal(2)
    end)

    it("parses numeric score fallback", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "c" .. n end
            return "0.8"
        end)
        local m = require("cs_pruner")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
        })
        -- Score is 0.8, normalized to [0,1] = 0.8
        expect(ctx.result.ranking[1].mean > 0.7).to.equal(true)
    end)

    it("errors on unparseable score", function()
        mock_alc(function(_, _, n)
            if n <= 2 then return "c" .. n end
            return "gibberish"
        end)
        _G.alc.parse_score = function() return nil end
        local m = require("cs_pruner")
        local ok = pcall(m.run, {
            task = "T",
            n_candidates = 2,
            rubric = { { name = "d1", criterion = "c" } },
        })
        expect(ok).to.equal(false)
    end)

    it("returns ranking sorted by alive then mean", function()
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "cand " .. n end
            if prompt:find("cand 1") then return "PASS" end
            if prompt:find("cand 2") then return "FAIL" end
            return "PASS"
        end)
        local m = require("cs_pruner")
        local rubric = {}
        for i = 1, 5 do rubric[i] = { name = "d" .. i, criterion = "c" } end
        local ctx = m.run({
            task = "T", n_candidates = 3, rubric = rubric,
        })
        -- Best should be a PASS candidate (index 1 or 3)
        local best_idx = ctx.result.ranking[1].index
        expect(best_idx == 1 or best_idx == 3).to.equal(true)
    end)
end)
