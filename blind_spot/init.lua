--- blind_spot — Self-Correction Blind Spot bypass
---
--- LLMs cannot correct errors in their own outputs but can successfully
--- correct identical errors when presented as coming from external sources.
--- This package exploits that asymmetry: generate an answer, then re-present
--- it as a "colleague's draft" for the same LLM to review and correct.
---
--- Additionally applies the "Wait" trigger: appending a minimal pause prompt
--- activates dormant correction capabilities (89.3% blind spot reduction
--- observed across 14 open-source models).
---
--- Based on: "Self-Correction Bench: Uncovering and Addressing the
---            Self-Correction Blind Spot in Large Language Models"
---            (arXiv 2507.02778, 2025)
---
--- Pipeline:
---   Step 1: generate   — produce initial answer normally
---   Step 2: externalize — re-present the answer as from an external source
---   Step 3: correct    — ask to find and fix errors in the "external" answer
---   Step 4: wait       — optional "Wait" reflection trigger for final check
---
--- Usage:
---   local blind_spot = require("blind_spot")
---   return blind_spot.run(ctx)
---
--- ctx.task (required): The task/question to solve
--- ctx.rounds: Number of externalize→correct rounds (default: 1)
--- ctx.wait: Enable "Wait" reflection trigger (default: true)
--- ctx.gen_tokens: Max tokens for generation (default: 600)
--- ctx.correct_tokens: Max tokens for correction (default: 800)

local M = {}

---@type AlcMeta
M.meta = {
    name = "blind_spot",
    version = "0.1.0",
    description = "Self-Correction Blind Spot bypass — re-present own output as external source to trigger genuine error correction",
    category = "correction",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rounds = ctx.rounds or 1
    local enable_wait = ctx.wait ~= false  -- default true
    local gen_tokens = ctx.gen_tokens or 600
    local correct_tokens = ctx.correct_tokens or 800

    -- ─── Step 1: Generate initial answer ───
    local initial = alc.llm(
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
        "blind_spot: initial answer generated (%d chars)", #initial
    ))

    -- ─── Step 2+3: Externalize and correct loop ───
    local current = initial
    local history = {
        { round = 0, role = "initial", text = initial },
    }

    for i = 1, rounds do
        alc.log("info", string.format(
            "blind_spot: externalize→correct round %d/%d", i, rounds
        ))

        -- Externalize: present as colleague's draft
        local correction = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "A colleague submitted the following answer for review. "
                    .. "Your job is to carefully check it for errors — logical flaws, "
                    .. "incorrect facts, missing considerations, or wrong conclusions.\n\n"
                    .. "Colleague's answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "First, identify ALL errors (if any) with specific explanations. "
                    .. "Then provide the corrected, complete answer.",
                task, current
            ),
            {
                system = "You are a senior reviewer examining a colleague's work. "
                    .. "Be thorough and critical. Check every claim, calculation, "
                    .. "and logical step. If the answer is correct, confirm why. "
                    .. "If there are errors, explain each one and provide the "
                    .. "corrected answer.",
                max_tokens = correct_tokens,
            }
        )

        history[#history + 1] = {
            round = i,
            role = "correction",
            text = correction,
        }

        current = correction
    end

    -- ─── Step 4: "Wait" reflection trigger ───
    local final_answer = current
    if enable_wait then
        alc.log("info", "blind_spot: applying 'Wait' reflection trigger")

        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Current answer:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Wait. Before finalizing, take a moment to reconsider. "
                    .. "Is there anything you missed? Any edge case, implicit assumption, "
                    .. "or subtle error? If so, correct it. If the answer is solid, "
                    .. "confirm and restate it clearly.",
                task, current
            ),
            {
                system = "You are performing a final sanity check. "
                    .. "Pause and reflect carefully before confirming or correcting.",
                max_tokens = correct_tokens,
            }
        )

        history[#history + 1] = {
            round = rounds + 1,
            role = "wait_reflection",
            text = final_answer,
        }
    end

    -- Count corrections made
    local corrections_detected = 0
    for i = 2, #history do
        local upper = history[i].text:upper()
        if upper:match("ERROR") or upper:match("INCORRECT")
            or upper:match("MISTAKE") or upper:match("WRONG")
            or upper:match("CORRECTION") or upper:match("FIX") then
            corrections_detected = corrections_detected + 1
        end
    end

    alc.log("info", string.format(
        "blind_spot: complete — %d round(s), %d correction(s) detected",
        rounds, corrections_detected
    ))

    ctx.result = {
        answer = final_answer,
        initial_answer = initial,
        corrections_detected = corrections_detected,
        rounds = rounds,
        wait_applied = enable_wait,
        history = history,
    }
    return ctx
end

return M
