--- ToT — Tree-of-Thought reasoning
--- Explores multiple reasoning paths via branching, evaluation, and pruning.
--- Unlike linear CoT, ToT maintains a tree of thought branches and uses
--- beam search to focus on the most promising paths.
---
--- Based on: Yao et al., "Tree of Thoughts: Deliberate Problem Solving
--- with Large Language Models" (2023, arXiv:2305.10601)
---
--- Usage:
---   local tot = require("tot")
---   return tot.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.breadth: Thoughts generated per node (default: 3)
--- ctx.depth: Maximum tree depth (default: 3)
--- ctx.beam_width: Branches kept after pruning (default: 2)

local M = {}

---@type AlcMeta
M.meta = {
    name = "tot",
    version = "0.1.0",
    description = "Tree-of-Thought — branching reasoning with evaluation and pruning",
    category = "reasoning",
}

--- Evaluate a partial reasoning path. Returns a numeric score 1-10.
local function evaluate_thought(task, path_so_far, thought)
    local path_text = ""
    for i, step in ipairs(path_so_far) do
        path_text = path_text .. string.format("Step %d: %s\n", i, step)
    end

    local score_str = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Reasoning path so far:\n%s"
                .. "New thought: %s\n\n"
                .. "Evaluate this reasoning direction on a 1-10 scale:\n"
                .. "- Is it logically sound?\n"
                .. "- Does it make progress toward solving the task?\n"
                .. "- Is it a dead end or promising?\n\n"
                .. "Reply with ONLY the number.",
            task, path_text, thought
        ),
        { system = "You are a critical evaluator of reasoning quality. Just the number.", max_tokens = 10 }
    )

    return alc.parse_score(score_str)
end

--- Generate candidate thoughts for the next step.
local function generate_thoughts(task, path_so_far, breadth)
    local path_text = ""
    for i, step in ipairs(path_so_far) do
        path_text = path_text .. string.format("Step %d: %s\n", i, step)
    end

    local thoughts = {}
    for i = 1, breadth do
        local existing = ""
        if #thoughts > 0 then
            for j, t in ipairs(thoughts) do
                existing = existing .. string.format("  [Already proposed %d]: %s\n", j, t)
            end
        end

        local prompt
        if #path_so_far == 0 then
            prompt = string.format(
                "Task: %s\n\n"
                    .. "%s"
                    .. "Propose reasoning approach #%d. A distinct first step toward solving this. "
                    .. "Be specific and concrete. 1-3 sentences.",
                task,
                #thoughts > 0 and ("Other approaches already proposed:\n" .. existing .. "\nPropose a DIFFERENT approach.\n\n") or "",
                i
            )
        else
            prompt = string.format(
                "Task: %s\n\n"
                    .. "Reasoning so far:\n%s\n"
                    .. "%s"
                    .. "What is the next reasoning step? Propose idea #%d. "
                    .. "Be specific and concrete. 1-3 sentences.",
                task, path_text,
                #thoughts > 0 and ("Other next steps already proposed:\n" .. existing .. "\nPropose a DIFFERENT next step.\n\n") or "",
                i
            )
        end

        thoughts[#thoughts + 1] = alc.llm(prompt, {
            system = "You are a creative problem solver. Each thought must be distinct from others.",
            max_tokens = 200,
        })
    end

    return thoughts
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local breadth = ctx.breadth or 3
    local depth = ctx.depth or 3
    local beam_width = ctx.beam_width or 2

    -- Each beam entry: { path = {step1, step2, ...}, score = N }
    local beams = { { path = {}, score = 0 } }

    for d = 1, depth do
        local candidates = {}

        for _, beam in ipairs(beams) do
            local thoughts = generate_thoughts(task, beam.path, breadth)

            for _, thought in ipairs(thoughts) do
                local score = evaluate_thought(task, beam.path, thought)
                local new_path = {}
                for _, s in ipairs(beam.path) do
                    new_path[#new_path + 1] = s
                end
                new_path[#new_path + 1] = thought

                candidates[#candidates + 1] = {
                    path = new_path,
                    score = score,
                }
            end
        end

        -- Prune: keep top beam_width candidates
        table.sort(candidates, function(a, b) return a.score > b.score end)
        beams = {}
        for i = 1, math.min(beam_width, #candidates) do
            beams[#beams + 1] = candidates[i]
        end

        alc.log("info", string.format(
            "tot: depth %d/%d — %d candidates, kept %d (best score: %d)",
            d, depth, #candidates, #beams, beams[1] and beams[1].score or 0
        ))
    end

    -- Synthesize final answer from best path
    local best = beams[1]
    local path_text = ""
    for i, step in ipairs(best.path) do
        path_text = path_text .. string.format("Step %d: %s\n", i, step)
    end

    local conclusion = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Best reasoning path (score: %d/10):\n%s\n"
                .. "Synthesize these reasoning steps into a clear, comprehensive answer.",
            task, best.score, path_text
        ),
        { system = "You are an expert synthesizer. Produce a thorough, well-structured answer.", max_tokens = 600 }
    )

    -- Build all paths for transparency
    local explored_paths = {}
    for i, beam in ipairs(beams) do
        explored_paths[#explored_paths + 1] = {
            rank = i,
            path = beam.path,
            score = beam.score,
        }
    end

    ctx.result = {
        conclusion = conclusion,
        best_path = best.path,
        best_score = best.score,
        explored_paths = explored_paths,
        tree_stats = {
            depth = depth,
            breadth = breadth,
            beam_width = beam_width,
        },
    }
    return ctx
end

return M
