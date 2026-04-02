--- sketch — Sketch-of-Thought: cognitive-inspired efficient reasoning
---
--- Selects one of three cognitive paradigms based on task characteristics,
--- then generates compressed reasoning using that paradigm's notation.
--- Reduces reasoning tokens by 60-84% while maintaining or improving accuracy.
---
--- Three paradigms (from cognitive science):
---   Conceptual Chaining  — key concepts linked with arrows (episodic memory)
---   Chunked Symbolism    — variables + equations (working memory chunking)
---   Expert Lexicons      — domain notation + abbreviations (expert schemas)
---
--- Routing: keyword heuristic first (0 LLM calls), LLM fallback if ambiguous.
---
--- Based on: Aytes, Baek, Hwang, "Sketch-of-Thought: Efficient LLM Reasoning
--- with Adaptive Cognitive-Inspired Sketching" (EMNLP 2025, arXiv:2503.05179)
---
--- Pipeline (1-2 LLM calls):
---   Step 1: Route    — select paradigm (keyword heuristic or LLM)
---   Step 2: Sketch   — generate compressed reasoning + answer
---
--- Usage:
---   local sketch = require("sketch")
---   return sketch.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.paradigm: Force paradigm (default: nil → auto-route)
--- ctx.max_tokens: Max tokens for reasoning (default: 200)
--- ctx.routing_threshold: Keyword confidence threshold for LLM fallback (default: 0.4)

local M = {}

---@type AlcMeta
M.meta = {
    name = "sketch",
    version = "0.1.0",
    description = "Sketch-of-Thought — cognitive-inspired efficient reasoning. "
        .. "Routes to Conceptual Chaining, Chunked Symbolism, or Expert Lexicons "
        .. "based on task type. 60-84% token reduction vs standard CoT.",
    category = "reasoning",
}

-- ─── Paradigm definitions ───

local PARADIGMS = {
    conceptual_chaining = {
        system = "You are a reasoning expert specializing in structured concept linking. "
            .. "Your task is to solve problems using minimal, structured reasoning.\n\n"
            .. "RULES:\n"
            .. "1. Extract key concepts and link them with → arrows\n"
            .. "2. Use minimal words — keywords and connections only\n"
            .. "3. Link steps sequentially: concept_A → concept_B → conclusion\n"
            .. "4. NO full sentences in reasoning. NO restating the question\n"
            .. "5. Output format:\n"
            .. "<sketch>\n[keyword chains with → arrows]\n</sketch>\n"
            .. "Answer: [concise final answer]",
        keywords = {
            "why", "how", "because", "cause", "effect", "lead", "result",
            "connection", "relate", "explain", "reason", "therefore",
            "implication", "consequence", "origin", "history",
        },
    },
    chunked_symbolism = {
        system = "You are a reasoning expert specializing in symbolic computation. "
            .. "Your task is to solve problems using variables and equations.\n\n"
            .. "RULES:\n"
            .. "1. Define variables FIRST, then compute\n"
            .. "2. One calculation per line with units\n"
            .. "3. Use explicit equations: a = 2.5 m/s², t = 10 s → v = a×t = 25 m/s\n"
            .. "4. NO prose. NO restating the question. NO filler words\n"
            .. "5. Output format:\n"
            .. "<sketch>\n[variables and equations]\n</sketch>\n"
            .. "Answer: [concise final answer with units]",
        keywords = {
            "calculate", "compute", "solve", "equation", "formula", "sum",
            "total", "average", "percent", "ratio", "how many", "how much",
            "price", "cost", "distance", "speed", "time", "rate", "area",
            "volume", "probability",
        },
        -- Pattern-based: presence of numbers + operators
        patterns = { "%d+%s*[%+%-%*/%%]", "%d+%.%d+", "%$%d", "%d+%%", },
    },
    expert_lexicons = {
        system = "You are a domain expert who communicates in professional shorthand. "
            .. "Your task is to solve problems using domain-specific notation.\n\n"
            .. "RULES:\n"
            .. "1. Replace common terms with standard notation: ∑, ∴, ∝, Δ, →\n"
            .. "2. Use domain abbreviations (e.g., CHF, EBITDA, pH, O(n))\n"
            .. "3. Structured notation only — NO full sentences\n"
            .. "4. Follow industry-standard conventions for the domain\n"
            .. "5. Output format:\n"
            .. "<sketch>\n[domain notation and abbreviations]\n</sketch>\n"
            .. "Answer: [concise final answer]",
        keywords = {
            "diagnose", "patient", "symptom", "treatment", "clinical",
            "enzyme", "molecule", "reaction", "compound", "pH",
            "circuit", "voltage", "resistance", "frequency",
            "algorithm", "complexity", "protocol", "specification",
            "EBITDA", "revenue", "margin", "portfolio", "valuation",
            "plaintiff", "statute", "jurisdiction", "precedent",
        },
    },
}

--- Keyword-based routing. Returns (paradigm_name, confidence).
local function keyword_route(task)
    local lower = task:lower()
    local scores = {}

    for name, paradigm in pairs(PARADIGMS) do
        local score = 0

        -- Keyword matches
        for _, kw in ipairs(paradigm.keywords) do
            if lower:match(kw) then
                score = score + 1
            end
        end

        -- Pattern matches (chunked_symbolism has numeric patterns)
        if paradigm.patterns then
            for _, pat in ipairs(paradigm.patterns) do
                if task:match(pat) then
                    score = score + 2
                end
            end
        end

        scores[name] = score
    end

    -- Find best and second-best
    local best_name, best_score = nil, -1
    local second_score = -1
    for name, score in pairs(scores) do
        if score > best_score then
            second_score = best_score
            best_name = name
            best_score = score
        elseif score > second_score then
            second_score = score
        end
    end

    -- Confidence: normalized gap between best and second
    local total = best_score + second_score + 1
    local confidence = (best_score - second_score) / total

    -- Default if no keywords matched
    if best_score == 0 then
        return "conceptual_chaining", 0.0
    end

    return best_name, confidence
end

--- LLM-based routing fallback. Returns (paradigm_name, routing_info).
local function llm_route(task)
    local response = alc.llm(
        string.format(
            "Classify this problem into exactly ONE reasoning paradigm:\n\n"
                .. "1. conceptual_chaining — for common sense, cause-effect, "
                .. "multi-hop reasoning, explanations\n"
                .. "2. chunked_symbolism — for math, calculation, numeric reasoning, "
                .. "formulas, quantitative problems\n"
                .. "3. expert_lexicons — for domain-specific technical problems "
                .. "(medical, legal, financial, engineering, CS)\n\n"
                .. "Problem: %s\n\n"
                .. "Reply with ONLY the paradigm name (one of: conceptual_chaining, "
                .. "chunked_symbolism, expert_lexicons).",
            task
        ),
        {
            system = "You classify problems into reasoning paradigms. "
                .. "Reply with exactly one paradigm name, nothing else.",
            max_tokens = 20,
        }
    )

    local lower = response:lower()
    if lower:match("chunked") or lower:match("symbol") then
        return "chunked_symbolism", { method = "llm", confidence = 0.8 }
    elseif lower:match("expert") or lower:match("lexicon") then
        return "expert_lexicons", { method = "llm", confidence = 0.8 }
    else
        return "conceptual_chaining", { method = "llm", confidence = 0.8 }
    end
end

--- Execute reasoning with the selected paradigm.
local function execute_paradigm(task, paradigm_name, max_tokens)
    local paradigm = PARADIGMS[paradigm_name]

    local response = alc.llm(
        string.format("Problem: %s", task),
        {
            system = paradigm.system,
            max_tokens = max_tokens,
        }
    )

    -- Parse <sketch>...</sketch> and Answer:
    local sketch = response:match("<sketch>(.-)</sketch>")
    local answer = response:match("[Aa]nswer:%s*(.-)$")
        or response:match("</sketch>%s*(.-)$")

    -- Clean up
    if sketch then
        sketch = sketch:match("^%s*(.-)%s*$")
    end
    if answer then
        answer = answer:match("^%s*(.-)%s*$")
    end

    return sketch or response, answer or response
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_tokens = ctx.max_tokens or 200
    local threshold = ctx.routing_threshold or 0.4

    -- ─── Step 1: Route — select paradigm ───
    local paradigm_name, routing_info

    if ctx.paradigm then
        paradigm_name = ctx.paradigm
        routing_info = { method = "manual", confidence = 1.0 }
        alc.log("info", string.format(
            "sketch: using manually specified paradigm: %s", paradigm_name
        ))
    else
        local kw_name, kw_confidence = keyword_route(task)
        alc.log("info", string.format(
            "sketch: keyword routing → %s (confidence: %.2f, threshold: %.2f)",
            kw_name, kw_confidence, threshold
        ))

        if kw_confidence >= threshold then
            paradigm_name = kw_name
            routing_info = { method = "keyword", confidence = kw_confidence }
        else
            alc.log("info", "sketch: keyword confidence below threshold, using LLM routing")
            paradigm_name, routing_info = llm_route(task)
            alc.log("info", string.format(
                "sketch: LLM routing → %s", paradigm_name
            ))
        end
    end

    -- Validate paradigm name
    if not PARADIGMS[paradigm_name] then
        alc.log("warn", string.format(
            "sketch: unknown paradigm '%s', falling back to conceptual_chaining",
            paradigm_name
        ))
        paradigm_name = "conceptual_chaining"
    end

    -- ─── Step 2: Sketch — generate compressed reasoning ───
    alc.log("info", string.format(
        "sketch: executing %s paradigm", paradigm_name
    ))

    local reasoning, answer = execute_paradigm(task, paradigm_name, max_tokens)

    alc.log("info", string.format(
        "sketch: complete — reasoning %d chars, answer %d chars",
        #(reasoning or ""), #(answer or "")
    ))

    ctx.result = {
        answer = answer,
        reasoning = reasoning,
        paradigm = paradigm_name,
        routing = routing_info,
    }
    return ctx
end

return M
