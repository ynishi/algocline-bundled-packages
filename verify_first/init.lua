--- verify_first — Verification-First prompting
---
--- Provides a candidate answer (trivial, random, or CoT-generated), then
--- instructs the LLM to verify it before generating the real answer.
--- "Reverse reasoning" is cognitively easier than forward generation and
--- reduces logical errors by overcoming egocentric bias.
---
--- Supports iterative mode (Iter-VF): Markovian verify→extract→re-verify
--- loop that scales test-time compute without context overflow.
---
--- Based on: "Asking LLMs to Verify First is Almost Free Lunch"
---           (arXiv 2511.21734, 2025)
---
--- Pipeline:
---   Step 1: generate   — produce an initial candidate answer (CoT or trivial)
---   Step 2: verify     — "A possible answer is X. First verify if X is correct,
---                          then think step by step to find the answer."
---   Step 3 (Iter-VF):   repeat Step 2 with extracted answer from previous round
---
--- Usage:
---   local verify_first = require("verify_first")
---   return verify_first.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.candidate: Pre-supplied candidate answer (default: nil → auto-generate)
--- ctx.trivial: Use trivial candidate "1" instead of CoT (default: false)
--- ctx.iterations: Number of Iter-VF rounds (default: 1, i.e. single VF)
--- ctx.gen_tokens: Max tokens for generation (default: 600)
--- ctx.verify_tokens: Max tokens for verification (default: 800)

local M = {}

M.meta = {
    name = "verify_first",
    version = "0.1.0",
    description = "Verification-First prompting — verify a candidate answer before generating, reducing logical errors via reverse reasoning",
    category = "reasoning",
}

--- Extract a final answer from verification output.
--- Looks for common answer patterns; falls back to full text.
local function extract_answer(text)
    -- Match "The answer is X" / "Final answer: X" / "Therefore, X"
    -- Terminate at sentence-ending period (period + space/newline/EOF),
    -- NOT at decimal points (period + digit).
    local answer = text:match("[Tt]he%s+answer%s+is%s*:?%s*(.-)%s*%.%s*\n")
        or text:match("[Ff]inal%s+[Aa]nswer%s*:?%s*(.-)%s*%.%s*\n")
        or text:match("[Tt]herefore%s*,?%s*(.-)%s*%.%s*\n")
        -- Fallback: match to end of line (no period required)
        or text:match("[Tt]he%s+answer%s+is%s*:?%s*(.-)%s*$")
        or text:match("[Ff]inal%s+[Aa]nswer%s*:?%s*(.-)%s*$")
    if answer and #answer > 0 and #answer < 500 then
        -- Trim trailing whitespace and periods
        answer = answer:match("^%s*(.-)%s*$")
        return answer
    end
    return text
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local iterations = ctx.iterations or 1
    local gen_tokens = ctx.gen_tokens or 600
    local verify_tokens = ctx.verify_tokens or 800

    -- ─── Step 1: Produce initial candidate answer ───
    local candidate
    if ctx.candidate then
        candidate = ctx.candidate
        alc.log("info", "verify_first: using provided candidate answer")
    elseif ctx.trivial then
        candidate = "1"
        alc.log("info", "verify_first: using trivial candidate '1'")
    else
        -- Generate via standard CoT
        candidate = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Think step by step to find the answer.",
                task
            ),
            {
                system = "You are an expert. Solve the task step by step. "
                    .. "End with a clear final answer.",
                max_tokens = gen_tokens,
            }
        )
        alc.log("info", string.format(
            "verify_first: generated CoT candidate (%d chars)", #candidate
        ))
    end

    -- ─── Step 2+: Verification loop (Iter-VF) ───
    local current_answer = candidate
    local history = {}

    for i = 1, iterations do
        alc.log("info", string.format(
            "verify_first: verification round %d/%d", i, iterations
        ))

        local verification = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "A possible answer is:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "First verify if this answer is correct. "
                    .. "Check each step and assumption carefully. "
                    .. "Then think step by step to find the correct answer.",
                task, current_answer
            ),
            {
                system = "You are a rigorous verifier. First examine the candidate "
                    .. "answer for errors — check logic, calculations, and assumptions. "
                    .. "Then derive the correct answer independently. "
                    .. "End with a clear final answer.",
                max_tokens = verify_tokens,
            }
        )

        local extracted = extract_answer(verification)

        history[#history + 1] = {
            round = i,
            input_candidate = current_answer,
            verification = verification,
            extracted_answer = extracted,
        }

        -- Markovian: use extracted answer for next round
        current_answer = extracted

        alc.log("info", string.format(
            "verify_first: round %d complete, extracted answer: %s",
            i, extracted:sub(1, 100)
        ))
    end

    local final_round = history[#history]

    ctx.result = {
        answer = final_round.verification,
        extracted_answer = final_round.extracted_answer,
        iterations = iterations,
        history = history,
        candidate_source = ctx.candidate and "provided"
            or ctx.trivial and "trivial"
            or "cot",
    }
    return ctx
end

return M
