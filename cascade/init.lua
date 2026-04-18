--- cascade — Multi-level difficulty routing with confidence gating
---
--- Routes problems through escalating complexity levels. Starts with
--- the simplest (cheapest) approach; if confidence is below threshold,
--- escalates to a more sophisticated strategy. Minimizes compute for
--- easy problems while ensuring quality for hard ones.
---
--- Based on: "FrugalGPT: How to Use Large Language Models While Reducing
---            Cost and Improving Performance" (Chen et al., arXiv 2305.05176, 2023)
---            + "Routing to the Expert: Efficient Reward-guided Ensemble of
---            Large Language Models" (Lu et al., arXiv 2311.08692, 2023)
---
--- Pipeline:
---   Level 1 (fast):   Direct zero-shot answer + self-assessed confidence
---   Level 2 (medium): Chain-of-thought with verification
---   Level 3 (deep):   Multi-perspective ensemble with ranking
---
--- Usage:
---   local cascade = require("cascade")
---   return cascade.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.threshold: Confidence threshold to stop (default: 0.8)
--- ctx.max_level: Maximum cascade level (default: 3)
--- ctx.gen_tokens: Max tokens per generation (default: 400)
--- ctx.verify_tokens: Max tokens for verification (default: 300)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "cascade",
    version = "0.1.0",
    description = "Multi-level difficulty routing — escalate from fast to deep only when confidence is low",
    category = "routing",
}

local history_entry_shape = T.shape({
    level      = T.number:describe("Level index (1=fast zero-shot, 2=cot+verify, 3=ensemble synthesis)"),
    name       = T.string:describe("Level name: 'fast' | 'cot_verify' | 'ensemble'"),
    answer     = T.string:describe("Answer extracted for this level (before the confidence marker)"),
    confidence = T.number:describe("Parsed confidence in [0, 1]; 0.5 when unparseable"),
    detail     = T.any:describe(
        "Level-polymorphic trace: Level 1 returns the raw LLM response as a string; "
        .. "Level 2 returns {cot = string, verification = string}; "
        .. "Level 3 returns {perspectives = array<string>, candidates = array<string>, synthesis = string}. "
        .. "Declared as T.any because the detail leaf crosses string/table kinds by design; "
        .. "follows the codebase convention used in condorcet/shapley/scoring_rule for "
        .. "legitimately heterogeneous leaves inside an otherwise shaped container."),
})

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task          = T.string:describe("Problem to solve (required)"),
                threshold     = T.number:is_optional():describe("Confidence threshold at which the cascade stops early (default 0.8)"),
                max_level     = T.number:is_optional():describe("Maximum cascade level to attempt (default 3)"),
                gen_tokens    = T.number:is_optional():describe("Max tokens per generation call (default 400)"),
                verify_tokens = T.number:is_optional():describe("Max tokens per verification call (default 300)"),
            }),
            result = T.shape({
                answer     = T.string:describe("Final answer from the highest level actually run"),
                confidence = T.number:describe("Final confidence in [0, 1]"),
                level_used = T.number:describe("Level at which the cascade stopped"),
                max_level  = T.number:describe("Echo of input.max_level"),
                threshold  = T.number:describe("Echo of input.threshold"),
                escalated  = T.boolean:describe("True iff level_used > 1"),
                history    = T.array_of(history_entry_shape):describe("Per-level execution trace in run order"),
            }),
        },
    },
}

--- Parse confidence from self-assessment.
--- Looks for "CONFIDENCE: 0.X" or percentage patterns.
local function parse_confidence(text)
    local lower = text:lower()

    -- Direct pattern: confidence: 0.85
    local conf = tonumber(lower:match("confidence:%s*(%d*%.?%d+)"))
    if conf then
        if conf > 1 then conf = conf / 100 end  -- Handle percentage
        return math.max(0, math.min(1, conf))
    end

    -- Percentage pattern: 85%
    local pct = tonumber(text:match("(%d+)%%"))
    if pct then
        return math.max(0, math.min(1, pct / 100))
    end

    -- Fraction pattern: 8/10, 9/10
    local num, den = text:match("(%d+)/(%d+)")
    if num and den and tonumber(den) > 0 then
        return math.max(0, math.min(1, tonumber(num) / tonumber(den)))
    end

    return 0.5  -- Default: uncertain
end

--- Extract answer portion (before confidence line).
local function extract_answer(text)
    -- Remove the confidence line and anything after
    local lower = text:lower()
    local pos = lower:find("confidence:")
    local answer = pos and text:sub(1, pos - 1) or nil
    if answer and #answer > 10 then
        return answer:match("^%s*(.-)%s*$")
    end
    return text
end

--- Level 1: Fast zero-shot with confidence self-assessment
local function level_fast(task, gen_tokens)
    local response = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Provide your answer, then on a new line state:\n"
                .. "CONFIDENCE: [0.0-1.0]\n"
                .. "where 1.0 = absolutely certain, 0.0 = pure guess.",
            task
        ),
        {
            system = "You are an expert. Answer concisely and accurately. "
                .. "Be honest about your confidence level.",
            max_tokens = gen_tokens,
        }
    )

    local confidence = parse_confidence(response)
    local answer = extract_answer(response)

    return answer, confidence, response
end

--- Level 2: Chain-of-thought with verification
local function level_cot_verify(task, gen_tokens, verify_tokens)
    -- Generate with CoT
    local cot_response = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Think step by step to find the answer. "
                .. "Show your reasoning clearly.",
            task
        ),
        {
            system = "You are an expert problem solver. Break down the problem "
                .. "and reason through it step by step.",
            max_tokens = gen_tokens,
        }
    )

    -- Verify the CoT answer
    local verification = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Proposed answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Verify this answer. Check each step and conclusion. "
                .. "Then provide:\n"
                .. "1. Your corrected answer (or confirm the original)\n"
                .. "2. CONFIDENCE: [0.0-1.0]",
            task, cot_response
        ),
        {
            system = "You are a rigorous verifier. Check every step for errors. "
                .. "Be honest about confidence.",
            max_tokens = verify_tokens,
        }
    )

    local confidence = parse_confidence(verification)
    local answer = extract_answer(verification)

    return answer, confidence, {
        cot = cot_response,
        verification = verification,
    }
end

--- Level 3: Multi-perspective ensemble with selection
local function level_ensemble(task, gen_tokens, verify_tokens)
    local perspectives = {
        "analytical expert who focuses on logical rigor",
        "domain specialist who draws on deep knowledge",
        "critical thinker who considers edge cases and counterexamples",
    }

    -- Generate from multiple perspectives
    local responses = alc.map(perspectives, function(perspective)
        return alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Provide a thorough, well-reasoned answer.",
                task
            ),
            {
                system = string.format(
                    "You are an %s. Give your best answer "
                        .. "from your specialized viewpoint.",
                    perspective
                ),
                max_tokens = gen_tokens,
            }
        )
    end)

    -- Synthesize and select best
    local candidates_text = {}
    for i, r in ipairs(responses) do
        candidates_text[#candidates_text + 1] = string.format(
            "--- Candidate %d ---\n%s", i, r
        )
    end

    local synthesis = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Three experts provided different answers:\n\n%s\n\n"
                .. "Synthesize the best answer by:\n"
                .. "1. Identifying where experts agree (high confidence)\n"
                .. "2. Resolving disagreements by analyzing reasoning quality\n"
                .. "3. Producing a final, comprehensive answer\n\n"
                .. "End with: CONFIDENCE: [0.0-1.0]",
            task, table.concat(candidates_text, "\n\n")
        ),
        {
            system = "You are a meta-analyst synthesizing multiple expert opinions. "
                .. "Weight by reasoning quality, not just majority vote.",
            max_tokens = gen_tokens,
        }
    )

    local confidence = parse_confidence(synthesis)
    local answer = extract_answer(synthesis)

    return answer, confidence, {
        perspectives = perspectives,
        candidates = responses,
        synthesis = synthesis,
    }
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local threshold = ctx.threshold or 0.8
    local max_level = ctx.max_level or 3
    local gen_tokens = ctx.gen_tokens or 400
    local verify_tokens = ctx.verify_tokens or 300

    local history = {}
    local final_answer, final_confidence, final_level

    -- ─── Level 1: Fast ───
    if max_level >= 1 then
        alc.log("info", "cascade: Level 1 — fast zero-shot")
        local answer, confidence, detail = level_fast(task, gen_tokens)
        history[#history + 1] = {
            level = 1,
            name = "fast",
            answer = answer,
            confidence = confidence,
            detail = detail,
        }
        final_answer = answer
        final_confidence = confidence
        final_level = 1

        alc.log("info", string.format(
            "cascade: Level 1 confidence=%.2f (threshold=%.2f)",
            confidence, threshold
        ))

        if confidence >= threshold then
            alc.log("info", "cascade: Level 1 sufficient, stopping")
            goto done
        end
    end

    -- ─── Level 2: CoT + Verify ───
    if max_level >= 2 then
        alc.log("info", "cascade: Level 2 — CoT with verification")
        local answer, confidence, detail = level_cot_verify(
            task, gen_tokens, verify_tokens
        )
        history[#history + 1] = {
            level = 2,
            name = "cot_verify",
            answer = answer,
            confidence = confidence,
            detail = detail,
        }
        final_answer = answer
        final_confidence = confidence
        final_level = 2

        alc.log("info", string.format(
            "cascade: Level 2 confidence=%.2f (threshold=%.2f)",
            confidence, threshold
        ))

        if confidence >= threshold then
            alc.log("info", "cascade: Level 2 sufficient, stopping")
            goto done
        end
    end

    -- ─── Level 3: Ensemble ───
    if max_level >= 3 then
        alc.log("info", "cascade: Level 3 — multi-perspective ensemble")
        local answer, confidence, detail = level_ensemble(
            task, gen_tokens, verify_tokens
        )
        history[#history + 1] = {
            level = 3,
            name = "ensemble",
            answer = answer,
            confidence = confidence,
            detail = detail,
        }
        final_answer = answer
        final_confidence = confidence
        final_level = 3

        alc.log("info", string.format(
            "cascade: Level 3 confidence=%.2f", confidence
        ))
    end

    ::done::

    alc.log("info", string.format(
        "cascade: complete — stopped at level %d/%d (confidence=%.2f)",
        final_level, max_level, final_confidence
    ))

    ctx.result = {
        answer = final_answer,
        confidence = final_confidence,
        level_used = final_level,
        max_level = max_level,
        threshold = threshold,
        escalated = final_level > 1,
        history = history,
    }
    return ctx
end

M.run = S.instrument(M, "run")

return M
