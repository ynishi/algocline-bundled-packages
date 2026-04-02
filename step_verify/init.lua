--- step_verify — Step-Level Verification (PRM-style, LLM-as-Verifier)
---
--- Verifies each intermediate reasoning step independently, identifying
--- exactly where errors occur. Retains only verified-correct steps and
--- re-derives from the last correct point.
---
--- Key difference from cove / factscore:
---   cove       — generates verification QUESTIONS about factual claims,
---                answers them independently, then revises. Targets factual
---                accuracy of the whole draft.
---   factscore  — decomposes text into atomic factual claims and scores each.
---                Targets factual precision (is each fact true?).
---   step_verify — scores each REASONING STEP for logical correctness.
---                Targets logical validity (does step N follow from step N-1?).
---                Identifies the first point of failure and re-derives from there.
---
--- Grounded in Process Reward Model (PRM) research:
---   - PRMs consistently outperform Outcome Reward Models (ORMs) for
---     mathematical and multi-step reasoning (Lightman et al., 2023)
---   - Step-level supervision localizes errors that outcome-level misses
---   - ThinkPRM: generative verification via chain-of-thought (2025)
---   - DiVeRSe: diverse prompts + step-level verification (Li et al.)
---
--- Based on: PRM Survey (arXiv:2510.08049, 2025), ThinkPRM (arXiv:2504.16828),
--- DiVeRSe (arXiv:2502.09955)
---
--- Usage:
---   local sv = require("step_verify")
---   return sv.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.max_repair_rounds: Max re-derivation attempts (default: 2)
--- ctx.gen_tokens: Max tokens for generation (default: 500)
--- ctx.verify_tokens: Max tokens per verification (default: 200)

local M = {}

---@type AlcMeta
M.meta = {
    name = "step_verify",
    version = "0.1.0",
    description = "Step-level reasoning verification — PRM-style LLM-as-Verifier "
        .. "that scores each reasoning step independently. Identifies the first "
        .. "point of failure and re-derives from the last correct step.",
    category = "validation",
}

--- Parse a multi-step reasoning into individual steps.
local function parse_steps(reasoning)
    local steps = {}
    -- Try numbered steps first (1. / Step 1: / etc.)
    for step in reasoning:gmatch("[Ss]tep%s*%d+[%.:%s]+([^\n]+[^\n]*)") do
        if #step > 5 then
            steps[#steps + 1] = step:match("^%s*(.-)%s*$")
        end
    end
    if #steps >= 2 then return steps end

    -- Fallback: numbered list
    steps = {}
    for step in reasoning:gmatch("%d+[%.%)%s]+([^\n]+)") do
        if #step > 5 then
            steps[#steps + 1] = step:match("^%s*(.-)%s*$")
        end
    end
    if #steps >= 2 then return steps end

    -- Last resort: split by newlines, filter short lines
    steps = {}
    for line in reasoning:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if #trimmed > 20 then
            steps[#steps + 1] = trimmed
        end
    end
    return steps
end

--- Generate step-by-step reasoning for a task.
local function generate_reasoning(task, context, gen_tokens)
    local prompt
    if context and #context > 0 then
        prompt = string.format(
            "Task: %s\n\n"
                .. "Verified correct steps so far:\n%s\n\n"
                .. "Continue from the last verified step. Solve the remaining "
                .. "part step by step. Number each step (Step 1, Step 2, ...).",
            task, context
        )
    else
        prompt = string.format(
            "Task: %s\n\n"
                .. "Solve step by step. Number each step (Step 1, Step 2, ...). "
                .. "Show your reasoning clearly at each step.",
            task
        )
    end

    return alc.llm(prompt, {
        system = "You are a precise, methodical reasoner. Show each reasoning "
            .. "step clearly and number them sequentially.",
        max_tokens = gen_tokens,
    })
end

--- Verify a single step against the context of prior steps.
--- Returns { correct = bool, explanation = string }
local function verify_step(task, prior_steps_text, step_text, step_num, verify_tokens)
    local raw = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Prior verified steps:\n%s\n\n"
                .. "Step %d to verify: %s\n\n"
                .. "Evaluate this step:\n"
                .. "1. Does it logically follow from the prior steps?\n"
                .. "2. Is the reasoning or calculation correct?\n"
                .. "3. Are there any errors, unjustified leaps, or mistakes?\n\n"
                .. "End your evaluation with exactly one of:\n"
                .. "VERDICT: CORRECT\n"
                .. "VERDICT: INCORRECT",
            task,
            (#prior_steps_text > 0) and prior_steps_text or "(initial step)",
            step_num,
            step_text
        ),
        {
            system = "You are a rigorous step-by-step verifier. Check logical "
                .. "validity and correctness of each reasoning step. Be strict: "
                .. "flag any unjustified leaps, calculation errors, or logical "
                .. "fallacies. End with VERDICT: CORRECT or VERDICT: INCORRECT.",
            max_tokens = verify_tokens,
        }
    )

    local correct = raw:match("VERDICT:%s*CORRECT") ~= nil
    return { correct = correct, explanation = raw }
end

--- Synthesize final answer from verified reasoning.
local function synthesize(task, verified_steps_text, gen_tokens)
    return alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Verified reasoning:\n%s\n\n"
                .. "Based on the verified reasoning above, provide a clear "
                .. "and complete final answer.",
            task, verified_steps_text
        ),
        {
            system = "Synthesize a clear answer from the verified reasoning. "
                .. "Be concise and accurate.",
            max_tokens = gen_tokens,
        }
    )
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_repair = ctx.max_repair_rounds or 2
    local gen_tokens = ctx.gen_tokens or 500
    local verify_tokens = ctx.verify_tokens or 200

    local verified_steps = {}
    local all_rounds = {}
    local total_llm_calls = 0

    for round = 0, max_repair do
        -- Build context from verified steps so far
        local context = ""
        if #verified_steps > 0 then
            local parts = {}
            for i, s in ipairs(verified_steps) do
                parts[#parts + 1] = string.format("Step %d: %s", i, s)
            end
            context = table.concat(parts, "\n")
        end

        -- Generate reasoning
        local reasoning = generate_reasoning(task, context, gen_tokens)
        total_llm_calls = total_llm_calls + 1

        -- Parse into steps
        local steps = parse_steps(reasoning)
        if #steps == 0 then
            -- If parsing fails, treat whole response as one step
            steps = { reasoning }
        end

        alc.log("info", string.format(
            "step_verify: round %d — %d steps to verify", round, #steps
        ))

        -- Verify each step sequentially
        local round_results = { round = round, steps = {} }
        local first_error_idx = nil

        for i, step in ipairs(steps) do
            -- Build prior steps text
            local prior_parts = {}
            for j, vs in ipairs(verified_steps) do
                prior_parts[#prior_parts + 1] = string.format("Step %d: %s", j, vs)
            end
            -- Also include already-verified steps from this round
            for j = 1, i - 1 do
                if round_results.steps[j] and round_results.steps[j].correct then
                    prior_parts[#prior_parts + 1] = string.format(
                        "Step %d: %s", #verified_steps + j, steps[j]
                    )
                end
            end
            local prior_text = table.concat(prior_parts, "\n")

            local verdict = verify_step(
                task, prior_text, step,
                #verified_steps + i, verify_tokens
            )
            total_llm_calls = total_llm_calls + 1

            round_results.steps[i] = {
                step = step,
                correct = verdict.correct,
                explanation = verdict.explanation,
            }

            if verdict.correct then
                alc.log("debug", string.format(
                    "step_verify: step %d CORRECT", #verified_steps + i
                ))
            else
                first_error_idx = i
                alc.log("info", string.format(
                    "step_verify: step %d INCORRECT — will re-derive",
                    #verified_steps + i
                ))
                break
            end
        end

        -- Accumulate verified steps from this round
        local verified_this_round = 0
        for i, sr in ipairs(round_results.steps) do
            if sr.correct then
                verified_steps[#verified_steps + 1] = steps[i]
                verified_this_round = verified_this_round + 1
            else
                break
            end
        end

        round_results.verified_count = verified_this_round
        round_results.error_at = first_error_idx
        all_rounds[#all_rounds + 1] = round_results

        -- If all steps were correct, we're done
        if not first_error_idx then
            alc.log("info", string.format(
                "step_verify: all steps verified after %d rounds", round + 1
            ))
            break
        end

        -- Otherwise, continue to next repair round (re-derive from last correct step)
        if round < max_repair then
            alc.log("info", string.format(
                "step_verify: re-deriving from step %d (round %d)",
                #verified_steps, round + 1
            ))
        end
    end

    -- Final synthesis
    local verified_text = ""
    for i, s in ipairs(verified_steps) do
        verified_text = verified_text .. string.format("Step %d: %s\n", i, s)
    end

    local final_answer = synthesize(task, verified_text, gen_tokens)
    total_llm_calls = total_llm_calls + 1

    ctx.result = {
        answer = final_answer,
        verified_steps = verified_steps,
        total_verified = #verified_steps,
        rounds = all_rounds,
        total_rounds = #all_rounds,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

return M
