--- Tests for governance packages: lineage, dissent, anti_cascade, topo_route
--- Structural tests + parse logic tests (no real LLM calls)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- ─── Test Helpers ──────────────────────────────────────────

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

--- Build a mock alc global. call_log records all llm calls.
--- llm_fn is called with (prompt, opts, call_number) and should return a string.
local function mock_alc(llm_fn)
    local call_log = {}
    local stats_log = {}
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
        stats = {
            record = function(key, value)
                stats_log[key] = value
            end,
        },
    }
    _G.alc = a
    return call_log, stats_log
end

local PACKAGES = { "lineage", "dissent", "anti_cascade", "topo_route" }

local function reset()
    _G.alc = nil
    for _, name in ipairs(PACKAGES) do
        package.loaded[name] = nil
    end
end

-- ================================================================
-- lineage
-- ================================================================
describe("lineage: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        mock_alc(function() return "mock" end)
        local m = require("lineage")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("lineage")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("governance")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.steps", function()
        mock_alc(function() return "mock" end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.steps is required")).to_not.equal(nil)
    end)

    it("errors with fewer than 2 steps", function()
        mock_alc(function() return "mock" end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ok, err = pcall(m.run, {
            task = "test",
            steps = { { name = "only_one", output = "text" } },
        })
        expect(ok).to.equal(false)
        expect(err:match("at least 2 steps")).to_not.equal(nil)
    end)
end)

describe("lineage: 2-step pipeline", function()
    lust.after(reset)

    it("makes 2N = 4 LLM calls for 2 steps", function()
        -- 2 steps: 2 extract + 1 trace + 1 conflict = 4 = 2×2
        local log, stats = mock_alc(function(prompt, _, n)
            if n <= 2 then
                -- Extract claims
                return "1. The system uses REST API\n2. Authentication is via JWT tokens\n3. Data is stored in PostgreSQL"
            elseif n == 3 then
                -- Trace dependencies
                return [[CLAIM 1: REST API usage
DERIVES_FROM: 1, 2
TRANSFORMATION: MERGED

CLAIM 2: JWT authentication
DERIVES_FROM: 2
TRANSFORMATION: PRESERVED

CLAIM 3: PostgreSQL storage
DERIVES_FROM: NONE
TRANSFORMATION: NOVEL]]
            else
                -- Conflict analysis
                return [[## Conflicts
None detected

## Ungrounded Claims
- UNGROUNDED: [implement claim_3]: PostgreSQL storage appears without prior mention

## Drift
None detected

## Integrity Score
SCORE: 0.85]]
            end
        end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ctx = m.run({
            task = "Design a web API",
            steps = {
                { name = "plan", output = "We will build a REST API with JWT auth" },
                { name = "implement", output = "Implemented REST with JWT and PostgreSQL" },
            },
        })
        expect(#log).to.equal(4)
        expect(ctx.result.integrity_score).to.equal(0.85)
        expect(#ctx.result.step_claims).to.equal(2)
        expect(#ctx.result.traces).to.equal(1)
        expect(stats["lineage_steps"]).to.equal(2)
        expect(stats["lineage_integrity"]).to.equal(0.85)
    end)

    it("makes 2N = 6 LLM calls for 3 steps", function()
        -- 3 steps: 3 extract + 2 trace + 1 conflict = 6 = 2×3
        local log = mock_alc(function(prompt, _, n)
            if n <= 3 then
                return "1. Claim A is a valid factual assertion\n2. Claim B is another assertion"
            elseif n <= 5 then
                return "CLAIM 1: Claim A\nDERIVES_FROM: 1\nTRANSFORMATION: PRESERVED"
            else
                return "## Conflicts\nNone detected\n\n## Ungrounded Claims\nNone detected\n\n## Drift\nNone detected\n\n## Integrity Score\nSCORE: 0.95"
            end
        end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ctx = m.run({
            task = "Multi-step task",
            steps = {
                { name = "step1", output = "output 1" },
                { name = "step2", output = "output 2" },
                { name = "step3", output = "output 3" },
            },
        })
        expect(#log).to.equal(6)
        expect(ctx.result.integrity_score).to.equal(0.95)
        expect(#ctx.result.traces).to.equal(2)
    end)
end)

describe("lineage: claim parsing", function()
    lust.after(reset)

    it("parses claims with various numbering formats", function()
        local log = mock_alc(function(_, _, n)
            if n <= 2 then
                -- Test various numbering: "1.", "2)", "3 "
                return "1. First claim with enough text\n2) Second claim with enough text\n3 Third claim with enough text\n4. Short"
            elseif n == 3 then
                return "CLAIM 1: c\nDERIVES_FROM: 1\nTRANSFORMATION: PRESERVED"
            else
                return "## Conflicts\nNone\n\n## Ungrounded Claims\nNone\n\n## Drift\nNone\n\n## Integrity Score\nSCORE: 1.0"
            end
        end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ctx = m.run({
            task = "test",
            steps = {
                { name = "a", output = "text" },
                { name = "b", output = "text" },
            },
        })
        -- "Short" (4 chars) should be filtered out (#text > 5)
        expect(#ctx.result.step_claims[1].claims).to.equal(3)
    end)

    it("handles missing SCORE gracefully", function()
        local log = mock_alc(function(_, _, n)
            if n <= 2 then
                return "1. A valid claim here for testing"
            elseif n == 3 then
                return "CLAIM 1: c\nDERIVES_FROM: 1\nTRANSFORMATION: PRESERVED"
            else
                return "## Conflicts\nSome issues\n\n## Ungrounded Claims\nSome\n\n## Drift\nNone"
                -- No SCORE line
            end
        end)
        package.loaded["lineage"] = nil
        local m = require("lineage")
        local ctx = m.run({
            task = "test",
            steps = {
                { name = "a", output = "text" },
                { name = "b", output = "text" },
            },
        })
        expect(ctx.result.integrity_score).to.equal(nil)
    end)
end)

-- ================================================================
-- dissent
-- ================================================================
describe("dissent: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        mock_alc(function() return "mock" end)
        local m = require("dissent")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("dissent")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("governance")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.consensus", function()
        mock_alc(function() return "mock" end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.consensus is required")).to_not.equal(nil)
    end)
end)

describe("dissent: consensus held (low merit)", function()
    lust.after(reset)

    it("makes 2 LLM calls when dissent has no merit", function()
        local log, stats = mock_alc(function(_, _, n)
            if n == 1 then
                return "Challenge 1: The consensus ignores edge cases."
            else
                return [[## Challenge Evaluations
1. Edge cases: INVALID — The consensus explicitly addresses edge cases in paragraph 2

## Overall Assessment
MERIT_SCORE: 0.1
REVISION_NEEDED: NO
KEY_ISSUES: ]]
            end
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "Design API",
            consensus = "We should use REST with proper error handling for edge cases",
        })
        expect(#log).to.equal(2) -- dissent + judge only
        expect(ctx.result.consensus_held).to.equal(true)
        expect(ctx.result.merit_score).to.equal(0.1)
        expect(ctx.result.revised_consensus).to.equal(nil)
        expect(ctx.result.output).to.equal("We should use REST with proper error handling for edge cases")
        expect(stats["dissent_revised"]).to.equal(0)
    end)
end)

describe("dissent: consensus revised (high merit)", function()
    lust.after(reset)

    it("makes 3 LLM calls when revision is needed", function()
        local log, stats = mock_alc(function(_, _, n)
            if n == 1 then
                return "Challenge 1: Security not addressed.\nChallenge 2: No rate limiting."
            elseif n == 2 then
                return [[## Challenge Evaluations
1. Security: VALID — No mention of authentication
2. Rate limiting: PARTIAL — Implied but not explicit

## Overall Assessment
MERIT_SCORE: 0.75
REVISION_NEEDED: YES
KEY_ISSUES: missing authentication, rate limiting not explicit]]
            else
                return [[## Revised Consensus
We should use REST with JWT authentication and explicit rate limiting.

## Changes Made
- Added JWT authentication requirement
- Made rate limiting explicit]]
            end
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "Design API",
            consensus = "We should use REST",
        })
        expect(#log).to.equal(3) -- dissent + judge + revise
        expect(ctx.result.consensus_held).to.equal(false)
        expect(ctx.result.merit_score).to.equal(0.75)
        expect(ctx.result.revised_consensus).to_not.equal(nil)
        expect(ctx.result.output).to.equal(ctx.result.revised_consensus)
        expect(stats["dissent_revised"]).to.equal(1)
    end)
end)

describe("dissent: with perspectives", function()
    lust.after(reset)

    it("includes perspectives in dissent prompt (string format)", function()
        local saw_perspectives = false
        mock_alc(function(prompt, _, n)
            if n == 1 and prompt:match("Perspective 1") and prompt:match("Perspective 2") then
                saw_perspectives = true
            end
            if n == 1 then return "Challenge" end
            return "MERIT_SCORE: 0.0\nREVISION_NEEDED: NO\nKEY_ISSUES: "
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        m.run({
            task = "Question",
            consensus = "Agreed answer",
            perspectives = { "Agent 1 thinks X", "Agent 2 thinks Y" },
        })
        expect(saw_perspectives).to.equal(true)
    end)

    it("includes perspectives in dissent prompt (table format)", function()
        local saw_named = false
        mock_alc(function(prompt, _, n)
            if n == 1 and prompt:match("Expert A") and prompt:match("Expert B") then
                saw_named = true
            end
            if n == 1 then return "Challenge" end
            return "MERIT_SCORE: 0.0\nREVISION_NEEDED: NO\nKEY_ISSUES: "
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        m.run({
            task = "Question",
            consensus = "Agreed answer",
            perspectives = {
                { name = "Expert A", output = "analysis A" },
                { name = "Expert B", output = "analysis B" },
            },
        })
        expect(saw_named).to.equal(true)
    end)
end)

describe("dissent: threshold gating", function()
    lust.after(reset)

    it("does not revise when merit_score < threshold despite REVISION_NEEDED=YES", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "Weak challenge" end
            return "MERIT_SCORE: 0.3\nREVISION_NEEDED: YES\nKEY_ISSUES: minor wording"
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "T",
            consensus = "C",
            merit_threshold = 0.6, -- default, but explicit
        })
        -- merit 0.3 < threshold 0.6 → no revision
        expect(#log).to.equal(2)
        expect(ctx.result.consensus_held).to.equal(true)
    end)

    it("respects custom threshold", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "Challenge" end
            if n == 2 then return "MERIT_SCORE: 0.3\nREVISION_NEEDED: YES\nKEY_ISSUES: issue" end
            return "Revised"
        end)
        package.loaded["dissent"] = nil
        local m = require("dissent")
        local ctx = m.run({
            task = "T",
            consensus = "C",
            merit_threshold = 0.2, -- lower threshold
        })
        -- merit 0.3 >= threshold 0.2 → revision triggered
        expect(#log).to.equal(3)
        expect(ctx.result.consensus_held).to.equal(false)
    end)
end)

-- ================================================================
-- anti_cascade
-- ================================================================
describe("anti_cascade: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        mock_alc(function() return "mock" end)
        local m = require("anti_cascade")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("anti_cascade")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("governance")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)

    it("errors without ctx.steps", function()
        mock_alc(function() return "mock" end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")
        local ok, err = pcall(m.run, { task = "test" })
        expect(ok).to.equal(false)
        expect(err:match("ctx.steps is required")).to_not.equal(nil)
    end)
end)

describe("anti_cascade: 2-step pipeline", function()
    lust.after(reset)

    it("makes 2N+1 = 5 LLM calls for 2 steps", function()
        -- 2 re-derive + 2 compare + 1 summary = 5
        local log, stats = mock_alc(function(prompt, _, n)
            if n <= 2 then
                -- Re-derivation
                return "Independent derivation of step output"
            elseif n <= 4 then
                -- Comparison
                return "DRIFT_SCORE: 0.15\nDRIFT_TYPE: MINOR_REFINEMENT\nDIVERGENCES:\n- Slight wording difference\nCASCADE_RISK: LOW\nEXPLANATION: Minor variation"
            else
                -- Summary
                return [[## Cascade Analysis Summary
No significant cascade detected.

## Flagged Steps
None.

## Cascade Pattern
DETECTED: NO
TREND: STABLE
DESCRIPTION: Drift is minimal and stable

## Overall Risk
RISK_LEVEL: LOW]]
            end
        end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")
        local ctx = m.run({
            task = "Build a feature",
            steps = {
                { name = "plan", instruction = "Create a plan", output = "The plan is X" },
                { name = "implement", instruction = "Implement the plan", output = "Implemented X" },
            },
        })
        expect(#log).to.equal(5)
        expect(#ctx.result.step_results).to.equal(2)
        expect(#ctx.result.flagged_steps).to.equal(0)
        expect(ctx.result.max_drift).to.equal(0.15)
        expect(stats["anti_cascade_steps"]).to.equal(2)
        expect(stats["anti_cascade_flagged"]).to.equal(0)
    end)
end)

describe("anti_cascade: drift detection", function()
    lust.after(reset)

    it("flags steps with drift above threshold", function()
        local log, stats = mock_alc(function(prompt, _, n)
            if n <= 2 then
                return "Re-derived output"
            elseif n == 3 then
                -- Step 1: low drift
                return "DRIFT_SCORE: 0.1\nDRIFT_TYPE: NONE\nDIVERGENCES:\nNone\nCASCADE_RISK: LOW\nEXPLANATION: Identical"
            elseif n == 4 then
                -- Step 2: high drift (cascade!)
                return "DRIFT_SCORE: 0.7\nDRIFT_TYPE: FACTUAL_DIVERGENCE\nDIVERGENCES:\n- Major factual error\nCASCADE_RISK: HIGH\nEXPLANATION: Pipeline drifted significantly"
            else
                return "## Cascade Analysis Summary\nCascade detected.\n\n## Flagged Steps\nStep 2\n\n## Cascade Pattern\nDETECTED: YES\nTREND: INCREASING\nDESCRIPTION: Drift increasing\n\n## Overall Risk\nRISK_LEVEL: HIGH"
            end
        end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")
        local ctx = m.run({
            task = "Build a feature",
            steps = {
                { name = "step1", instruction = "Do step 1", output = "Step 1 output" },
                { name = "step2", instruction = "Do step 2", output = "Step 2 output with error" },
            },
        })
        -- step1 drift=0.1 < 0.4 (not flagged), step2 drift=0.7 >= 0.4 (flagged)
        expect(#ctx.result.flagged_steps).to.equal(1)
        expect(ctx.result.flagged_steps[1]).to.equal("step2")
        expect(ctx.result.max_drift).to.equal(0.7)
        expect(ctx.result.step_results[1].flagged).to.equal(false)
        expect(ctx.result.step_results[2].flagged).to.equal(true)
        expect(ctx.result.step_results[2].drift_type).to.equal("FACTUAL_DIVERGENCE")
        expect(ctx.result.step_results[2].cascade_risk).to.equal("HIGH")
        expect(stats["anti_cascade_flagged"]).to.equal(1)
        expect(stats["anti_cascade_max_drift"]).to.equal(0.7)
    end)

    it("respects custom drift_threshold", function()
        local log = mock_alc(function(_, _, n)
            if n == 1 then return "re-derive" end
            if n == 2 then
                return "DRIFT_SCORE: 0.25\nDRIFT_TYPE: ADDED_DETAIL\nDIVERGENCES:\n- Extra detail\nCASCADE_RISK: LOW\nEXPLANATION: Minor"
            end
            return "## Cascade Analysis Summary\nOK\n\n## Flagged Steps\nNone\n\n## Cascade Pattern\nDETECTED: NO\nTREND: STABLE\nDESCRIPTION: ok\n\n## Overall Risk\nRISK_LEVEL: LOW"
        end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")

        -- With default threshold (0.4): not flagged
        local ctx1 = m.run({
            task = "T",
            steps = { { name = "s1", instruction = "i1", output = "o1" } },
        })
        expect(#ctx1.result.flagged_steps).to.equal(0)

        -- With lower threshold (0.2): flagged
        package.loaded["anti_cascade"] = nil
        local m2 = require("anti_cascade")
        mock_alc(function(_, _, n)
            if n == 1 then return "re-derive" end
            if n == 2 then
                return "DRIFT_SCORE: 0.25\nDRIFT_TYPE: ADDED_DETAIL\nDIVERGENCES:\n- Extra\nCASCADE_RISK: MEDIUM\nEXPLANATION: Minor"
            end
            return "## Cascade Analysis Summary\nOK\n\n## Flagged Steps\ns1\n\n## Cascade Pattern\nDETECTED: NO\nTREND: STABLE\nDESCRIPTION: ok\n\n## Overall Risk\nRISK_LEVEL: LOW"
        end)
        local ctx2 = m2.run({
            task = "T",
            steps = { { name = "s1", instruction = "i1", output = "o1" } },
            drift_threshold = 0.2,
        })
        expect(#ctx2.result.flagged_steps).to.equal(1)
    end)
end)

describe("anti_cascade: uses instruction for re-derivation", function()
    lust.after(reset)

    it("passes instruction to re-derivation prompt", function()
        local saw_instruction = false
        mock_alc(function(prompt, _, n)
            if n == 1 and prompt:match("Generate a detailed plan") then
                saw_instruction = true
            end
            if n <= 1 then return "re-derive" end
            if n <= 2 then
                return "DRIFT_SCORE: 0.0\nDRIFT_TYPE: NONE\nDIVERGENCES:\nNone\nCASCADE_RISK: LOW\nEXPLANATION: Same"
            end
            return "## Cascade Analysis Summary\nOK\n\n## Flagged Steps\nNone\n\n## Cascade Pattern\nDETECTED: NO\nTREND: STABLE\nDESCRIPTION: ok\n\n## Overall Risk\nRISK_LEVEL: LOW"
        end)
        package.loaded["anti_cascade"] = nil
        local m = require("anti_cascade")
        m.run({
            task = "Build feature X",
            steps = {
                { name = "plan", instruction = "Generate a detailed plan", output = "Plan text" },
            },
        })
        expect(saw_instruction).to.equal(true)
    end)
end)

-- ================================================================
-- topo_route
-- ================================================================
describe("topo_route: meta", function()
    lust.after(reset)

    it("has correct meta fields", function()
        mock_alc(function() return "mock" end)
        local m = require("topo_route")
        expect(m.meta).to_not.equal(nil)
        expect(m.meta.name).to.equal("topo_route")
        expect(m.meta.version).to.equal("0.1.0")
        expect(m.meta.category).to.equal("routing")
        expect(type(m.run)).to.equal("function")
    end)

    it("errors without ctx.task", function()
        mock_alc(function() return "mock" end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ok, err = pcall(m.run, {})
        expect(ok).to.equal(false)
        expect(err:match("ctx.task is required")).to_not.equal(nil)
    end)
end)

describe("topo_route: topology recommendation", function()
    lust.after(reset)

    it("makes exactly 1 LLM call", function()
        local log = mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: HIGH
DECOMPOSABILITY: LOW
VERIFICATION_NEED: HIGH
ADVERSARIAL_VALUE: LOW
COST_SENSITIVITY: LOW

## Recommendation
TOPOLOGY: linear
CONFIDENCE: 0.8
REASONING: Sequential task with clear stage boundaries

## Alternative
TOPOLOGY: ensemble
WHEN: If higher reliability is needed

## Governance Add-ons
lineage, anti_cascade]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Implement a multi-step data pipeline" })
        expect(#log).to.equal(1)
    end)

    it("parses linear topology correctly", function()
        local log, stats = mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: MEDIUM
DECOMPOSABILITY: LOW
VERIFICATION_NEED: HIGH
ADVERSARIAL_VALUE: LOW
COST_SENSITIVITY: MEDIUM

## Recommendation
TOPOLOGY: linear
CONFIDENCE: 0.85
REASONING: Sequential pipeline task

## Alternative
TOPOLOGY: star
WHEN: If tasks are independent

## Governance Add-ons
lineage]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Build a data pipeline" })

        expect(ctx.result.topology).to.equal("linear")
        expect(ctx.result.confidence).to.equal(0.85)
        expect(ctx.result.dimensions.complexity).to.equal("MEDIUM")
        expect(ctx.result.dimensions.verification_need).to.equal("HIGH")
        expect(stats["topo_route_topology"]).to.equal("linear")
        expect(stats["topo_route_confidence"]).to.equal(0.85)

        -- linear packages should include orch_fixpipe, orch_gatephase + governance
        local has_fixpipe = false
        local has_lineage_addon = false
        for _, p in ipairs(ctx.result.packages) do
            if p.package == "orch_fixpipe" then has_fixpipe = true end
            if p.package == "lineage" and p.role == "governance" then has_lineage_addon = true end
        end
        expect(has_fixpipe).to.equal(true)
        expect(has_lineage_addon).to.equal(true)
    end)

    it("parses debate topology correctly", function()
        mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: HIGH
DECOMPOSABILITY: LOW
VERIFICATION_NEED: HIGH
ADVERSARIAL_VALUE: HIGH
COST_SENSITIVITY: LOW

## Recommendation
TOPOLOGY: debate
CONFIDENCE: 0.9
REASONING: Controversial question benefits from adversarial analysis

## Alternative
TOPOLOGY: star
WHEN: If cost is a concern

## Governance Add-ons
dissent]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Should we use microservices or monolith?" })

        expect(ctx.result.topology).to.equal("debate")
        expect(ctx.result.confidence).to.equal(0.9)

        local has_triad = false
        local has_dissent = false
        for _, p in ipairs(ctx.result.packages) do
            if p.package == "triad" then has_triad = true end
            if p.package == "dissent" then has_dissent = true end
        end
        expect(has_triad).to.equal(true)
        expect(has_dissent).to.equal(true)
    end)
end)

describe("topo_route: parse_topology section isolation", function()
    lust.after(reset)

    it("extracts Recommendation topology, not Alternative", function()
        mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: LOW
DECOMPOSABILITY: HIGH
VERIFICATION_NEED: LOW
ADVERSARIAL_VALUE: LOW
COST_SENSITIVITY: HIGH

## Recommendation
TOPOLOGY: escalation
CONFIDENCE: 0.7
REASONING: Cost-sensitive variable difficulty

## Alternative
TOPOLOGY: linear
WHEN: If all tasks are similar difficulty

## Governance Add-ons
none]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Process batch of varied tasks" })

        -- Should pick escalation (Recommendation), not linear (Alternative)
        expect(ctx.result.topology).to.equal("escalation")
    end)
end)

describe("topo_route: fallback on unrecognized topology", function()
    lust.after(reset)

    it("falls back to linear for unknown topology name", function()
        mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: LOW
DECOMPOSABILITY: LOW
VERIFICATION_NEED: LOW
ADVERSARIAL_VALUE: LOW
COST_SENSITIVITY: LOW

## Recommendation
TOPOLOGY: quantum_entangled
CONFIDENCE: 0.5
REASONING: Unknown

## Alternative
TOPOLOGY: linear
WHEN: Always

## Governance Add-ons
none]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Something" })

        expect(ctx.result.topology).to.equal("linear")
    end)
end)

describe("topo_route: governance add-ons parsing", function()
    lust.after(reset)

    it("parses multiple governance add-ons", function()
        mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: HIGH
DECOMPOSABILITY: LOW
VERIFICATION_NEED: HIGH
ADVERSARIAL_VALUE: HIGH
COST_SENSITIVITY: LOW

## Recommendation
TOPOLOGY: linear
CONFIDENCE: 0.8
REASONING: Complex sequential

## Alternative
TOPOLOGY: dag
WHEN: If branching needed

## Governance Add-ons
lineage, dissent, anti_cascade]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Critical pipeline" })

        expect(#ctx.result.governance_addons).to.equal(3)
        local found = {}
        for _, g in ipairs(ctx.result.governance_addons) do
            found[g] = true
        end
        expect(found["lineage"]).to.equal(true)
        expect(found["dissent"]).to.equal(true)
        expect(found["anti_cascade"]).to.equal(true)
    end)

    it("returns empty for 'none'", function()
        mock_alc(function()
            return [[## Task Analysis
COMPLEXITY: LOW
DECOMPOSABILITY: LOW
VERIFICATION_NEED: LOW
ADVERSARIAL_VALUE: LOW
COST_SENSITIVITY: HIGH

## Recommendation
TOPOLOGY: escalation
CONFIDENCE: 0.7
REASONING: Simple

## Alternative
TOPOLOGY: linear
WHEN: fallback

## Governance Add-ons
none]]
        end)
        package.loaded["topo_route"] = nil
        local m = require("topo_route")
        local ctx = m.run({ task = "Quick task" })

        expect(#ctx.result.governance_addons).to.equal(0)
    end)
end)
