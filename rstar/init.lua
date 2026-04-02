--- rstar — Mutual reasoning verification via self-play
---
--- Generates two independent reasoning paths, then each path verifies
--- the other. Disagreements trigger a resolution round. Achieves MCTS-level
--- accuracy at a fraction of the cost by replacing tree search with
--- targeted mutual critique.
---
--- Based on: Qi et al., "Mutual Reasoning Makes Smaller LLMs Stronger
--- Problem-Solvers" (rStar, 2024, arXiv:2408.06195)
---
--- Pipeline (4-6 LLM calls):
---   Step 1: Generate Path A — independent reasoning attempt
---   Step 2: Generate Path B — independent reasoning attempt (parallel)
---   Step 3: Cross-verify    — A verifies B, B verifies A (parallel)
---   Step 4: Resolve         — if disagreement, synthesize final answer
---
--- Usage:
---   local rstar = require("rstar")
---   return rstar.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.gen_tokens: Max tokens per reasoning path (default: 400)
--- ctx.verify_tokens: Max tokens per verification (default: 300)

local M = {}

---@type AlcMeta
M.meta = {
    name = "rstar",
    version = "0.1.0",
    description = "Mutual reasoning verification — two paths cross-verify each other for efficient accuracy",
    category = "reasoning",
}

--- Extract the core conclusion from a reasoning path.
local function extract_conclusion(text)
    -- Look for explicit conclusion markers
    local conclusion = text:match("[Cc]onclusion:%s*(.-)$")
        or text:match("[Ff]inal [Aa]nswer:%s*(.-)$")
        or text:match("[Tt]herefore,%s*(.-)$")
    if conclusion and #conclusion > 0 then
        return conclusion
    end
    -- Fallback: last substantive sentence
    local last_line = ""
    for line in text:gmatch("[^\n]+") do
        if #line > 10 then last_line = line end
    end
    return last_line
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local gen_tokens = ctx.gen_tokens or 400
    local verify_tokens = ctx.verify_tokens or 300

    -- ─── Step 1 & 2: Generate two independent reasoning paths (parallel) ───
    alc.log("info", "rstar: generating two independent reasoning paths")

    local paths = alc.map({ "A", "B" }, function(label)
        local approach_hint = label == "A"
            and "Start from first principles and build up systematically."
            or "Consider the problem from multiple angles before converging."

        return alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "%s\n"
                    .. "Show your complete reasoning step by step. "
                    .. "End with a clear conclusion.",
                task, approach_hint
            ),
            {
                system = "You are a rigorous problem solver. Reason carefully "
                    .. "and show all steps. State your conclusion explicitly.",
                max_tokens = gen_tokens,
            }
        )
    end)

    local path_a = paths[1]
    local path_b = paths[2]

    local conclusion_a = extract_conclusion(path_a)
    local conclusion_b = extract_conclusion(path_b)

    alc.log("info", "rstar: two paths generated, starting cross-verification")

    -- ─── Step 3: Cross-verify (parallel) ───
    -- A verifies B's reasoning, B verifies A's reasoning
    local verifications = alc.map({ "A_checks_B", "B_checks_A" }, function(direction)
        local checker_path, target_path, checker_label, target_label
        if direction == "A_checks_B" then
            checker_path = path_a
            target_path = path_b
            checker_label = "A"
            target_label = "B"
        else
            checker_path = path_b
            target_path = path_a
            checker_label = "B"
            target_label = "A"
        end

        return alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Your reasoning (Path %s):\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Another solver's reasoning (Path %s):\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Verify Path %s's reasoning:\n"
                    .. "1. Are there any logical errors or incorrect steps?\n"
                    .. "2. Does the conclusion follow from the reasoning?\n"
                    .. "3. Did they miss anything important?\n\n"
                    .. "Then state:\n"
                    .. "VERDICT: AGREE (their conclusion is correct) or "
                    .. "DISAGREE (their conclusion has errors)\n"
                    .. "If DISAGREE, explain the specific error.",
                task, checker_label, checker_path,
                target_label, target_path, target_label
            ),
            {
                system = "You are a rigorous verifier. Check each step for "
                    .. "correctness. Be specific about any errors found.",
                max_tokens = verify_tokens,
            }
        )
    end)

    local a_checks_b = verifications[1]
    local b_checks_a = verifications[2]

    -- Parse verdicts
    local a_agrees_b = not a_checks_b:upper():match("DISAGREE")
    local b_agrees_a = not b_checks_a:upper():match("DISAGREE")

    alc.log("info", string.format(
        "rstar: cross-verification — A agrees with B: %s, B agrees with A: %s",
        tostring(a_agrees_b), tostring(b_agrees_a)
    ))

    -- ─── Step 4: Resolve ───
    local final_answer
    local resolution_needed = false

    if a_agrees_b and b_agrees_a then
        -- Both agree: high confidence, use either (prefer A)
        alc.log("info", "rstar: mutual agreement — using Path A conclusion")
        final_answer = conclusion_a

    elseif a_agrees_b and not b_agrees_a then
        -- B found error in A, but A thinks B is fine → trust B
        alc.log("info", "rstar: B found error in A — using Path B")
        final_answer = conclusion_b

    elseif not a_agrees_b and b_agrees_a then
        -- A found error in B, but B thinks A is fine → trust A
        alc.log("info", "rstar: A found error in B — using Path A")
        final_answer = conclusion_a

    else
        -- Both disagree with each other → synthesis needed
        resolution_needed = true
        alc.log("info", "rstar: mutual disagreement — synthesizing resolution")

        local resolution = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Two solvers produced different answers:\n\n"
                    .. "Path A:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Path B:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "A's critique of B:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "B's critique of A:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Analyze both critiques carefully. Determine which "
                    .. "path's reasoning is more sound, or synthesize a "
                    .. "corrected answer incorporating valid points from both.",
                task, path_a, path_b, a_checks_b, b_checks_a
            ),
            {
                system = "You are an expert arbiter. Evaluate the critiques "
                    .. "objectively. Identify the correct reasoning and produce "
                    .. "a definitive answer.",
                max_tokens = gen_tokens,
            }
        )
        final_answer = extract_conclusion(resolution)
    end

    local agreement_level
    if a_agrees_b and b_agrees_a then
        agreement_level = "full"
    elseif a_agrees_b or b_agrees_a then
        agreement_level = "partial"
    else
        agreement_level = "none"
    end

    ctx.result = {
        answer = final_answer,
        agreement = agreement_level,
        resolution_needed = resolution_needed,
        path_a = {
            reasoning = path_a,
            conclusion = conclusion_a,
        },
        path_b = {
            reasoning = path_b,
            conclusion = conclusion_b,
        },
        verification = {
            a_checks_b = a_checks_b,
            b_checks_a = b_checks_a,
            a_agrees_b = a_agrees_b,
            b_agrees_a = b_agrees_a,
        },
    }
    return ctx
end

return M
