--- Tests for topo_route (routing — topology recommendation + governance add-on selection).
--- Extracted from tests/test_governance.lua (Phase C decomposition).

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

local function reset()
    _G.alc = nil
    package.loaded["topo_route"] = nil
end

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
