--- reflexion — Episodic Memory Self-Improvement
---
--- Iteratively attempts a task, evaluates the result, generates a natural
--- language "reflection" from failures, and stores it in episodic memory.
--- Subsequent attempts reference accumulated reflections to avoid repeating
--- the same mistakes.
---
--- Key difference from reflect:
---   reflect   — Generate → Critique → Revise loop within a SINGLE attempt.
---               Each round improves the CURRENT draft. No memory across attempts.
---               Metaphor: proofreading and editing a paper.
---   reflexion — Multiple INDEPENDENT attempts, each informed by reflections on
---               previous FAILURES. Stores what went wrong and why in episodic
---               memory. Each attempt starts fresh but with accumulated wisdom.
---               Metaphor: retaking an exam after studying your mistakes.
---
--- Why this matters:
---   reflect polishes a single output (local optimization).
---   reflexion explores fundamentally different approaches informed by past
---   failures (global search with memory). On HumanEval: 67% → 91%.
---   On AlfWorld: achieved 134/134 tasks. The episodic memory prevents
---   the agent from repeating the same class of errors.
---
--- Based on: Shinn et al., "Reflexion: Language Agents with Verbal
--- Reinforcement Learning" (NeurIPS 2023, arXiv:2303.11366)
---
--- Usage:
---   local rfx = require("reflexion")
---   return rfx.run(ctx)
---
--- ctx.task (required): The task to solve
--- ctx.max_trials: Maximum number of attempts (default: 3)
--- ctx.evaluator: Custom evaluation prompt (optional)
--- ctx.success_threshold: Score threshold to accept (default: 8, scale 1-10)
--- ctx.gen_tokens: Max tokens per attempt (default: 500)
--- ctx.reflect_tokens: Max tokens per reflection (default: 300)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "reflexion",
    version = "0.1.0",
    description = "Episodic memory self-improvement — learns from failed attempts "
        .. "via verbal reinforcement. Each new attempt references accumulated "
        .. "reflections on past failures. reflect polishes; reflexion learns.",
    category = "refinement",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task              = T.string:describe("The task to solve"),
                max_trials        = T.number:is_optional():describe("Maximum number of attempts (default: 3)"),
                evaluator         = T.string:is_optional():describe("Custom evaluation prompt"),
                success_threshold = T.number:is_optional():describe("Score threshold to accept, 1-10 scale (default: 8)"),
                gen_tokens        = T.number:is_optional():describe("Max tokens per attempt (default: 500)"),
                reflect_tokens    = T.number:is_optional():describe("Max tokens per reflection (default: 300)"),
            }),
            result = T.shape({
                answer          = T.string:describe("Best attempt across all trials"),
                passed          = T.boolean:describe("Whether the final trial passed the threshold"),
                best_score      = T.number:describe("Score of the best-scoring attempt"),
                best_trial      = T.number:describe("1-based index of the best trial"),
                total_trials    = T.number:describe("Number of trials executed"),
                reflections     = T.array_of(T.string):describe("Accumulated episodic memory (one per failed trial except the last)"),
                trials          = T.array_of(T.shape({
                    trial      = T.number,
                    attempt    = T.string,
                    score      = T.number:describe("Grader score for this attempt (1-10 scale)"),
                    passed     = T.boolean:describe("Whether this trial reached success_threshold"),
                    feedback   = T.string,
                    reflection = T.string:is_optional(),
                })):describe("Ordered trial records with score, feedback, and optional reflection"),
                total_llm_calls = T.number:describe("Total alc.llm invocations across trials"),
            }),
        },
    },
}

--- Evaluate an attempt. Returns { score, passed, feedback }.
local function evaluate_attempt(task, attempt, evaluator, threshold)
    local eval_prompt = evaluator or string.format(
        "Task: %s\n\nAttempt:\n%s\n\n"
            .. "Evaluate this attempt on a 1-10 scale:\n"
            .. "- Does it correctly solve the task?\n"
            .. "- Is the reasoning sound?\n"
            .. "- Are there any errors or omissions?\n\n"
            .. "Respond with JSON: {\"score\": N, \"passed\": true/false, "
            .. "\"feedback\": \"specific issues found\"}",
        task, attempt
    )

    local raw = alc.llm(eval_prompt, {
        system = "You are a strict evaluator. Be precise about what's wrong. "
            .. "Score honestly: 8+ means correct with minor issues at most. "
            .. "Respond with valid JSON only.",
        max_tokens = 150,
    })

    -- Parse JSON response
    local json_str = raw:match("%b{}")
    if json_str then
        local ok, parsed = pcall(alc.json_decode, json_str)
        if ok and type(parsed) == "table" then
            local score = tonumber(parsed.score) or 5
            return {
                score = score,
                passed = score >= threshold,
                feedback = parsed.feedback or "",
            }
        end
    end

    -- Fallback: try to extract score
    local score = alc.parse_score(raw)
    return {
        score = score,
        passed = score >= threshold,
        feedback = raw,
    }
end

--- Generate a reflection on a failed attempt.
--- This is the core differentiator from reflect: the reflection is about
--- WHY the approach failed, not about HOW to fix the current draft.
local function generate_reflection(task, attempt, feedback, prior_reflections, reflect_tokens)
    local memory_text = ""
    if #prior_reflections > 0 then
        memory_text = "\n\nPrior reflections (lessons already learned):\n"
        for i, r in ipairs(prior_reflections) do
            memory_text = memory_text .. string.format(
                "Reflection %d: %s\n", i, r
            )
        end
    end

    return alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Failed attempt:\n%s\n\n"
                .. "Evaluation feedback: %s%s\n\n"
                .. "Reflect on this failure:\n"
                .. "1. What specific mistake(s) did the attempt make?\n"
                .. "2. What was the root cause (wrong approach, missing knowledge, "
                .. "careless error, etc.)?\n"
                .. "3. What concrete lesson should guide the next attempt?\n\n"
                .. "Write a concise reflection (2-3 sentences) that captures the "
                .. "key lesson. This will be shown to the next attempt as guidance.",
            task, attempt, feedback, memory_text
        ),
        {
            system = "You are a metacognitive coach. Extract the key lesson from "
                .. "this failure. Be specific and actionable — the next attempt "
                .. "will read this reflection to avoid the same mistake. "
                .. "Do not repeat prior reflections; identify NEW insights.",
            max_tokens = reflect_tokens,
        }
    )
end

--- Generate a new attempt, informed by episodic memory.
local function generate_attempt(task, reflections, gen_tokens)
    local memory_text = ""
    if #reflections > 0 then
        memory_text = "\n\nLessons from previous attempts (DO NOT repeat these mistakes):\n"
        for i, r in ipairs(reflections) do
            memory_text = memory_text .. string.format("- %s\n", r)
        end
        memory_text = memory_text .. "\nUse these lessons to guide a better approach.\n"
    end

    return alc.llm(
        string.format(
            "Task: %s%s\n\n"
                .. "Provide a thorough, correct solution.",
            task, memory_text
        ),
        {
            system = "You are an expert problem solver. "
                .. (
                    #reflections > 0
                        and "Learn from the lessons provided and take a different, better approach."
                        or "Give your best, most careful attempt."
                ),
            max_tokens = gen_tokens,
        }
    )
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_trials = ctx.max_trials or 3
    local evaluator = ctx.evaluator
    local threshold = ctx.success_threshold or 8
    local gen_tokens = ctx.gen_tokens or 500
    local reflect_tokens = ctx.reflect_tokens or 300

    local reflections = {}  -- episodic memory
    local trials = {}
    local total_llm_calls = 0
    local best = { score = 0, attempt = "", trial = 0 }

    for trial = 1, max_trials do
        alc.log("info", string.format(
            "reflexion: trial %d/%d (reflections: %d)",
            trial, max_trials, #reflections
        ))

        -- Generate attempt (informed by episodic memory)
        local attempt = generate_attempt(task, reflections, gen_tokens)
        total_llm_calls = total_llm_calls + 1

        -- Evaluate
        local eval_result = evaluate_attempt(task, attempt, evaluator, threshold)
        total_llm_calls = total_llm_calls + 1

        local trial_record = {
            trial = trial,
            attempt = attempt,
            score = eval_result.score,
            passed = eval_result.passed,
            feedback = eval_result.feedback,
            reflection = nil,
        }

        -- Track best
        if eval_result.score > best.score then
            best = {
                score = eval_result.score,
                attempt = attempt,
                trial = trial,
            }
        end

        if eval_result.passed then
            alc.log("info", string.format(
                "reflexion: PASSED at trial %d (score: %d)",
                trial, eval_result.score
            ))
            trial_record.reflection = "(passed — no reflection needed)"
            trials[#trials + 1] = trial_record
            break
        end

        -- Generate reflection on failure (only if not the last trial)
        if trial < max_trials then
            local reflection = generate_reflection(
                task, attempt, eval_result.feedback,
                reflections, reflect_tokens
            )
            total_llm_calls = total_llm_calls + 1

            reflections[#reflections + 1] = reflection
            trial_record.reflection = reflection

            alc.log("info", string.format(
                "reflexion: trial %d FAILED (score: %d) — reflection stored",
                trial, eval_result.score
            ))
        else
            alc.log("warn", string.format(
                "reflexion: final trial %d FAILED (score: %d) — returning best",
                trial, eval_result.score
            ))
        end

        trials[#trials + 1] = trial_record
    end

    local final_passed = #trials > 0 and trials[#trials].passed

    ctx.result = {
        answer = best.attempt,
        passed = final_passed,
        best_score = best.score,
        best_trial = best.trial,
        total_trials = #trials,
        reflections = reflections,
        trials = trials,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
