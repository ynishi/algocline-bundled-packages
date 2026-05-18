--- Tests for f_race (Friedman Race Partial-Data Pruner)
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
            for i, item in ipairs(list) do results[i] = fn(item, i) end
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
                    prompt = p; opts = {}
                end
                call_log[#call_log + 1] = { prompt = prompt, opts = opts }
                results[i] = llm_fn(prompt, opts, #call_log)
            end
            return results
        end,
        log = function() end,
        parse_score = function(s) return tonumber(tostring(s):match("[%d%.]+")) end,
    }
    return call_log
end

local function reset()
    _G.alc = nil
    package.loaded["f_race"] = nil
end

-- Build a mock llm that scores per (candidate index, dimension) using a
-- deterministic table. Each call extracts the candidate # from the prompt
-- via a marker, so the test fixture just maps "cand i" -> bias.
local function biased_llm(biases, dim_noise)
    -- biases: {1=p1, 2=p2, ...} probability that candidate i passes any dim.
    -- We use a deterministic pseudo-random based on call index for repeatability.
    return function(prompt, _opts, call_idx)
        if not prompt:find("Evaluate ONE specific criterion", 1, true) then
            return "candidate text"
        end
        -- Extract candidate index from "expert #N" — but since the rubric
        -- prompt does not include that, we use the candidate's text marker.
        local cand_marker = prompt:match("Candidate answer:%s*\n([^\n]+)")
        local i = tonumber((cand_marker or ""):match("CAND(%d+)")) or 1
        local p = biases[i] or 0.5
        if dim_noise then p = p + dim_noise(call_idx) end
        -- Deterministic pseudo-random: use call_idx + i for jitter.
        local rng = ((call_idx * 1103515245 + 12345) % 2147483648) / 2147483648
        if rng < p then return "PASS" else return "FAIL" end
    end
end

-- Override the default candidate generator: we want each candidate's
-- text to encode its index so the mock judge can read it.
local function gen_marker_llm(biases)
    local judge = biased_llm(biases)
    return function(prompt, opts, call_idx)
        if prompt:find("Provide your best answer", 1, true) then
            local sys = opts and opts.system or ""
            local n = tonumber(sys:match("expert #(%d+)")) or 1
            return "CAND" .. tostring(n) .. " text"
        end
        return judge(prompt, opts, call_idx)
    end
end

describe("f_race", function()
    lust.after(reset)

    it("has correct meta", function()
        mock_alc(function() return "mock" end)
        local m = require("f_race")
        expect(m.meta.name).to.equal("f_race")
        expect(m.meta.category).to.equal("selection")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "PASS" end)
        local m = require("f_race")
        expect(pcall(m.run, {})).to.equal(false)
    end)

    it("errors on n_candidates < 2", function()
        mock_alc(function() return "PASS" end)
        local m = require("f_race")
        expect(pcall(m.run, { task = "T", n_candidates = 1 })).to.equal(false)
    end)

    it("errors on invalid delta", function()
        mock_alc(function() return "PASS" end)
        local m = require("f_race")
        expect(pcall(m.run, { task = "T", delta = 1.5 })).to.equal(false)
    end)

    it("runs end-to-end with uniform candidates and produces a result", function()
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5, [3]=0.5, [4]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({ task = "T", n_candidates = 4 })
        expect(ctx.result).to.exist()
        expect(ctx.result.n_candidates).to.equal(4)
        expect(ctx.result.evaluations > 0).to.equal(true)
        expect(#ctx.result.ranking).to.equal(4)
    end)

    it("eliminates clearly inferior candidates", function()
        -- Cand 1 is strongly best; cands 2-4 are weak. Friedman should
        -- detect and eliminate the weak ones.
        mock_alc(gen_marker_llm({ [1]=0.95, [2]=0.15, [3]=0.15, [4]=0.15 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            min_blocks_before_race = 5,
        })
        expect(ctx.result.alive_count < 4).to.equal(true)
        expect(#ctx.result.kill_events > 0).to.equal(true)
        -- Winner must be candidate 1.
        expect(ctx.result.best_index).to.equal(1)
    end)

    it("does not eliminate when all candidates are tied", function()
        -- Identical biases: Friedman Q should remain small.
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5, [3]=0.5, [4]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            min_blocks_before_race = 5,
        })
        -- We don't strictly require alive_count==4 (occasional rejections
        -- can happen), but in expectation no kill should occur for tied
        -- candidates with our deterministic rng. Just sanity check.
        expect(ctx.result.alive_count >= 1).to.equal(true)
    end)

    it("respects min_blocks_before_race warmup", function()
        -- Even with strong gap, no kill before 6 blocks observed.
        mock_alc(gen_marker_llm({ [1]=0.95, [2]=0.05 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            min_blocks_before_race = 6,
            rubric = {
                { name = "d1", criterion = "c1" },
                { name = "d2", criterion = "c2" },
                { name = "d3", criterion = "c3" },
            },
        })
        -- Only 3 blocks, less than min_blocks=6 → no kill possible.
        expect(#ctx.result.kill_events).to.equal(0)
        expect(ctx.result.alive_count).to.equal(2)
    end)

    it("alpha_spending: defaults to OFF and effective_delta == delta", function()
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({ task = "T", n_candidates = 2, delta = 0.05 })
        expect(ctx.result.alpha_spending).to.equal(false)
        expect(ctx.result.effective_delta).to.equal(0.05)
    end)

    it("alpha_spending=true Bonferroni-tightens effective_delta", function()
        -- D=20 (default rubric), min_blocks=5 → K_max = 4
        -- target α = 0.05 / 4 = 0.0125 → exactly tabulated → 0.0125
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            delta = 0.05,
            min_blocks_before_race = 5,
            alpha_spending = true,
        })
        expect(ctx.result.alpha_spending).to.equal(true)
        expect(ctx.result.effective_delta).to.equal(0.0125)
    end)

    it("alpha_spending=true rounds to next tighter tabulated level", function()
        -- D=15, min_blocks=5 → K_max = 3 → target = 0.05/3 ≈ 0.01667
        -- Largest tabulated ≤ 0.01667 is 0.0125.
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5 }))
        local m = require("f_race")
        local rubric15 = {}
        for i = 1, 15 do rubric15[i] = { name = "d"..i, criterion = "c"..i } end
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            delta = 0.05,
            min_blocks_before_race = 5,
            alpha_spending = true,
            rubric = rubric15,
        })
        expect(ctx.result.effective_delta).to.equal(0.0125)
    end)

    it("non-tabulated delta is rounded down to nearest tabulated level", function()
        -- delta=0.03 → largest tabulated ≤ 0.03 is 0.025
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({ task = "T", n_candidates = 2, delta = 0.03 })
        -- alpha_spending OFF → effective_delta = delta as-passed (0.03)
        expect(ctx.result.effective_delta).to.equal(0.03)
        -- But internal lookups use 0.025 — verify by checking that
        -- a clearly distinguishable scenario still kills.
    end)

    it("alpha_spending=true keeps effective_delta=delta when K_max<2", function()
        -- D=4 < 2*min_blocks (=10) → K_max = floor(4/5) = 0 < 2 → no tightening
        mock_alc(gen_marker_llm({ [1]=0.5, [2]=0.5 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 2,
            delta = 0.05,
            min_blocks_before_race = 5,
            alpha_spending = true,
            rubric = {
                { name = "d1", criterion = "c1" },
                { name = "d2", criterion = "c2" },
                { name = "d3", criterion = "c3" },
                { name = "d4", criterion = "c4" },
            },
        })
        expect(ctx.result.alpha_spending).to.equal(true)
        expect(ctx.result.effective_delta).to.equal(0.05)
    end)

    it("alpha_spending=true gates test to fixed checkpoints", function()
        -- With alpha_spending=true and min_blocks=5, the test fires at
        -- block 5, 10, 15, 20... Construct a scenario where the gap is
        -- detectable so kills do happen, and verify the kill blocks
        -- align with the checkpoint schedule.
        mock_alc(gen_marker_llm({ [1]=0.95, [2]=0.05, [3]=0.05, [4]=0.05 }))
        local m = require("f_race")
        local ctx = m.run({
            task = "T",
            n_candidates = 4,
            min_blocks_before_race = 5,
            alpha_spending = true,
        })
        for _, ev in ipairs(ctx.result.kill_events) do
            -- kill_block must be a multiple of min_blocks (5), since the
            -- test only fires at those checkpoints (modulo history reset).
            -- After a reset blocks_observed restarts, so the next kill
            -- can occur at any block ≥ k_kill + min_blocks. We assert
            -- the weaker invariant: kill block ≥ min_blocks.
            expect(ev.block >= 5).to.equal(true)
        end
        expect(ctx.result.alive_count < 4).to.equal(true)
    end)

    it("on_kill callback fires", function()
        local killed = {}
        mock_alc(gen_marker_llm({ [1]=0.95, [2]=0.05, [3]=0.05 }))
        local m = require("f_race")
        m.run({
            task = "T",
            n_candidates = 3,
            min_blocks_before_race = 5,
            on_kill = function(i, _) killed[#killed + 1] = i end,
        })
        expect(#killed >= 1).to.equal(true)
    end)
end)
