--- Tests for Tier 1-2 packages: usc, step_verify, compute_alloc,
--- gumbel_search, mbr_select, reflexion
--- Structural tests + logic tests (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local PKG_NAMES = {
    "usc", "step_verify", "compute_alloc",
    "gumbel_search", "mbr_select", "reflexion",
}

--- Build a mock alc global. call_log records all llm calls.
local function mock_alc(llm_fn)
    local call_log = {}
    local a = {
        llm = function(prompt, opts)
            call_log[#call_log + 1] = { prompt = prompt, opts = opts }
            return llm_fn(prompt, opts, #call_log)
        end,
        map = function(list, fn)
            local results = {}
            for _, item in ipairs(list) do
                results[#results + 1] = fn(item)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s)
            return tonumber(s:match("%d+")) or 5
        end,
        json_decode = function(s)
            -- Minimal JSON parser for test: extracts score, passed, feedback
            local score = s:match('"score"%s*:%s*(%d+)')
            local passed = s:match('"passed"%s*:%s*(true)')
            local fb = s:match('"feedback"%s*:%s*"([^"]*)"')
            if score then
                return {
                    score = tonumber(score),
                    passed = passed ~= nil,
                    feedback = fb or "",
                }
            end
            return nil
        end,
        stats = { record = function() end },
    }
    _G.alc = a
    return call_log
end

--- Reset alc and unload all packages from cache.
local function reset()
    _G.alc = nil
    for _, name in ipairs(PKG_NAMES) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- usc — Universal Self-Consistency
-- ================================================================
describe("usc", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("usc")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("usc")
        expect(m.meta.category).to.equal("aggregation")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("uses N+1 LLM calls (N samples + 1 selection)", function()
        local log = mock_alc(function(_, _, n)
            if n <= 5 then return "candidate " .. n end
            return "Response 3 is most consistent. The answer is candidate 3."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "What is 2+2?" })
        -- default n=5: 5 sampling + 1 selection = 6
        expect(#log).to.equal(6)
        expect(ctx.result.n_sampled).to.equal(5)
        expect(#ctx.result.candidates).to.equal(5)
    end)

    it("custom n=3 uses 4 LLM calls", function()
        local log = mock_alc(function(_, _, n)
            if n <= 3 then return "answer " .. n end
            return "Response 2 is most consistent."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test", n = 3 })
        expect(#log).to.equal(4)
        expect(ctx.result.n_sampled).to.equal(3)
    end)

    it("extracts selected_index from 'Response N' pattern", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "Response 4 is the most consistent answer."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(4)
    end)

    it("extracts selected_index from '#N' pattern", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "The best answer is #2 because it is most consistent."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(2)
    end)

    it("sets selected_index to nil when no index is extractable", function()
        mock_alc(function(_, _, n)
            if n <= 5 then return "candidate" end
            return "The consensus is that the answer is 42."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test" })
        expect(ctx.result.selected_index).to.equal(nil)
    end)

    it("rejects out-of-range index", function()
        mock_alc(function(_, _, n)
            if n <= 3 then return "candidate" end
            return "Response 99 is the best."
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        local ctx = m.run({ task = "Test", n = 3 })
        expect(ctx.result.selected_index).to.equal(nil)
    end)

    it("selection prompt includes all candidates", function()
        local selection_prompt = nil
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "answer_" .. n end
            selection_prompt = prompt
            return "Response 1"
        end)
        package.loaded["usc"] = nil
        local m = require("usc")
        m.run({ task = "Q", n = 3 })
        expect(selection_prompt:match("answer_1")).to_not.equal(nil)
        expect(selection_prompt:match("answer_2")).to_not.equal(nil)
        expect(selection_prompt:match("answer_3")).to_not.equal(nil)
        expect(selection_prompt:match("Response 1")).to_not.equal(nil)
        expect(selection_prompt:match("Response 2")).to_not.equal(nil)
        expect(selection_prompt:match("Response 3")).to_not.equal(nil)
    end)
end)

-- ================================================================
-- step_verify — Step-Level Verification
-- ================================================================
describe("step_verify", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("step_verify")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("step_verify")
        expect(m.meta.category).to.equal("validation")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("all steps correct = no re-derive, 1 round", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then
                return "Step 1: Identify 2+2\nStep 2: Calculate 2+2=4\nStep 3: Answer is 4"
            end
            -- Verification calls
            if prompt:match("verify") or prompt:match("Verify") or prompt:match("VERDICT") then
                return "This step is logically sound. VERDICT: CORRECT"
            end
            -- Synthesis
            return "The answer is 4."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "What is 2+2?" })
        expect(ctx.result.total_rounds).to.equal(1)
        expect(ctx.result.total_verified > 0).to.equal(true)
        expect(ctx.result.answer).to.equal("The answer is 4.")
    end)

    it("error at step 2 triggers re-derive", function()
        local gen_calls = 0
        local log = mock_alc(function(prompt, _, n)
            -- Generation calls: "Solve step by step" or "Continue from"
            if prompt:match("Solve step by step") or prompt:match("Continue from") or prompt:match("Verified correct steps") then
                gen_calls = gen_calls + 1
                if gen_calls == 1 then
                    return "Step 1: Setup equations\nStep 2: Wrong calculation\nStep 3: Bad conclusion"
                else
                    return "Step 2: Correct calculation\nStep 3: Right conclusion"
                end
            end
            -- Verification calls contain "to verify:"
            if prompt:match("to verify:") then
                -- Fail on "Wrong calculation"
                if prompt:match("Wrong calculation") then
                    return "Error found. VERDICT: INCORRECT"
                end
                return "Looks correct. VERDICT: CORRECT"
            end
            -- Synthesis (contains "final answer")
            return "Final answer."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "Solve", max_repair_rounds = 1 })
        -- Should have 2 generation calls (initial + re-derive)
        expect(gen_calls).to.equal(2)
        expect(ctx.result.total_rounds > 1).to.equal(true)
    end)

    it("respects max_repair_rounds=0 (no re-derive)", function()
        local log = mock_alc(function(prompt)
            if prompt:match("Solve step by step") then
                return "Step 1: Only step"
            end
            if prompt:match("VERDICT") then
                return "VERDICT: INCORRECT"
            end
            return "Synthesized."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        local ctx = m.run({ task = "X", max_repair_rounds = 0 })
        -- Only 1 round (round 0), no re-derive
        expect(ctx.result.total_rounds).to.equal(1)
    end)

    it("synthesis is always the last LLM call", function()
        local last_prompt = nil
        mock_alc(function(prompt)
            last_prompt = prompt
            if prompt:match("Solve step by step") then
                return "Step 1: One step"
            end
            if prompt:match("VERDICT") then
                return "VERDICT: CORRECT"
            end
            return "Final synthesis."
        end)
        package.loaded["step_verify"] = nil
        local m = require("step_verify")
        m.run({ task = "Test" })
        expect(last_prompt:match("final answer")).to_not.equal(nil)
    end)
end)

-- ================================================================
-- compute_alloc — Compute-Optimal Allocation
-- ================================================================
describe("compute_alloc", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("compute_alloc")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("compute_alloc")
        expect(m.meta.category).to.equal("orchestration")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("EASY classification → single paradigm, 2 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "EASY — straightforward factual question" end
            return "The answer is 42."
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "What is 6*7?" })
        expect(ctx.result.difficulty).to.equal("easy")
        expect(ctx.result.paradigm).to.equal("single")
        expect(#log).to.equal(2) -- classify + direct
        expect(ctx.result.total_llm_calls).to.equal(2)
    end)

    it("MEDIUM classification → parallel paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "MEDIUM — requires multi-step reasoning" end
            return "response " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Explain the CAP theorem" })
        expect(ctx.result.difficulty).to.equal("medium")
        expect(ctx.result.paradigm).to.equal("parallel")
        -- 1 classify + 3 samples + 1 selection = 5
        expect(#log).to.equal(5)
    end)

    it("HARD classification → sequential paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "HARD — complex mathematical proof" end
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "step-by-step solution " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Prove P=NP" })
        expect(ctx.result.difficulty).to.equal("hard")
        expect(ctx.result.paradigm).to.equal("sequential")
    end)

    it("VERY_HARD classification → hybrid paradigm", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "VERY_HARD — open research problem" end
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "response " .. n
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Solve the Riemann hypothesis" })
        expect(ctx.result.difficulty).to.equal("very_hard")
        expect(ctx.result.paradigm).to.equal("hybrid")
    end)

    it("budget='low' overrides to easy (no classification call)", function()
        local log = mock_alc(function() return "direct answer" end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Simple Q", budget = "low" })
        expect(ctx.result.difficulty).to.equal("easy")
        expect(#log).to.equal(1) -- no classification, just direct
        expect(ctx.result.total_llm_calls).to.equal(1)
    end)

    it("budget='high' overrides to hard (no classification call)", function()
        local log = mock_alc(function(prompt)
            if prompt:match("VERIFIED_CORRECT") then
                return "VERIFIED_CORRECT"
            end
            return "answer"
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Q", budget = "high" })
        expect(ctx.result.difficulty).to.equal("hard")
        expect(ctx.result.total_llm_calls > 1).to.equal(true)
    end)

    it("sequential stops early when VERIFIED_CORRECT", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "HARD" end
            if n == 2 then return "step by step solution" end
            -- First verification passes immediately
            return "All steps are correct. VERIFIED_CORRECT"
        end)
        package.loaded["compute_alloc"] = nil
        local m = require("compute_alloc")
        local ctx = m.run({ task = "Math" })
        -- 1 classify + 1 generate + 1 verify = 3 (no revision needed)
        expect(#log).to.equal(3)
    end)
end)

-- ================================================================
-- gumbel_search — Gumbel + Sequential Halving
-- ================================================================
describe("gumbel_search", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("gumbel_search")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("gumbel_search")
        expect(m.meta.category).to.equal("reasoning")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("generates N candidates then halves until 1 winner", function()
        local gen_count = 0
        local eval_count = 0
        local log = mock_alc(function(prompt, opts, n)
            -- Generation calls have "solver #" in the system prompt
            if opts and opts.system and opts.system:match("solver #") then
                gen_count = gen_count + 1
                return "candidate answer " .. gen_count
            end
            -- Evaluation: return varying scores
            eval_count = eval_count + 1
            return tostring(5 + (eval_count % 5))
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Solve X", initial_candidates = 4 })

        -- 4 candidates generated
        expect(gen_count).to.equal(4)
        -- Sequential halving: round 1 = 4 evals → keep 2, round 2 = 2 evals → keep 1
        expect(eval_count).to.equal(6)
        -- Result structure
        expect(ctx.result.answer).to_not.equal(nil)
        expect(ctx.result.best_index).to_not.equal(nil)
        expect(ctx.result.halving_rounds).to.equal(2) -- log2(4) = 2
        expect(ctx.result.total_evaluations).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(10) -- 4 gen + 6 eval
    end)

    it("with 2 candidates = 1 halving round", function()
        local log = mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "7"
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 2 })
        expect(ctx.result.halving_rounds).to.equal(1)
        expect(ctx.result.total_evaluations).to.equal(2)
        expect(ctx.result.total_llm_calls).to.equal(4) -- 2 gen + 2 eval
    end)

    it("best_score is normalized to [0,1]", function()
        mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "8" -- score 8/10 = 0.8
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 2 })
        expect(ctx.result.best_score).to.equal(0.8)
    end)

    it("candidate_summary includes all candidates with scores", function()
        mock_alc(function(prompt)
            if prompt:match("solver") then return "candidate" end
            return "6"
        end)
        package.loaded["gumbel_search"] = nil
        local m = require("gumbel_search")
        local ctx = m.run({ task = "Q", initial_candidates = 4 })
        expect(#ctx.result.candidates).to.equal(4)
        for _, c in ipairs(ctx.result.candidates) do
            expect(c.index).to_not.equal(nil)
            expect(c.mean_score).to_not.equal(nil)
            expect(c.n_evals).to_not.equal(nil)
        end
    end)
end)

-- ================================================================
-- mbr_select — Minimum Bayes Risk Selection
-- ================================================================
describe("mbr_select", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("mbr_select")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("mbr_select")
        expect(m.meta.category).to.equal("selection")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("N=3: 3 gen + 3 pairwise = 6 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 3 then return "candidate " .. n end
            -- Pairwise similarity scores
            return "7"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "Test", n = 3 })
        -- 3 gen + C(3,2)=3 pairwise = 6
        expect(#log).to.equal(6)
        expect(ctx.result.total_llm_calls).to.equal(6)
        expect(#ctx.result.candidates).to.equal(3)
    end)

    it("N=4: 4 gen + 6 pairwise = 10 calls", function()
        local log = mock_alc(function(prompt, _, n)
            if n <= 4 then return "candidate " .. n end
            return "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "Test", n = 4 })
        -- 4 gen + C(4,2)=6 pairwise = 10
        expect(#log).to.equal(10)
    end)

    it("similarity matrix is symmetric", function()
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "c" .. n end
            return "8"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        local sim = ctx.result.similarity_matrix
        for i = 1, 3 do
            for j = 1, 3 do
                expect(sim[i][j]).to.equal(sim[j][i])
            end
            -- Self-similarity = 1.0
            expect(sim[i][i]).to.equal(1.0)
        end
    end)

    it("selects the candidate with highest MBR score", function()
        local pair_idx = 0
        local pair_scores = {
            -- For N=3: pairs are (1,2), (1,3), (2,3)
            "9",  -- 1-2: very similar
            "9",  -- 1-3: very similar
            "2",  -- 2-3: very different
        }
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "candidate " .. n end
            pair_idx = pair_idx + 1
            return pair_scores[pair_idx] or "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        -- Candidate 1 has highest agreement: sim(1,2)=0.9, sim(1,3)=0.9
        -- MBR(1) = (1.0 + 0.9 + 0.9) / 3 = 0.933
        -- MBR(2) = (0.9 + 1.0 + 0.2) / 3 = 0.7
        -- MBR(3) = (0.9 + 0.2 + 1.0) / 3 = 0.7
        expect(ctx.result.best_index).to.equal(1)
    end)

    it("ranking is sorted descending by MBR score", function()
        mock_alc(function(prompt, _, n)
            if n <= 3 then return "c" end
            return "5"
        end)
        package.loaded["mbr_select"] = nil
        local m = require("mbr_select")
        local ctx = m.run({ task = "T", n = 3 })
        local ranking = ctx.result.ranking
        expect(#ranking).to.equal(3)
        for i = 1, #ranking - 1 do
            expect(ranking[i].mbr_score >= ranking[i + 1].mbr_score).to.equal(true)
        end
    end)
end)

-- ================================================================
-- reflexion — Episodic Memory Self-Improvement
-- ================================================================
describe("reflexion", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("reflexion")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("reflexion")
        expect(m.meta.category).to.equal("refinement")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("passes on first trial = 2 calls, no reflection", function()
        local log = mock_alc(function(prompt, _, n)
            if n == 1 then return "correct answer" end
            -- Evaluation: passes (score 9 >= threshold 8)
            return '{"score": 9, "passed": true, "feedback": "excellent"}'
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Easy question" })
        expect(#log).to.equal(2) -- attempt + evaluate
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.total_trials).to.equal(1)
        expect(ctx.result.best_trial).to.equal(1)
        expect(#ctx.result.reflections).to.equal(0)
    end)

    it("fails trial 1, passes trial 2 = 5 calls with reflection", function()
        local trial = 0
        local log = mock_alc(function(prompt, _, n)
            -- Count trials by attempt generation
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                if trial == 1 then return "wrong approach" end
                return "correct approach using lesson"
            end
            -- Evaluation
            if prompt:match('"score"') or prompt:match("Evaluate") then
                if trial == 1 then
                    return '{"score": 4, "passed": false, "feedback": "wrong method"}'
                end
                return '{"score": 9, "passed": true, "feedback": "correct"}'
            end
            -- Reflection (after trial 1 failure)
            if prompt:match("Reflect on this failure") then
                return "Lesson: should use method B instead of A"
            end
            return "fallback"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Hard question" })
        -- Trial 1: attempt(1) + eval(2) + reflect(3)
        -- Trial 2: attempt(4) + eval(5)
        expect(#log).to.equal(5)
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.total_trials).to.equal(2)
        expect(ctx.result.best_trial).to.equal(2)
        expect(#ctx.result.reflections).to.equal(1)
    end)

    it("all trials fail = returns best, passed=false", function()
        local trial = 0
        local log = mock_alc(function(prompt)
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                return "attempt " .. trial
            end
            if prompt:match("Evaluate") or prompt:match('"score"') then
                -- Increasing scores but never passing threshold 8
                local scores = { 3, 5, 6 }
                local s = scores[trial] or 5
                return string.format('{"score": %d, "passed": false, "feedback": "still wrong"}', s)
            end
            if prompt:match("Reflect") then
                return "lesson from trial " .. trial
            end
            return "fallback"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Very hard", max_trials = 3 })
        expect(ctx.result.passed).to.equal(false)
        expect(ctx.result.total_trials).to.equal(3)
        -- Best = trial 3 (score 6)
        expect(ctx.result.best_score).to.equal(6)
        expect(ctx.result.best_trial).to.equal(3)
        -- 2 reflections (after trial 1 and 2, not after final trial 3)
        expect(#ctx.result.reflections).to.equal(2)
    end)

    it("episodic memory is passed to subsequent attempts", function()
        local attempt_prompts = {}
        local trial = 0
        mock_alc(function(prompt)
            if prompt:match("Provide a thorough") or prompt:match("correct solution") then
                trial = trial + 1
                attempt_prompts[trial] = prompt
                if trial >= 3 then return "finally correct" end
                return "attempt " .. trial
            end
            if prompt:match("Evaluate") then
                if trial >= 3 then
                    return '{"score": 9, "passed": true, "feedback": "good"}'
                end
                return '{"score": 3, "passed": false, "feedback": "bad"}'
            end
            if prompt:match("Reflect") then
                return "lesson_" .. trial
            end
            return "x"
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        m.run({ task = "Q", max_trials = 3 })

        -- Trial 1: no lessons in prompt
        expect(attempt_prompts[1]:match("Lessons")).to.equal(nil)
        -- Trial 2: has lesson_1
        expect(attempt_prompts[2]:match("lesson_1")).to_not.equal(nil)
        -- Trial 3: has both lesson_1 and lesson_2
        expect(attempt_prompts[3]:match("lesson_1")).to_not.equal(nil)
        expect(attempt_prompts[3]:match("lesson_2")).to_not.equal(nil)
    end)

    it("custom success_threshold is respected", function()
        mock_alc(function(prompt, _, n)
            if n == 1 then return "answer" end
            -- Score 6: passes threshold 5, would fail default 8
            return '{"score": 6, "passed": true, "feedback": "ok"}'
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Q", success_threshold = 5 })
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.best_score).to.equal(6)
    end)

    it("fallback parse_score when JSON decode fails", function()
        mock_alc(function(prompt, _, n)
            if n == 1 then return "answer" end
            -- Return non-JSON, fallback to parse_score
            return "Score: 9 out of 10. Very good work."
        end)
        package.loaded["reflexion"] = nil
        local m = require("reflexion")
        local ctx = m.run({ task = "Q" })
        -- parse_score extracts 9, which >= threshold 8
        expect(ctx.result.passed).to.equal(true)
        expect(ctx.result.best_score).to.equal(9)
    end)
end)
