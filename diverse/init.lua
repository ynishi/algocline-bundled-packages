--- DiVERSe — diverse reasoning paths with step-level verification
--- Generates multiple diverse reasoning paths, then verifies each path
--- at the step level (not just the final answer). Selects the path with
--- the highest step-level verification score.
---
--- Based on: Li et al., "Making Language Models Better Reasoners with
--- Step-Aware Verifier" (DiVERSe, 2023, arXiv:2206.02336)
---
--- Usage:
---   local diverse = require("diverse")
---   return diverse.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n_paths: Number of diverse reasoning paths (default: 3)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "diverse",
    version = "0.1.0",
    description = "DiVERSe — diverse reasoning paths with step-level verification and selection",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task    = T.string:describe("The problem to solve"),
                n_paths = T.number:is_optional():describe("Number of diverse reasoning paths (default: 3)"),
            }),
            result = T.shape({
                answer         = T.string:describe("Final synthesized answer from the best path"),
                best_path_id   = T.number:describe("path_id of the highest-scoring path"),
                best_avg_score = T.number:describe("Average step score of the winning path"),
                ranking        = T.array_of(T.shape({
                    rank           = T.number:describe("1-based rank after sorting by avg_score"),
                    path_id        = T.number:describe("Original path identifier"),
                    avg_score      = T.number:describe("Average step-level score"),
                    steps_verified = T.number:describe("Number of steps that received a verification score"),
                })):describe("Paths ordered from best to worst by avg_score"),
                paths          = T.array_of(T.shape({
                    path_id      = T.number:describe("Original path identifier"),
                    reasoning    = T.string:describe("Full reasoning text for the path"),
                    verification = T.shape({
                        step_scores = T.array_of(T.shape({
                            step  = T.string:describe("Step text (or whole reasoning when fallback)"),
                            score = T.number:describe("Per-step correctness score"),
                        })):describe("Per-step verification results"),
                        total_score = T.number:describe("Sum of per-step scores"),
                        avg_score   = T.number:describe("Mean of per-step scores"),
                    }):describe("Step-level verification results for the path"),
                })):describe("All generated paths with verification details (sorted)"),
            }),
        },
    },
}

--- Parse a reasoning path into individual steps.
local function parse_steps(reasoning)
    local steps = {}
    -- Try numbered format first: "1. ...", "Step 1: ..."
    for step in reasoning:gmatch("[Ss]tep%s*%d+[.:]+%s*([^\n]+)") do
        if #step > 5 then steps[#steps + 1] = step end
    end
    if #steps == 0 then
        for step in reasoning:gmatch("%d+%.%s*([^\n]+)") do
            if #step > 5 then steps[#steps + 1] = step end
        end
    end
    -- Fallback: split by sentences
    if #steps == 0 then
        for step in reasoning:gmatch("([^.!?]+[.!?])") do
            local trimmed = step:match("^%s*(.-)%s*$")
            if #trimmed > 10 then steps[#steps + 1] = trimmed end
        end
    end
    return steps
end

--- Verify each step in a reasoning path. Returns per-step scores and overall.
local function verify_steps(task, steps)
    local scores = {}
    local total = 0

    for i, step in ipairs(steps) do
        local prior = ""
        for j = 1, i - 1 do
            prior = prior .. string.format("  Step %d: %s\n", j, steps[j])
        end

        local score_str = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Reasoning so far:\n%s"
                    .. "Current step (Step %d): %s\n\n"
                    .. "Verify this step:\n"
                    .. "- Is it logically correct given the prior steps?\n"
                    .. "- Does it follow validly from what came before?\n"
                    .. "- Is it relevant to solving the task?\n\n"
                    .. "Rate correctness 1-10. Reply with ONLY the number.",
                task, prior, i, step
            ),
            { system = "You are a step-level verifier. Rate ONLY this step's correctness. Just the number.", max_tokens = 10 }
        )

        local score = alc.parse_score(score_str)
        scores[#scores + 1] = { step = step, score = score }
        total = total + score
    end

    return {
        step_scores = scores,
        total_score = total,
        avg_score = #scores > 0 and (total / #scores) or 0,
    }
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_paths = ctx.n_paths or 3

    -- Phase 1: Generate diverse reasoning paths
    local paths = {}

    for i = 1, n_paths do
        local existing = ""
        if #paths > 0 then
            for j, p in ipairs(paths) do
                existing = existing .. string.format(
                    "  [Path %d approach]: %s\n", j, p.reasoning
                )
            end
        end

        local prompt_style
        if i == 1 then
            prompt_style = "Solve step by step using a straightforward approach."
        elseif i == 2 then
            prompt_style = "Solve step by step, but try an alternative or unconventional approach."
        else
            prompt_style = string.format(
                "Solve step by step using a DIFFERENT approach from these:\n%s", existing
            )
        end

        local reasoning = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "%s\n"
                    .. "Number each step clearly (Step 1, Step 2, etc.).",
                task, prompt_style
            ),
            {
                system = "You are a methodical problem solver. Show each reasoning step clearly. "
                    .. "Use a different approach or perspective from other paths.",
                max_tokens = 400,
            }
        )

        paths[#paths + 1] = {
            path_id = i,
            reasoning = reasoning,
        }
    end

    -- Phase 2: Step-level verification for each path
    local verified_paths = {}

    for _, path in ipairs(paths) do
        local steps = parse_steps(path.reasoning)
        local verification

        if #steps >= 2 then
            verification = verify_steps(task, steps)
        else
            -- Fallback: score the whole path as one step
            alc.log("warn", string.format(
                "diverse: path %d — only %d steps parsed, scoring as single block",
                path.path_id, #steps
            ))
            local score_str = alc.llm(
                string.format(
                    "Task: %s\n\nReasoning:\n%s\n\n"
                        .. "Rate the overall correctness 1-10. Reply with ONLY the number.",
                    task, path.reasoning
                ),
                { system = "Rate overall correctness. Just the number.", max_tokens = 10 }
            )
            local score = alc.parse_score(score_str)
            verification = {
                step_scores = { { step = path.reasoning, score = score } },
                total_score = score,
                avg_score = score,
            }
        end

        verified_paths[#verified_paths + 1] = {
            path_id = path.path_id,
            reasoning = path.reasoning,
            verification = verification,
        }

        alc.log("info", string.format(
            "diverse: path %d — %d steps, avg score: %.1f",
            path.path_id, #verification.step_scores, verification.avg_score
        ))
    end

    -- Phase 3: Select best path
    table.sort(verified_paths, function(a, b)
        return a.verification.avg_score > b.verification.avg_score
    end)
    local best = verified_paths[1]

    -- Phase 4: Synthesize final answer from best path
    local answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Best verified reasoning path (avg step score: %.1f/10):\n%s\n\n"
                .. "Synthesize this reasoning into a clear, comprehensive final answer.",
            task, best.verification.avg_score, best.reasoning
        ),
        { system = "You are an expert synthesizer. Produce a clear, well-structured answer.", max_tokens = 600 }
    )

    -- Build ranking summary
    local ranking = {}
    for i, vp in ipairs(verified_paths) do
        ranking[#ranking + 1] = {
            rank = i,
            path_id = vp.path_id,
            avg_score = vp.verification.avg_score,
            steps_verified = #vp.verification.step_scores,
        }
    end

    ctx.result = {
        answer = answer,
        best_path_id = best.path_id,
        best_avg_score = best.verification.avg_score,
        ranking = ranking,
        paths = verified_paths,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
