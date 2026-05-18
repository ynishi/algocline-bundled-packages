--- tot(ToT) — beam-search tree-of-thought reasoning over branching thought paths
---
--- Explores multiple reasoning paths by generating candidate thoughts at each
--- depth level, scoring them, and pruning to the top-scoring beams. Synthesizes
--- the best beam path into a final answer.
---
--- ## Usage
---
--- ```lua
--- local tot = require("tot")
--- return tot.run(ctx)
--- ```
---
--- ## Algorithm
---
--- Given a task and beam parameters (breadth B, depth D, beam width K):
---
--- 1. At each depth d ∈ {1..D}, for every surviving beam, generate B candidate
---    thoughts via `alc.llm` (thought generation prompt).
--- 2. Score each candidate thought with a separate `alc.llm` call that rates
---    logical soundness and progress on a 1-10 scale.
--- 3. Prune all candidates to the top-K by score (beam search step).
--- 4. After D rounds, synthesize the best-scored beam path into a conclusion
---    via a final `alc.llm` call.
---
--- Beam search complexity: O(D × K × B) LLM calls for generation +
--- O(D × K × B) calls for scoring = O(D × K × B) total.
---
--- ## Theoretical foundations
---
--- Yao et al. (2023) show that deliberate search over a tree of thoughts
--- outperforms linear chain-of-thought (CoT) on tasks requiring exploration,
--- strategic look-ahead, or backtracking. The beam-search variant implemented
--- here approximates the BFS/DFS variants in the paper with a fixed-width
--- pruning step that trades completeness for bounded LLM call count.
---
--- ## References
---
--- - Yao, S., Yu, D., Zhao, J., Shafran, I., Griffiths, T. L., Cao, Y.,
---   and Narasimhan, K. (2023). "Tree of Thoughts: Deliberate Problem Solving
---   with Large Language Models". arXiv:2305.10601.
---   https://arxiv.org/abs/2305.10601

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "tot",
    version = "0.1.0",
    description = "Tree-of-Thought — branching reasoning with evaluation and pruning",
    category = "reasoning",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("The problem to solve"),
                breadth    = T.number:is_optional():describe("Thoughts generated per beam node (default: 3)"),
                depth      = T.number:is_optional():describe("Maximum tree depth (default: 3)"),
                beam_width = T.number:is_optional():describe("Branches kept after pruning (default: 2)"),
            }),
            result = T.shape({
                conclusion     = T.string:describe("Synthesized final answer from the best-scored beam path"),
                best_path      = T.array_of(T.string):describe("Best beam path: ordered reasoning steps"),
                best_score     = T.number:describe("Score of the best beam (1-10)"),
                explored_paths = T.array_of(T.shape({
                    rank  = T.number:describe("1-based rank among surviving beams (1 = best score)"),
                    path  = T.array_of(T.string):describe("Ordered reasoning steps for this beam"),
                    score = T.number:describe("Aggregate score of this beam path (1-10)"),
                })):describe("All surviving beams, rank-ordered by score"),
                tree_stats     = T.shape({
                    depth      = T.number:describe("Search depth used"),
                    breadth    = T.number:describe("Thoughts generated per node"),
                    beam_width = T.number:describe("Beam width (branches kept after pruning)"),
                }):describe("Configuration echo for traceability"),
            }),
        },
    },
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

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
