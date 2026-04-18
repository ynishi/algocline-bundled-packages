--- MCTS — Monte Carlo Tree Search reasoning
--- Applies MCTS to LLM reasoning: selection (UCB1), expansion (generate),
--- simulation (rollout to conclusion), backpropagation (update scores).
--- Explores deep reasoning trees more efficiently than exhaustive search.
---
--- Optional Reflection mechanism (ctx.reflection = true): when a simulation
--- scores below the reflection threshold, the LLM generates a 1-sentence
--- diagnosis of why that path failed. These reflections are accumulated and
--- injected into subsequent expansion prompts, helping the search avoid
--- repeating the same mistakes.
---
--- Based on:
---   [1] Hao et al. "Reasoning with Language Model is Planning with
---       World Model" (RAP, 2023, arXiv:2305.14992)
---   [2] Zhou et al. "Language Agent Tree Search Unifies Reasoning, Acting,
---       and Planning in Language Models" (LATS, ICML 2024, arXiv:2310.04406)
---   [3] Xu et al. "CogMCTS: Cognitive-Guided Monte Carlo Tree Search"
---       (2025, arXiv:2512.08609)
---
--- Usage:
---   local mcts = require("mcts")
---   return mcts.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.iterations: Number of MCTS iterations (default: 6)
--- ctx.max_depth: Maximum tree depth per rollout (default: 3)
--- ctx.exploration: UCB1 exploration constant (default: 1.41)
--- ctx.reflection: Enable reflection on low-score paths (default: false)
--- ctx.reflection_threshold: Score below which reflection triggers (default: 4)
--- ctx.max_reflections: Maximum stored reflections (default: 5)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "mcts",
    version = "0.1.0",
    description = "Monte Carlo Tree Search — selection, expansion, simulation, backpropagation for reasoning",
    category = "reasoning",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task                 = T.string:describe("The problem to solve"),
                iterations           = T.number:is_optional():describe("Number of MCTS iterations (default: 6)"),
                max_depth            = T.number:is_optional():describe("Maximum tree depth per rollout (default: 3)"),
                exploration          = T.number:is_optional():describe("UCB1 exploration constant C (default: √2 ≈ 1.41)"),
                reflection           = T.boolean:is_optional():describe("Enable reflection on low-score paths (default: false)"),
                reflection_threshold = T.number:is_optional():describe("Score below which reflection triggers (default: 4)"),
                max_reflections      = T.number:is_optional():describe("Maximum stored reflections (default: 5)"),
            }),
            result = T.shape({
                conclusion = T.string:describe("Synthesized final answer from the best path"),
                best_path = T.array_of(T.shape({
                    thought   = T.string:describe("Reasoning thought at this node"),
                    avg_score = T.number:describe("Average score across visits"),
                    visits    = T.number:describe("Visit count for this node"),
                })):describe("Best path from root to leaf"),
                total_iterations = T.number:describe("Iterations actually performed"),
                tree_stats = T.shape({
                    root_visits          = T.number:describe("Visit count at the root node"),
                    root_children        = T.number:describe("Number of direct children of root"),
                    exploration_constant = T.number:describe("UCB1 constant C used"),
                    max_depth            = T.number:describe("Max depth setting used"),
                }):describe("Tree-level statistics"),
            }),
        },
    },
}

--- Node structure:
--- { thought, children = {}, visits = 0, total_score = 0, parent = nil }

local function new_node(thought, parent)
    return {
        thought = thought,
        children = {},
        visits = 0,
        total_score = 0,
        parent = parent,
    }
end

--- UCB1 score for node selection.
local function ucb1_score(node, parent_visits, C)
    if node.visits == 0 then return math.huge end
    local exploit = node.total_score / node.visits
    local explore = C * math.sqrt(math.log(parent_visits + 1) / node.visits)
    return exploit + explore
end

--- Build the reasoning path from root to this node.
local function path_to_node(node)
    local path = {}
    local current = node
    while current and current.thought do
        table.insert(path, 1, current.thought)
        current = current.parent
    end
    return path
end

local function format_path(path)
    local text = ""
    for i, step in ipairs(path) do
        text = text .. string.format("Step %d: %s\n", i, step)
    end
    return text
end

--- SELECTION: Walk down tree using UCB1 to find most promising leaf.
local function select_node(root, C)
    local node = root
    while #node.children > 0 do
        local best_child = nil
        local best_score = -math.huge
        for _, child in ipairs(node.children) do
            local score = ucb1_score(child, node.visits, C)
            if score > best_score then
                best_score = score
                best_child = child
            end
        end
        node = best_child
    end
    return node
end

--- Generate a reflection from a low-scoring path.
local function reflect(task, path, score)
    return alc.llm(
        string.format(
            "Task: %s\n\nReasoning path (scored %d/10):\n%s\n\n"
                .. "In ONE sentence, explain why this reasoning path scored poorly. "
                .. "Focus on the key flaw or wrong assumption.",
            task, score, format_path(path)
        ),
        {
            system = "You are a concise diagnostician. One sentence only.",
            max_tokens = 80,
        }
    )
end

--- EXPANSION: Generate a child thought from this node.
--- reflection_buffer: optional list of past failure reflections to inject.
local function expand(task, node, reflection_buffer)
    local path = path_to_node(node)
    local path_text = format_path(path)

    local existing = ""
    if #node.children > 0 then
        for i, child in ipairs(node.children) do
            existing = existing .. string.format("  [Already explored %d]: %s\n", i, child.thought)
        end
    end

    -- Build reflection hint if available
    local reflection_hint = ""
    if reflection_buffer and #reflection_buffer > 0 then
        local items = {}
        for i, r in ipairs(reflection_buffer) do
            items[#items + 1] = string.format("  - %s", r)
        end
        reflection_hint = "\n\nLessons from failed paths (AVOID these mistakes):\n"
            .. table.concat(items, "\n") .. "\n"
    end

    local prompt
    if #path == 0 then
        prompt = string.format(
            "Task: %s\n\n"
                .. "%s%s"
                .. "Propose a first reasoning step. Be specific and concrete. 1-3 sentences.",
            task,
            #node.children > 0 and ("Approaches already explored:\n" .. existing .. "\nPropose a DIFFERENT approach.\n\n") or "",
            reflection_hint
        )
    else
        prompt = string.format(
            "Task: %s\n\nReasoning so far:\n%s\n"
                .. "%s%s"
                .. "What is the next reasoning step? Be specific and concrete. 1-3 sentences.",
            task, path_text,
            #node.children > 0 and ("Next steps already explored:\n" .. existing .. "\nPropose a DIFFERENT next step.\n\n") or "",
            reflection_hint
        )
    end

    local thought = alc.llm(prompt, {
        system = "You are a creative problem solver. Propose a distinct, insightful reasoning step.",
        max_tokens = 200,
    })

    local child = new_node(thought, node)
    node.children[#node.children + 1] = child
    return child
end

--- SIMULATION: Rollout from this node to a conclusion and score it.
local function simulate(task, node, max_depth)
    local path = path_to_node(node)

    -- Quick rollout: continue reasoning to a conclusion
    local remaining = max_depth - #path
    local rollout_path = {}
    for _, s in ipairs(path) do
        rollout_path[#rollout_path + 1] = s
    end

    if remaining > 0 then
        local rollout_text = format_path(rollout_path)
        local continuation = alc.llm(
            string.format(
                "Task: %s\n\nReasoning so far:\n%s\n"
                    .. "Continue this reasoning to a conclusion in %d more step(s). "
                    .. "Be concise — 1-2 sentences per step.",
                task, rollout_text, remaining
            ),
            {
                system = "You are a fast, focused reasoner. Reach a conclusion quickly.",
                max_tokens = 300,
            }
        )
        rollout_path[#rollout_path + 1] = continuation
    end

    -- Evaluate the complete reasoning path
    local full_path = format_path(rollout_path)
    local score_str = alc.llm(
        string.format(
            "Task: %s\n\nComplete reasoning path:\n%s\n"
                .. "Rate this reasoning on a 1-10 scale:\n"
                .. "- Correctness and logical soundness\n"
                .. "- Completeness of the solution\n"
                .. "- Quality of the final conclusion\n\n"
                .. "Reply with ONLY the number.",
            task, full_path
        ),
        { system = "You are a rigorous evaluator. Just the number.", max_tokens = 10 }
    )

    return alc.parse_score(score_str)
end

--- BACKPROPAGATION: Update scores from leaf to root.
local function backpropagate(node, score)
    local current = node
    while current do
        current.visits = current.visits + 1
        current.total_score = current.total_score + score
        current = current.parent
    end
end

--- Collect the best path through the tree by highest average score.
local function best_path_through(root)
    local path = {}
    local node = root
    while #node.children > 0 do
        local best_child = nil
        local best_avg = -math.huge
        for _, child in ipairs(node.children) do
            if child.visits > 0 then
                local avg = child.total_score / child.visits
                if avg > best_avg then
                    best_avg = avg
                    best_child = child
                end
            end
        end
        if not best_child then break end
        path[#path + 1] = {
            thought = best_child.thought,
            avg_score = best_avg,
            visits = best_child.visits,
        }
        node = best_child
    end
    return path
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local iterations = ctx.iterations or 6
    local max_depth = ctx.max_depth or 3
    local C = ctx.exploration or 1.41
    local use_reflection = ctx.reflection or false
    local reflection_threshold = ctx.reflection_threshold or 4
    local max_reflections = ctx.max_reflections or 5

    local root = new_node(nil, nil)
    root.visits = 1  -- avoid log(0)

    -- Reflection buffer (LATS-style): accumulates failure diagnoses
    local reflection_buffer = {}

    for i = 1, iterations do
        -- 1. Selection
        local leaf = select_node(root, C)

        -- 2. Expansion (inject reflections if enabled)
        local child = expand(
            task, leaf,
            use_reflection and reflection_buffer or nil
        )

        -- 3. Simulation
        local score = simulate(task, child, max_depth)

        -- 4. Backpropagation
        backpropagate(child, score)

        -- 5. Reflection (LATS extension): learn from low-scoring paths
        if use_reflection and score <= reflection_threshold then
            local child_path = path_to_node(child)
            local r = reflect(task, child_path, score)
            if #reflection_buffer >= max_reflections then
                table.remove(reflection_buffer, 1)  -- FIFO eviction
            end
            reflection_buffer[#reflection_buffer + 1] = r
            alc.log("info", string.format(
                "mcts: reflection added (score=%d, buffer=%d/%d)",
                score, #reflection_buffer, max_reflections
            ))
        end

        alc.log("info", string.format(
            "mcts: iteration %d/%d — expanded node at depth %d, rollout score: %d",
            i, iterations, #path_to_node(child), score
        ))
    end

    -- Extract best path and synthesize
    local best = best_path_through(root)
    local path_text = ""
    for i, step in ipairs(best) do
        path_text = path_text .. string.format(
            "Step %d (score: %.1f, visits: %d): %s\n",
            i, step.avg_score, step.visits, step.thought
        )
    end

    local conclusion = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Best reasoning path found by MCTS:\n%s\n"
                .. "Synthesize these reasoning steps into a clear, comprehensive answer.",
            task, path_text
        ),
        { system = "You are an expert synthesizer. Produce a thorough, well-structured answer.", max_tokens = 600 }
    )

    ctx.result = {
        conclusion = conclusion,
        best_path = best,
        total_iterations = iterations,
        tree_stats = {
            root_visits = root.visits,
            root_children = #root.children,
            exploration_constant = C,
            max_depth = max_depth,
        },
    }
    return ctx
end

-- Malli-style self-decoration: wrapper asserts ctx against
-- M.spec.entries.run.input and ret.result against .result when
-- ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
