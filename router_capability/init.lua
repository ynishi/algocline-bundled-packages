--- router_capability — Capability-based Registry Router
--- Extracts task requirements via LLM, then scores against agent capabilities
--- using Jaccard similarity. Based on Dynamic Agent Registry pattern.
---
--- Usage:
---   local router = require("router_capability")
---   return router.run(ctx)
---
--- ctx.task        (required): Task description
--- ctx.registry    (optional): Agent registry [{name, capabilities, description, cost}, ...]
--- ctx.max_results (optional): Number of top matches to return (default: 3)

local M = {}

M.meta = {
    name = "router_capability",
    version = "0.1.0",
    description = "Capability-based routing using agent registry metadata matching. "
        .. "Extracts task requirements via LLM, then scores against agent capabilities "
        .. "using Jaccard similarity. Based on Dynamic Agent Registry pattern.",
    category = "routing",
}

-- Default agent registry (coding pipeline oriented)
local DEFAULT_REGISTRY = {
    {
        name = "planner",
        capabilities = { "decomposition", "analysis", "architecture", "planning" },
        description = "Breaks down tasks into subtasks and designs solutions",
        cost = 1,
    },
    {
        name = "implementer",
        capabilities = { "coding", "implementation", "editing", "refactoring" },
        description = "Writes and modifies code",
        cost = 2,
    },
    {
        name = "reviewer",
        capabilities = { "review", "validation", "quality", "security", "testing" },
        description = "Reviews code for correctness and quality",
        cost = 1,
    },
    {
        name = "debugger",
        capabilities = { "debugging", "error_analysis", "tracing", "profiling" },
        description = "Diagnoses and fixes runtime issues",
        cost = 2,
    },
    {
        name = "tester",
        capabilities = { "testing", "test_generation", "coverage", "verification" },
        description = "Writes and runs tests",
        cost = 1,
    },
}

local EXTRACT_SYSTEM = [[You are a task requirements extractor for software engineering.
Given a task description, extract the required capabilities as tags.
Respond with ONLY a JSON object: {"requirements": ["tag1", "tag2", ...], "reasoning": "one sentence"}

Available capability tags: decomposition, analysis, architecture, planning, coding, implementation,
editing, refactoring, review, validation, quality, security, testing, debugging, error_analysis,
tracing, profiling, test_generation, coverage, verification]]

--- Parse JSON from a potentially noisy LLM response.
local function parse_json(raw)
    local ok, decoded = pcall(alc.json_decode, raw)
    if ok and type(decoded) == "table" then
        return decoded
    end
    local json_str = raw:match("%b{}")
    if json_str then
        local ok2, decoded2 = pcall(alc.json_decode, json_str)
        if ok2 and type(decoded2) == "table" then
            return decoded2
        end
    end
    return nil
end

--- Jaccard similarity between two tag lists (deterministic scoring).
local function jaccard(set_a, set_b)
    if #set_a == 0 and #set_b == 0 then return 0 end
    local a_map, b_map = {}, {}
    for _, v in ipairs(set_a) do a_map[v:lower()] = true end
    for _, v in ipairs(set_b) do b_map[v:lower()] = true end

    local intersection, union = 0, 0
    local seen = {}
    for k in pairs(a_map) do
        seen[k] = true
        union = union + 1
        if b_map[k] then intersection = intersection + 1 end
    end
    for k in pairs(b_map) do
        if not seen[k] then union = union + 1 end
    end
    return union > 0 and (intersection / union) or 0
end

-- Expose for testing
M._jaccard = jaccard

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local registry = ctx.registry or DEFAULT_REGISTRY
    local max_results = ctx.max_results or 3

    -- Phase 1: Extract requirements via LLM (1 call)
    local raw = alc.llm(
        "Extract requirements for:\n\n" .. task,
        { system = EXTRACT_SYSTEM, max_tokens = 150 }
    )

    local parsed = parse_json(raw)
    local requirements = {}
    local reasoning = ""

    if parsed and parsed.requirements and type(parsed.requirements) == "table" then
        requirements = parsed.requirements
        reasoning = parsed.reasoning or ""
    else
        alc.log("warn", "router_capability: requirements extraction failed, using empty set")
        reasoning = "Extraction failed"
    end

    -- Phase 2: Deterministic scoring
    local scored = {}
    for _, agent in ipairs(registry) do
        local score = jaccard(requirements, agent.capabilities)
        scored[#scored + 1] = {
            name = agent.name,
            score = score,
            capabilities = agent.capabilities,
            description = agent.description,
            cost = agent.cost,
        }
    end

    table.sort(scored, function(a, b)
        if a.score == b.score then return a.cost < b.cost end
        return a.score > b.score
    end)

    -- Return top N
    local top_n = {}
    for i = 1, math.min(max_results, #scored) do
        top_n[i] = scored[i]
    end

    local selected = scored[1]

    ctx.result = {
        selected = selected and selected.name or "unknown",
        confidence = selected and selected.score or 0,
        reasoning = reasoning,
        requirements = requirements,
        method = "jaccard",
        alternatives = top_n,
    }

    return ctx
end

return M
