--- MCTS — Monte Carlo Tree Search reasoning
--- Applies MCTS to LLM reasoning: selection (UCB1), expansion (generate),
--- simulation (rollout to conclusion), backpropagation (update scores).
--- Explores deep reasoning trees more efficiently than exhaustive search.
---
--- Based on: Hao et al., "Reasoning with Language Model is Planning with
--- World Model" (RAP, 2023, arXiv:2305.14992)
---
--- Usage:
---   local mcts = require("mcts")
---   return mcts.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.iterations: Number of MCTS iterations (default: 6)
--- ctx.max_depth: Maximum tree depth per rollout (default: 3)
--- ctx.exploration: UCB1 exploration constant (default: 1.41)

local M = {}

M.meta = {
    name = "mcts",
    version = "0.1.0",
    description = "Monte Carlo Tree Search — selection, expansion, simulation, backpropagation for reasoning",
    category = "reasoning",
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

--- EXPANSION: Generate a child thought from this node.
local function expand(task, node)
    local path = path_to_node(node)
    local path_text = format_path(path)

    local existing = ""
    if #node.children > 0 then
        for i, child in ipairs(node.children) do
            existing = existing .. string.format("  [Already explored %d]: %s\n", i, child.thought)
        end
    end

    local prompt
    if #path == 0 then
        prompt = string.format(
            "Task: %s\n\n"
                .. "%s"
                .. "Propose a first reasoning step. Be specific and concrete. 1-3 sentences.",
            task,
            #node.children > 0 and ("Approaches already explored:\n" .. existing .. "\nPropose a DIFFERENT approach.\n\n") or ""
        )
    else
        prompt = string.format(
            "Task: %s\n\nReasoning so far:\n%s\n"
                .. "%s"
                .. "What is the next reasoning step? Be specific and concrete. 1-3 sentences.",
            task, path_text,
            #node.children > 0 and ("Next steps already explored:\n" .. existing .. "\nPropose a DIFFERENT next step.\n\n") or ""
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

    return tonumber(score_str:match("%d+")) or 5
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

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local iterations = ctx.iterations or 6
    local max_depth = ctx.max_depth or 3
    local C = ctx.exploration or 1.41

    local root = new_node(nil, nil)
    root.visits = 1  -- avoid log(0)

    for i = 1, iterations do
        -- 1. Selection
        local leaf = select_node(root, C)

        -- 2. Expansion
        local child = expand(task, leaf)

        -- 3. Simulation
        local score = simulate(task, child, max_depth)

        -- 4. Backpropagation
        backpropagate(child, score)

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

return M
