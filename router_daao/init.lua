--- router_daao — Difficulty-Aware Agent Orchestration Router
--- Classifies task difficulty with a single LLM call, then maps to
--- optimal strategy/depth/parameters via deterministic lookup.
---
--- Based on DAAO (arxiv 2509.11079): lightweight difficulty estimation
--- followed by adaptive resource allocation.
---
--- Usage:
---   local router = require("router_daao")
---   return router.run(ctx)
---
--- ctx.task       (required): Task description to route
--- ctx.candidates (optional): List of candidate strategy names or {name=...} tables
--- ctx.profiles   (optional): Custom difficulty→profile mapping table
---   Each profile may include confidence (0-1) and fallback_confidence (0-1)

local M = {}

M.meta = {
    name = "router_daao",
    version = "0.1.0",
    description = "Difficulty-aware task routing based on DAAO (arxiv 2509.11079). "
        .. "Classifies task difficulty with a single LLM call, then maps to "
        .. "optimal strategy/depth/parameters via deterministic lookup.",
    category = "routing",
}

-- Default difficulty→strategy profile mapping.
-- confidence: baseline confidence for this difficulty level.
-- fallback_confidence: used when LLM classification parse fails.
-- Both are injectable via ctx.profiles.
local DEFAULT_PROFILES = {
    simple = {
        depth = 1,
        max_retries = 1,
        recommended_strategies = { "orch_fixpipe" },
        skip_phases = { "review" },
        context_mode = "summary",
        confidence = 0.85,
        fallback_confidence = 0.5,
    },
    medium = {
        depth = 2,
        max_retries = 3,
        recommended_strategies = { "orch_gatephase" },
        skip_phases = {},
        context_mode = "summary",
        confidence = 0.7,
        fallback_confidence = 0.5,
    },
    complex = {
        depth = 3,
        max_retries = 5,
        recommended_strategies = { "orch_gatephase", "orch_nver" },
        skip_phases = {},
        context_mode = "full",
        confidence = 0.85,
        fallback_confidence = 0.5,
    },
}

local CLASSIFICATION_SYSTEM = [[You are a task difficulty classifier for software engineering tasks.
Classify the given task into exactly one of: simple, medium, complex.

Criteria:
- simple: Single-file change, clear fix, no design decision needed. Examples: typo fix, rename variable, add a log line.
- medium: Multi-file change, requires understanding of existing architecture but no major design decision. Examples: add a new API endpoint, fix a bug with multiple touch points, refactor a module.
- complex: Requires design decisions, new architecture, cross-cutting concerns, or risk of regression. Examples: add session management, redesign error handling, implement new subsystem.

Respond with ONLY a JSON object: {"difficulty": "simple|medium|complex", "reasoning": "one sentence"}]]

--- Extract JSON object from a potentially noisy LLM response.
--- Tries alc.json_decode first; on failure, extracts the first {...} block.
local function parse_classification(raw)
    local ok, decoded = pcall(alc.json_decode, raw)
    if ok and type(decoded) == "table" then
        return decoded
    end

    -- Fallback: extract first JSON object from response
    local json_str = raw:match("%b{}")
    if json_str then
        local ok2, decoded2 = pcall(alc.json_decode, json_str)
        if ok2 and type(decoded2) == "table" then
            return decoded2
        end
    end

    return nil
end

--- Find the best candidate matching profile recommendations.
--- Returns the selected strategy name.
local function select_from_candidates(candidates, profile)
    -- Try to match candidates against profile's recommended strategies
    for _, rec in ipairs(profile.recommended_strategies) do
        for _, cand in ipairs(candidates) do
            local cand_name = type(cand) == "table" and cand.name or cand
            if cand_name == rec then
                return cand_name
            end
        end
    end

    -- No match: use first candidate
    local first = candidates[1]
    return type(first) == "table" and first.name or first
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local profiles = ctx.profiles or DEFAULT_PROFILES
    local candidates = ctx.candidates

    -- Phase 1: LLM classification (single call)
    local raw = alc.llm(
        "Classify this task:\n\n" .. task,
        { system = CLASSIFICATION_SYSTEM, max_tokens = 100 }
    )

    -- Phase 2: Parse classification result
    local classification = parse_classification(raw)
    local difficulty = "medium" -- fallback
    local reasoning = ""

    if classification and classification.difficulty then
        local d = classification.difficulty:lower()
        if profiles[d] then
            difficulty = d
        else
            alc.log("warn", "router_daao: unknown difficulty '"
                .. d .. "', defaulting to medium")
            reasoning = "Unknown difficulty '" .. d .. "', using default"
        end
        if classification.reasoning then
            reasoning = classification.reasoning
        end
    else
        alc.log("warn", "router_daao: classification parse failed, defaulting to medium")
        reasoning = "Classification parse failed, using default"
    end

    -- Phase 3: Deterministic lookup
    local profile = profiles[difficulty]
    local selected = profile.recommended_strategies[1]

    -- If candidates are provided, match against profile recommendations
    if candidates and #candidates > 0 then
        selected = select_from_candidates(candidates, profile)
    end

    -- Confidence from profile (injectable via ctx.profiles)
    local parse_failed = not classification or not classification.difficulty
    local confidence = parse_failed
        and (profile.fallback_confidence or 0.5)
        or  (profile.confidence or 0.7)

    ctx.result = {
        selected = selected,
        difficulty = difficulty,
        confidence = confidence,
        reasoning = reasoning,
        profile = profile,
        alternatives = profile.recommended_strategies,
    }

    return ctx
end

return M
