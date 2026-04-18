--- router_semantic — Semantic Router with LLM Fallback
--- Keyword/pattern-based routing with LLM fallback for ambiguous cases.
--- Zero LLM calls for clear matches, one call for ambiguous cases.
---
--- Based on Semantic Router pattern (Microsoft Multi-Agent Reference Architecture).
---
--- Usage:
---   local router = require("router_semantic")
---   return router.run(ctx)
---
--- ctx.task      (required): Task description to route
--- ctx.rules     (optional): Routing rules [{name, keywords, description}, ...]
--- ctx.threshold (optional): Minimum keyword score to skip LLM (default: 0.3)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "router_semantic",
    version = "0.1.0",
    description = "Keyword/pattern-based routing with LLM fallback. "
        .. "Zero LLM calls for clear matches, one call for ambiguous cases. "
        .. "Based on Semantic Router pattern (Microsoft Multi-Agent Reference Architecture).",
    category = "routing",
}

local rule_shape = T.shape({
    name        = T.string:describe("Rule identifier"),
    keywords    = T.array_of(T.string):describe("Keyword list used for substring matching"),
    description = T.string:describe("Human-readable rule description (used in LLM fallback prompt)"),
})

local score_shape = T.shape({
    name             = T.string:describe("Rule name"),
    score            = T.number:describe("Normalized score (matches / total keywords, 0-1)"),
    raw_matches      = T.number:describe("Raw keyword hit count"),
    matched_keywords = T.array_of(T.string):describe("Which keywords matched the task"),
    description      = T.string,
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task      = T.string:describe("Task description (required)"),
                rules     = T.array_of(rule_shape):is_optional():describe("Routing rules; defaults to DEFAULT_RULES"),
                threshold = T.number:is_optional():describe("Minimum keyword score to skip LLM (default 0.3)"),
            }),
            result = T.shape({
                selected     = T.string:describe("Best-match rule name"),
                confidence   = T.number:describe("Score in [0, 1] — keyword score or LLM-reported"),
                reasoning    = T.string:describe("Keyword match list, LLM reasoning, or failure note"),
                method       = T.one_of({ "keyword", "llm_fallback", "keyword_forced" })
                    :describe("Which dispatch path produced the verdict"),
                alternatives = T.array_of(score_shape):describe("All rules scored by keyword, sorted by score desc"),
            }),
        },
    },
}

-- Default routing rules (coding task oriented)
local DEFAULT_RULES = {
    {
        name = "bugfix",
        keywords = { "fix", "bug", "error", "crash", "broken", "regression", "fail" },
        description = "Bug fix tasks",
    },
    {
        name = "feature",
        keywords = { "add", "implement", "create", "new", "introduce", "support" },
        description = "New feature implementation",
    },
    {
        name = "refactor",
        keywords = { "refactor", "rename", "reorganize", "clean", "simplify", "extract" },
        description = "Code refactoring",
    },
    {
        name = "test",
        keywords = { "test", "spec", "coverage", "assert", "verify" },
        description = "Testing tasks",
    },
    {
        name = "docs",
        keywords = { "document", "readme", "comment", "explain", "describe" },
        description = "Documentation tasks",
    },
}

local FALLBACK_SYSTEM = [[You are a task classifier for software engineering.
Given a task and a list of categories, select the best matching category.
Respond with ONLY a JSON object: {"selected": "category_name", "confidence": 0.0-1.0, "reasoning": "one sentence"}]]

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

--- Score rules against task using keyword matching (deterministic, no LLM).
local function score_rules(task, rules)
    local task_lower = task:lower()
    local scores = {}

    for _, rule in ipairs(rules) do
        local score = 0
        local matched = {}
        for _, kw in ipairs(rule.keywords) do
            if task_lower:find(kw, 1, true) then
                score = score + 1
                matched[#matched + 1] = kw
            end
        end
        local normalized = #rule.keywords > 0 and (score / #rule.keywords) or 0
        scores[#scores + 1] = {
            name = rule.name,
            score = normalized,
            raw_matches = score,
            matched_keywords = matched,
            description = rule.description,
        }
    end

    table.sort(scores, function(a, b) return a.score > b.score end)
    return scores
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rules = ctx.rules or DEFAULT_RULES
    local threshold = ctx.threshold or 0.3

    -- Phase 1: Keyword scoring (0 LLM calls)
    local scores = score_rules(task, rules)
    local top = scores[1]

    if top and top.score >= threshold then
        ctx.result = {
            selected = top.name,
            confidence = top.score,
            reasoning = "Keyword match: " .. table.concat(top.matched_keywords, ", "),
            method = "keyword",
            alternatives = scores,
        }
        return ctx
    end

    -- Phase 2: LLM Fallback (1 call)
    alc.log("info", string.format(
        "router_semantic: keyword confidence %.2f < threshold %.2f, escalating to LLM",
        top and top.score or 0, threshold
    ))

    local rule_descriptions = {}
    for _, rule in ipairs(rules) do
        rule_descriptions[#rule_descriptions + 1] =
            string.format("- %s: %s", rule.name, rule.description)
    end

    local raw = alc.llm(
        string.format(
            "Task: %s\n\nCategories:\n%s",
            task,
            table.concat(rule_descriptions, "\n")
        ),
        { system = FALLBACK_SYSTEM, max_tokens = 100 }
    )

    local parsed = parse_json(raw)
    if parsed and parsed.selected then
        ctx.result = {
            selected = parsed.selected,
            confidence = parsed.confidence or 0.5,
            reasoning = parsed.reasoning or "LLM classification",
            method = "llm_fallback",
            alternatives = scores,
        }
    else
        -- Complete fallback: use keyword top
        alc.log("warn", "router_semantic: LLM fallback parse failed, using keyword top")
        ctx.result = {
            selected = top and top.name or rules[1].name,
            confidence = top and top.score or 0,
            reasoning = "LLM fallback failed, keyword top used",
            method = "keyword_forced",
            alternatives = scores,
        }
    end

    return ctx
end

M.run = S.instrument(M, "run")

return M
