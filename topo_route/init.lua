--- topo_route — Topology-aware meta-router for multi-agent pipelines
---
--- Analyzes task characteristics and recommends the optimal agent
--- topology (linear, star, DAG, mesh, debate) along with concrete
--- package combinations from the algocline bundled collection.
---
--- Generalizes the "Topological Sensitivity" finding from "From Spark
--- to Fire" (Xie et al., AAMAS 2026), which demonstrated that the
--- SAME agents connected in different topologies show up to 40%
--- reliability variation. Topology selection is therefore a first-class
--- architectural decision, not an implementation detail.
---
--- Also informed by MAST (Cemri et al., 2025) which identified 14
--- failure modes, many of which are topology-dependent (F1: wrong
--- decomposition granularity, F5: missing verification stage, F11:
--- groupthink in mesh topologies).
---
--- Pipeline (1-2 LLM calls):
---   Step 1: Task analysis — classify complexity, decomposability,
---           verification needs, and adversarial requirements
---   Step 2: Topology recommendation with package mapping
---
--- Usage:
---   local topo_route = require("topo_route")
---   return topo_route.run(ctx)
---
--- ctx.task (required): Task description to route
--- ctx.available_packages (optional): Override default package registry
--- ctx.analysis_tokens: Max tokens for analysis (default: 600)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "topo_route",
    version = "0.1.0",
    description = "Topology-aware meta-router — analyzes task characteristics "
        .. "and recommends optimal agent topology (linear/star/DAG/mesh/debate) "
        .. "with concrete package mappings. Generalizes Topological Sensitivity "
        .. "from 'From Spark to Fire' (Xie et al., AAMAS 2026). Same agents, "
        .. "different topology → up to 40% reliability variation.",
    category = "routing",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task               = T.string:describe("Task description to route (required)"),
                available_packages = T.any:is_optional():describe("Override default package registry (reserved; not currently consumed)"),
                analysis_tokens    = T.number:is_optional():describe("Max tokens for the analysis LLM call (default 600)"),
            }),
            result = T.shape({
                topology          = T.string:describe("Recommended topology name: linear | star | dag | debate | ensemble | escalation"),
                description       = T.string:describe("Short topology description"),
                confidence        = T.number:describe("Parsed CONFIDENCE in [0, 1] (default 0.5 on parse failure)"),
                dimensions        = T.map_of(T.string, T.string)
                    :describe("Task analysis axes; keys are complexity/decomposability/verification_need/adversarial_value/cost_sensitivity, values are LOW|MEDIUM|HIGH"),
                packages          = T.array_of(T.shape({
                    package = T.string:describe("Package name"),
                    role    = T.string:describe("Role slot (orchestration/verification/aggregation/reasoning/routing/governance)"),
                })):describe("Flattened package list covering all roles of the selected topology plus governance addons"),
                governance_addons = T.array_of(T.string):describe("Filtered governance packages from LLM suggestion (subset of {lineage, dissent, anti_cascade})"),
                risks             = T.string:describe("Topology-specific risk summary"),
                mitigations       = T.string:describe("Suggested mitigation packages for those risks"),
                analysis          = T.string:describe("Raw LLM analysis text (kept for downstream consumers)"),
            }),
        },
    },
}

-- ─── Topology Registry ───

local TOPOLOGIES = {
    {
        name = "linear",
        description = "Sequential pipeline — each stage feeds the next",
        best_for = "Well-defined multi-phase tasks with clear stage boundaries",
        risks = "Cascade amplification (errors compound through stages)",
        mitigations = "anti_cascade, lineage",
        packages = {
            orchestration = { "orch_fixpipe", "orch_gatephase" },
            verification = { "lineage", "anti_cascade" },
        },
    },
    {
        name = "star",
        description = "Hub-and-spoke — central coordinator delegates to specialists",
        best_for = "Tasks requiring multiple independent perspectives aggregated by a coordinator",
        risks = "Single point of failure at hub; information loss in aggregation",
        mitigations = "dissent at aggregation point",
        packages = {
            orchestration = { "decompose", "orch_adaptive" },
            aggregation = { "panel", "moa" },
            verification = { "dissent" },
        },
    },
    {
        name = "dag",
        description = "Directed acyclic graph — branching and merging thought paths",
        best_for = "Complex problems requiring exploration of multiple paths with synthesis",
        risks = "Merge conflicts; inconsistent branches",
        mitigations = "lineage for provenance tracking across branches",
        packages = {
            reasoning = { "got", "tot" },
            verification = { "lineage", "cove" },
        },
    },
    {
        name = "debate",
        description = "Adversarial — multiple agents argue opposing positions with arbitration",
        best_for = "Controversial questions, decisions with trade-offs, bias detection",
        risks = "Consensus inertia; debate may not converge",
        mitigations = "dissent; bounded rounds",
        packages = {
            reasoning = { "triad", "panel" },
            verification = { "dissent", "factscore" },
        },
    },
    {
        name = "ensemble",
        description = "Parallel independent runs with selection/voting",
        best_for = "High-stakes tasks where redundancy reduces error rate",
        risks = "Cost scales linearly with N; correlated failures if prompts are similar",
        mitigations = "orch_nver with diverse prompts; rstar for mutual verification",
        packages = {
            orchestration = { "orch_nver", "sc" },
            reasoning = { "rstar", "moa" },
            verification = { "rank", "dissent" },
        },
    },
    {
        name = "escalation",
        description = "Cascade from light to heavy — only escalate if needed",
        best_for = "Variable difficulty tasks; cost optimization",
        risks = "Under-escalation (stopping too early on hard tasks)",
        mitigations = "calibrate for confidence gating",
        packages = {
            orchestration = { "orch_escalate", "cascade" },
            routing = { "router_daao", "calibrate" },
        },
    },
}

-- ─── Prompts ───

local ANALYZE_SYSTEM = [[You are a multi-agent system architect. Analyze the given task and recommend the optimal topology.

Available topologies:
{topology_descriptions}

Analyze the task on these dimensions:
1. COMPLEXITY: LOW | MEDIUM | HIGH (reasoning depth required)
2. DECOMPOSABILITY: LOW | MEDIUM | HIGH (can it be split into independent subtasks?)
3. VERIFICATION_NEED: LOW | MEDIUM | HIGH (how important is correctness validation?)
4. ADVERSARIAL_VALUE: LOW | MEDIUM | HIGH (does it benefit from opposing viewpoints?)
5. COST_SENSITIVITY: LOW | MEDIUM | HIGH (is minimizing LLM calls important?)

Then recommend a topology.

Respond in this exact format:
## Task Analysis
COMPLEXITY: <level>
DECOMPOSABILITY: <level>
VERIFICATION_NEED: <level>
ADVERSARIAL_VALUE: <level>
COST_SENSITIVITY: <level>

## Recommendation
TOPOLOGY: <topology_name>
CONFIDENCE: <0.0 to 1.0>
REASONING: <1-2 sentences explaining why this topology fits>

## Alternative
TOPOLOGY: <second_best_topology_name>
WHEN: <condition under which the alternative would be better>

## Governance Add-ons
<comma-separated list of recommended governance packages: lineage, dissent, anti_cascade, or "none">]]

local ANALYZE_PROMPT = [[Task to route:
{task}

Analyze this task and recommend the optimal agent topology.]]

-- ─── Helpers ───

local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

local function build_topology_descriptions()
    local lines = {}
    for _, t in ipairs(TOPOLOGIES) do
        lines[#lines + 1] = string.format(
            "- **%s**: %s\n  Best for: %s\n  Risks: %s",
            t.name, t.description, t.best_for, t.risks
        )
    end
    return table.concat(lines, "\n\n")
end

local function find_topology(name)
    local lower = name:lower()
    for _, t in ipairs(TOPOLOGIES) do
        if t.name == lower then
            return t
        end
    end
    return nil
end

local function parse_topology(raw, section)
    section = section or "Recommendation"
    local pat = "## " .. section .. "\n(.-)\n## "
    local block = raw:match(pat)
    if not block then
        -- Fallback: section may be the last block (no trailing ## )
        block = raw:match("## " .. section .. "\n(.+)$")
    end
    if block then
        return block:match("TOPOLOGY:%s*(%S+)")
    end
    -- Final fallback: first TOPOLOGY: in entire output
    return raw:match("TOPOLOGY:%s*(%S+)")
end

local function parse_confidence(raw)
    local conf = raw:match("CONFIDENCE:%s*(%d*%.?%d+)")
    if conf then
        return math.max(0, math.min(1, tonumber(conf)))
    end
    return nil
end

local function parse_dimensions(raw)
    local dims = {}
    for _, dim in ipairs({ "COMPLEXITY", "DECOMPOSABILITY", "VERIFICATION_NEED", "ADVERSARIAL_VALUE", "COST_SENSITIVITY" }) do
        local val = raw:match(dim .. ":%s*(%S+)")
        if val then
            dims[dim:lower()] = val:upper()
        end
    end
    return dims
end

local function parse_governance(raw)
    local section = raw:match("## Governance Add%-ons\n(.+)")
    if not section then
        return {}
    end
    local first_line = section:match("^([^\n]+)")
    if not first_line or first_line:lower():match("none") then
        return {}
    end
    local addons = {}
    for addon in first_line:gmatch("[%w_]+") do
        if addon == "lineage" or addon == "dissent" or addon == "anti_cascade" then
            addons[#addons + 1] = addon
        end
    end
    return addons
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local analysis_tokens = ctx.analysis_tokens or 600

    alc.log("info", "topo_route: analyzing task for topology recommendation")

    local topo_descs = build_topology_descriptions()
    local system = expand(ANALYZE_SYSTEM, { topology_descriptions = topo_descs })

    local prompt = expand(ANALYZE_PROMPT, { task = task })

    local raw = alc.llm(prompt, {
        system = system,
        max_tokens = analysis_tokens,
    })

    -- Parse recommendation
    local recommended_name = parse_topology(raw, "Recommendation")
    local confidence = parse_confidence(raw) or 0.5
    local dimensions = parse_dimensions(raw)
    local governance_addons = parse_governance(raw)

    local recommended = find_topology(recommended_name or "linear")
    if not recommended then
        alc.log("warn", string.format(
            "topo_route: unrecognized topology '%s', falling back to linear",
            tostring(recommended_name)
        ))
        recommended = find_topology("linear")
    end

    -- Collect all recommended packages
    local all_packages = {}
    for role, pkgs in pairs(recommended.packages) do
        for _, pkg in ipairs(pkgs) do
            all_packages[#all_packages + 1] = { package = pkg, role = role }
        end
    end
    for _, addon in ipairs(governance_addons) do
        all_packages[#all_packages + 1] = { package = addon, role = "governance" }
    end

    alc.log("info", string.format(
        "topo_route: recommended=%s confidence=%.2f governance=%s",
        recommended.name,
        confidence,
        #governance_addons > 0 and table.concat(governance_addons, ",") or "none"
    ))
    alc.stats.record("topo_route_topology", recommended.name)
    alc.stats.record("topo_route_confidence", confidence)

    ctx.result = {
        topology = recommended.name,
        description = recommended.description,
        confidence = confidence,
        dimensions = dimensions,
        packages = all_packages,
        governance_addons = governance_addons,
        risks = recommended.risks,
        mitigations = recommended.mitigations,
        analysis = raw,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
