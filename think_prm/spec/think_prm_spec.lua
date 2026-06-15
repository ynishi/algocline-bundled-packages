--- Tests for think_prm package (ThinkPRM, Khalifa et al. 2025
--- arXiv:2504.16828). Per-step verifier chain → \boxed{correct|incorrect}
--- extraction → solution-level aggregation. Training-free / zero-shot
--- path only (force-decode logits aggregation is out of scope).
---
--- Covers:
---   - Figure 14 verbatim template + early-stop variant
---   - parse_verdicts (case-insensitive, unknown token skip, invalid)
---   - aggregate (any_incorrect / all_correct)
---   - verify (single LLM call) + run (K-CoT averaging)
---   - score_majority_threshold override
---   - nested dispatch via M.<entry>
---
--- Run via:
---   just alc-pkg-test-file think_prm/spec/think_prm_spec.lua

local describe, it, expect = lust.describe, lust.it, lust.expect

local function reset()
    _G.alc = nil
    package.loaded["think_prm"] = nil
end

--- Build a mock alc whose llm always returns the supplied response (or
--- the i-th from `responses` if supplied). Used by run() / verify().
local function mock_alc(opts)
    opts = opts or {}
    local responses = opts.responses
    local idx = 0
    local call_log = {}
    _G.alc = {
        llm = function(prompt, options)
            call_log[#call_log + 1] = { prompt = prompt, opts = options }
            idx = idx + 1
            if responses then
                return responses[idx] or responses[#responses]
            end
            return opts.response or ""
        end,
        log = setmetatable(
            { warn = function(_) end, info = function(_) end },
            { __call = function(_, _, _) end }
        ),
    }
    return call_log
end

-- ============================================================
-- meta + spec exposure
-- ============================================================

describe("think_prm.meta", function()
    reset()
    mock_alc()
    local m = require("think_prm")
    it("name / version / category", function()
        expect(m.meta.name).to.equal("think_prm")
        expect(m.meta.version).to.equal("0.2.0")
        expect(m.meta.category).to.equal("validation")
    end)
end)

describe("think_prm.spec", function()
    reset()
    mock_alc()
    local m = require("think_prm")
    it("exposes build_prompt / parse_verdicts / aggregate / verify / run", function()
        for _, entry in ipairs({
            "build_prompt", "parse_verdicts", "aggregate", "verify", "run",
        }) do
            expect(m.spec.entries[entry]).to_not.equal(nil)
            expect(m.spec.entries[entry].input).to_not.equal(nil)
            expect(m.spec.entries[entry].result).to_not.equal(nil)
        end
    end)
end)

-- ============================================================
-- build_prompt (Figure 14 + early_stop knob)
-- ============================================================

describe("think_prm.build_prompt", function()
    it("errors when ctx.problem is missing", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ok = pcall(m.build_prompt, { solution_steps = { "s1" } })
        expect(ok).to.equal(false)
    end)

    it("default: renders Figure 14 verbatim with step-indexed solution + early-stop line", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.build_prompt({
            problem = "What is 1+1?",
            solution_steps = { "first step text", "second step text" },
        })
        expect(ctx.result.prompt:find("What is 1+1?", 1, true)).to_not.equal(nil)
        expect(ctx.result.prompt:find("Step 1: first step text", 1, true)).to_not.equal(nil)
        expect(ctx.result.prompt:find("Step 2: second step text", 1, true)).to_not.equal(nil)
        expect(ctx.result.prompt:find("Let's verify step by step", 1, true)).to_not.equal(nil)
        -- Figure 14 early-stop tail must appear (default)
        expect(ctx.result.prompt:find("Once you find an incorrect step", 1, true)).to_not.equal(nil)
    end)

    it("early_stop_on_incorrect=false substitutes the early-stop tail", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.build_prompt({
            problem = "P",
            solution_steps = { "s1" },
            early_stop_on_incorrect = false,
        })
        -- Figure 14 last line must be absent
        expect(ctx.result.prompt:find("Once you find an incorrect step", 1, true)).to.equal(nil)
        -- Replacement instruction must be present
        expect(ctx.result.prompt:find("Critique every step", 1, true)).to_not.equal(nil)
    end)

    it("prompt_template override wins over early_stop_on_incorrect", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.build_prompt({
            problem = "P",
            solution_steps = { "s1" },
            prompt_template = "CUSTOM_PROMPT for %s with %s",
            early_stop_on_incorrect = true, -- ignored when template is supplied
        })
        expect(ctx.result.prompt:find("CUSTOM_PROMPT for P", 1, true)).to_not.equal(nil)
        expect(ctx.result.prompt:find("Once you find an incorrect step", 1, true)).to.equal(nil)
    end)
end)

-- ============================================================
-- parse_verdicts
-- ============================================================

describe("think_prm.parse_verdicts", function()
    it("extracts ordered verdicts from a well-formed chain", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local chain = [[
Let's verify step by step:
Step 1: looks fine. The step is \boxed{correct}
Step 2: also fine. The step is \boxed{correct}
Step 3: this is wrong. The step is \boxed{incorrect}
]]
        local ctx = m.parse_verdicts({ chain = chain })
        expect(#ctx.result.verdicts).to.equal(3)
        expect(ctx.result.verdicts[1]).to.equal("correct")
        expect(ctx.result.verdicts[2]).to.equal("correct")
        expect(ctx.result.verdicts[3]).to.equal("incorrect")
        expect(ctx.result.invalid).to.equal(false)
    end)

    it("marks invalid when no \\boxed tokens are present", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.parse_verdicts({ chain = "I refuse to follow the format" })
        expect(#ctx.result.verdicts).to.equal(0)
        expect(ctx.result.invalid).to.equal(true)
    end)

    it("is case-insensitive for the boxed token value", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.parse_verdicts({
            chain = [[Step 1: The step is \boxed{CORRECT}]],
        })
        expect(ctx.result.verdicts[1]).to.equal("correct")
    end)

    it("ignores unknown \\boxed tokens (e.g. \\boxed{maybe})", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.parse_verdicts({
            chain = [[
Step 1: The step is \boxed{correct}
Step 2: hmm... \boxed{maybe}
Step 3: nope. \boxed{incorrect}
]],
        })
        expect(#ctx.result.verdicts).to.equal(2)
        expect(ctx.result.verdicts[1]).to.equal("correct")
        expect(ctx.result.verdicts[2]).to.equal("incorrect")
    end)
end)

-- ============================================================
-- aggregate
-- ============================================================

describe("think_prm.aggregate", function()
    it("any_incorrect: any incorrect step → solution incorrect", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.aggregate({
            verdicts = { "correct", "incorrect", "correct" },
        })
        expect(ctx.result.correct).to.equal(false)
        expect(ctx.result.invalid).to.equal(false)
    end)

    it("any_incorrect: all correct → solution correct", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.aggregate({
            verdicts = { "correct", "correct", "correct" },
        })
        expect(ctx.result.correct).to.equal(true)
    end)

    it("empty verdicts → invalid", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.aggregate({ verdicts = {} })
        expect(ctx.result.invalid).to.equal(true)
        expect(ctx.result.correct).to.equal(false)
    end)

    it("all_correct method: any non-correct → solution incorrect", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ctx = m.aggregate({
            verdicts = { "correct", "incorrect" },
            method = "all_correct",
        })
        expect(ctx.result.correct).to.equal(false)
    end)
end)

-- ============================================================
-- verify
-- ============================================================

describe("think_prm.verify", function()
    it("errors when ctx.problem is missing", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ok = pcall(m.verify, { solution_steps = { "s" } })
        expect(ok).to.equal(false)
    end)

    it("calls LLM once and parses verdicts", function()
        reset()
        local log = mock_alc({
            response = [[
Let's verify step by step:
Step 1: ok. \boxed{correct}
Step 2: ok. \boxed{correct}
]],
        })
        local m = require("think_prm")
        local ctx = m.verify({
            problem = "P",
            solution_steps = { "s1", "s2" },
        })
        expect(#log).to.equal(1)
        expect(#ctx.result.verdicts).to.equal(2)
        expect(ctx.result.invalid).to.equal(false)
    end)
end)

-- ============================================================
-- run — K-CoT averaging
-- ============================================================

describe("think_prm.run — K-CoT averaging", function()
    it("errors when ctx.problem is missing", function()
        reset()
        mock_alc()
        local m = require("think_prm")
        local ok = pcall(m.run, { solution_steps = { "s" } })
        expect(ok).to.equal(false)
    end)

    it("default n_parallel_cots=1: 1 LLM call, parses verdicts, all-correct → correct", function()
        reset()
        local log = mock_alc({
            response = [[
Let's verify step by step:
Step 1: \boxed{correct}
Step 2: \boxed{correct}
]],
        })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1", "s2" },
        })
        expect(#log).to.equal(1)
        expect(ctx.result.correct).to.equal(true)
        expect(ctx.result.score).to.equal(1)
        expect(ctx.result.valid_chains).to.equal(1)
        expect(ctx.result.invalid).to.equal(false)
        expect(#ctx.result.chains).to.equal(1)
    end)

    it("default n_parallel_cots=1: any incorrect step → not correct", function()
        reset()
        mock_alc({
            response = [[
Step 1: \boxed{correct}
Step 2: \boxed{incorrect}
]],
        })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1", "s2" },
        })
        expect(ctx.result.correct).to.equal(false)
        expect(ctx.result.score).to.equal(0)
    end)

    it("n_parallel_cots=3: K-CoT averaging produces fractional score", function()
        reset()
        local good = "Step 1: \\boxed{correct}\nStep 2: \\boxed{correct}"
        local bad = "Step 1: \\boxed{incorrect}"
        local log = mock_alc({ responses = { good, good, bad } })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1", "s2" },
            n_parallel_cots = 3,
        })
        expect(#log).to.equal(3)
        expect(ctx.result.valid_chains).to.equal(3)
        -- 2 correct / 3 valid = 2/3
        expect(ctx.result.score > 0.6 and ctx.result.score < 0.7).to.equal(true)
        expect(ctx.result.correct).to.equal(true)
    end)

    it("all invalid chains → invalid=true, score=0, correct=false", function()
        reset()
        mock_alc({
            responses = { "garbage 1", "garbage 2", "garbage 3" },
        })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1" },
            n_parallel_cots = 3,
        })
        expect(ctx.result.invalid).to.equal(true)
        expect(ctx.result.score).to.equal(0)
        expect(ctx.result.valid_chains).to.equal(0)
        expect(ctx.result.correct).to.equal(false)
    end)

    it("mixed valid/invalid: invalid chains excluded from denominator", function()
        reset()
        local good = "Step 1: \\boxed{correct}"
        mock_alc({ responses = { good, good, "garbage" } })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1" },
            n_parallel_cots = 3,
        })
        expect(ctx.result.valid_chains).to.equal(2)
        expect(ctx.result.score).to.equal(1)
        expect(ctx.result.correct).to.equal(true)
        expect(ctx.result.invalid).to.equal(false)
    end)

    it("score_majority_threshold=0.75 flips a 2/3 score from correct to not correct", function()
        reset()
        local good = "Step 1: \\boxed{correct}"
        local bad = "Step 1: \\boxed{incorrect}"
        mock_alc({ responses = { good, good, bad } })
        local m = require("think_prm")
        local ctx = m.run({
            problem = "P",
            solution_steps = { "s1" },
            n_parallel_cots = 3,
            score_majority_threshold = 0.75,
        })
        -- 2/3 = 0.666... < 0.75
        expect(ctx.result.score > 0.6 and ctx.result.score < 0.7).to.equal(true)
        expect(ctx.result.correct).to.equal(false)
    end)
end)

-- ============================================================
-- run — nested dispatch via M.<entry>
-- ============================================================

describe("think_prm.run — nested dispatch via M.<entry>", function()
    it("M.run calls through M.verify (K times)", function()
        reset()
        mock_alc({ response = "Step 1: \\boxed{correct}" })
        local m = require("think_prm")
        local marker = 0
        local orig = m.verify
        m.verify = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({
            problem = "P",
            solution_steps = { "s1" },
            n_parallel_cots = 3,
        })
        expect(marker).to.equal(3)
    end)

    it("M.run calls through M.aggregate (K times, one per valid chain)", function()
        reset()
        mock_alc({ response = "Step 1: \\boxed{correct}" })
        local m = require("think_prm")
        local marker = 0
        local orig = m.aggregate
        m.aggregate = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.run({
            problem = "P",
            solution_steps = { "s1" },
            n_parallel_cots = 3,
        })
        expect(marker).to.equal(3)
    end)

    it("M.verify calls through M.build_prompt", function()
        reset()
        mock_alc({ response = "Step 1: \\boxed{correct}" })
        local m = require("think_prm")
        local marker = 0
        local orig = m.build_prompt
        m.build_prompt = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.verify({
            problem = "P",
            solution_steps = { "s1" },
        })
        expect(marker).to.equal(1)
    end)

    it("M.verify calls through M.parse_verdicts", function()
        reset()
        mock_alc({ response = "Step 1: \\boxed{correct}" })
        local m = require("think_prm")
        local marker = 0
        local orig = m.parse_verdicts
        m.parse_verdicts = function(ctx)
            marker = marker + 1
            return orig(ctx)
        end
        m.verify({
            problem = "P",
            solution_steps = { "s1" },
        })
        expect(marker).to.equal(1)
    end)
end)

reset()
