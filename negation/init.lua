--- negation — Adversarial self-test via destruction conditions
---
--- Given an answer, generates "destruction conditions": specific scenarios
--- or facts that, if true, would invalidate the answer. Then attempts to
--- verify whether any destruction condition actually holds. Surviving
--- answers are strengthened; refuted answers are revised.
---
--- Based on: "Large Language Models Cannot Self-Correct Reasoning Yet"
---            (Huang et al., arXiv 2310.01798, 2023) — external feedback
---            is required for effective self-correction. Negation provides
---            structured external-style feedback via adversarial probing.
---            + Red-teaming / adversarial testing methodology
---
--- Pipeline:
---   Step 1: generate   — produce initial answer
---   Step 2: negate     — generate destruction conditions
---   Step 3: verify     — check if any condition holds
---   Step 4: revise     — if conditions hold, revise the answer
---
--- Usage:
---   local negation = require("negation")
---   return negation.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.answer: Pre-supplied answer to test (default: nil → auto-generate)
--- ctx.max_conditions: Max destruction conditions to generate (default: 5)
--- ctx.gen_tokens: Max tokens for generation (default: 600)
--- ctx.verify_tokens: Max tokens per condition verification (default: 200)
--- ctx.revise_tokens: Max tokens for revision (default: 600)

local M = {}

M.meta = {
    name = "negation",
    version = "0.1.0",
    description = "Adversarial self-test — generate destruction conditions and verify answer survival",
    category = "validation",
}

--- Parse numbered conditions from LLM output.
local function parse_conditions(raw)
    local conditions = {}
    for line in raw:gmatch("[^\n]+") do
        local _, cond = line:match("^%s*(%d+)[%.%)%s]+(.+)")
        if cond then
            cond = cond:match("^%s*(.-)%s*$")
            if #cond > 10 then
                conditions[#conditions + 1] = cond
            end
        end
    end
    return conditions
end

--- Parse verification verdict: HOLDS (condition is true → answer is wrong)
--- or REFUTED (condition is false → answer survives).
local function parse_verdict(raw)
    local upper = raw:upper()
    local verdict_str = upper:match("VERDICT:%s*(%a+)")
    if verdict_str then
        if verdict_str:match("HOLD") or verdict_str:match("TRUE")
            or verdict_str:match("CONFIRM") then
            return "holds"
        end
        return "refuted"
    end

    -- Fallback heuristics
    if upper:match("HOLDS") or upper:match("CONDITION IS TRUE")
        or upper:match("ANSWER IS WRONG") or upper:match("INVALIDAT") then
        return "holds"
    end
    return "refuted"
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_conditions = ctx.max_conditions or 5
    local gen_tokens = ctx.gen_tokens or 600
    local verify_tokens = ctx.verify_tokens or 200
    local revise_tokens = ctx.revise_tokens or 600

    -- ─── Step 1: Generate initial answer ───
    local answer = ctx.answer
    if not answer then
        answer = alc.llm(
            string.format(
                "Task: %s\n\nProvide a thorough, well-reasoned answer.",
                task
            ),
            {
                system = "You are an expert. Provide a detailed, accurate answer.",
                max_tokens = gen_tokens,
            }
        )
        alc.log("info", string.format(
            "negation: generated initial answer (%d chars)", #answer
        ))
    end

    -- ─── Step 2: Generate destruction conditions ───
    alc.log("info", string.format(
        "negation: generating up to %d destruction conditions", max_conditions
    ))

    local conditions_raw = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Proposed answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Your job is to ATTACK this answer. Generate specific "
                .. "destruction conditions — scenarios or facts that, if true, "
                .. "would INVALIDATE this answer.\n\n"
                .. "For each condition:\n"
                .. "- Be specific and concrete (not vague)\n"
                .. "- Target the weakest assumptions in the answer\n"
                .. "- Include factual claims that could be checked\n"
                .. "- Consider edge cases, exceptions, and counterexamples\n\n"
                .. "Generate up to %d destruction conditions:\n"
                .. "1. [condition that would invalidate the answer]\n"
                .. "2. ...",
            task, answer, max_conditions
        ),
        {
            system = "You are a rigorous adversarial tester. Your goal is to find "
                .. "every possible way the answer could be wrong. Be creative, "
                .. "thorough, and ruthless in generating failure conditions. "
                .. "Do not hold back — the goal is to stress-test the answer.",
            max_tokens = gen_tokens,
        }
    )

    local conditions = parse_conditions(conditions_raw)

    if #conditions == 0 then
        alc.log("warn", "negation: no destruction conditions parsed")
        ctx.result = {
            answer = answer,
            survived = true,
            conditions = {},
            holding = 0,
            refuted = 0,
            total = 0,
            revised = false,
        }
        return ctx
    end

    alc.log("info", string.format(
        "negation: %d destruction conditions generated", #conditions
    ))

    -- ─── Step 3: Verify each condition ───
    local verifications = alc.map(conditions, function(condition)
        return alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Proposed answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Destruction condition:\n\"%s\"\n\n"
                    .. "Does this destruction condition actually hold? "
                    .. "Is it factually true that this condition exists?\n\n"
                    .. "Analyze carefully, then respond:\n"
                    .. "VERDICT: HOLDS (condition is true, answer may be wrong) "
                    .. "or REFUTED (condition is false, answer survives)\n"
                    .. "REASONING: [your analysis]",
                task, answer, condition
            ),
            {
                system = "You are an impartial fact-checker. Evaluate whether "
                    .. "the destruction condition actually holds. Be rigorous: "
                    .. "HOLDS only if you are confident the condition is true. "
                    .. "REFUTED if the condition is false or unsupported.",
                max_tokens = verify_tokens,
            }
        )
    end)

    -- Parse results
    local condition_results = {}
    local holding = 0
    local refuted = 0

    for i, raw in ipairs(verifications) do
        local verdict = parse_verdict(raw)
        local reasoning = raw:match("REASONING:%s*(.-)$")
            or raw:match("\n([^\n]+)$")
            or ""
        reasoning = reasoning:match("^%s*(.-)%s*$") or ""

        condition_results[#condition_results + 1] = {
            condition = conditions[i],
            verdict = verdict,
            reasoning = reasoning,
            raw = raw,
        }

        if verdict == "holds" then
            holding = holding + 1
        else
            refuted = refuted + 1
        end
    end

    alc.log("info", string.format(
        "negation: %d holding, %d refuted out of %d conditions",
        holding, refuted, #conditions
    ))

    -- ─── Step 4: Revise if any destruction conditions hold ───
    local final_answer = answer
    local revised = false

    if holding > 0 then
        alc.log("info", string.format(
            "negation: %d conditions hold — revising answer", holding
        ))

        local holding_list = {}
        for _, cr in ipairs(condition_results) do
            if cr.verdict == "holds" then
                holding_list[#holding_list + 1] = string.format(
                    "- %s\n  Reasoning: %s",
                    cr.condition, cr.reasoning
                )
            end
        end

        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Original answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "The following destruction conditions were found to HOLD, "
                    .. "meaning the original answer has flaws:\n\n%s\n\n"
                    .. "Revise the answer to address ALL holding conditions. "
                    .. "Explain what was wrong and provide the corrected answer.",
                task, answer, table.concat(holding_list, "\n")
            ),
            {
                system = "You are an expert reviser. The original answer has "
                    .. "confirmed weaknesses. Address each one specifically. "
                    .. "Do not dismiss valid criticisms. Produce a corrected, "
                    .. "improved answer.",
                max_tokens = revise_tokens,
            }
        )
        revised = true

        alc.log("info", string.format(
            "negation: answer revised (%d chars)", #final_answer
        ))
    else
        alc.log("info", "negation: all conditions refuted — answer survived")
    end

    ctx.result = {
        answer = final_answer,
        initial_answer = answer,
        survived = holding == 0,
        conditions = condition_results,
        holding = holding,
        refuted = refuted,
        total = #conditions,
        revised = revised,
    }
    return ctx
end

return M
