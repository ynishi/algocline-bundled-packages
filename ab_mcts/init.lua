--- ab_mcts — Adaptive Branching Monte Carlo Tree Search
---
--- Extends standard MCTS by dynamically deciding at each node whether to
--- explore wider (generate new candidates) or deeper (refine existing ones).
--- Uses Thompson Sampling with Beta posteriors instead of UCB1, enabling
--- principled exploration-exploitation balance that adapts to problem structure.
---
--- Key difference from mcts: standard MCTS uses UCB1 with fixed branching.
--- AB-MCTS introduces a virtual GEN node at each position — when Thompson
--- Sampling selects GEN over existing children, a new candidate is generated
--- (wider). When an existing child is selected, it is refined (deeper).
---
--- Based on: Inoue et al., "Wider or Deeper? Scaling LLM Inference-Time
--- Compute with Adaptive Branching Tree Search"
--- (NeurIPS 2025 Spotlight, arXiv:2503.04412)
---
--- Pipeline (2*budget + 1 LLM calls):
---   For each iteration:
---     Selection   — Thompson Sampling down the tree
---     Expansion   — generate new or refine existing (1 LLM call)
---     Evaluation  — score the result (1 LLM call)
---     Backprop    — update Beta posteriors along the path
---   Final: synthesize best answer
---
--- Usage:
---   local ab_mcts = require("ab_mcts")
---   return ab_mcts.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.budget: Total expansion iterations (default: 8)
--- ctx.max_depth: Maximum tree depth (default: 3)
--- ctx.alpha_prior: Beta prior alpha (default: 1.0)
--- ctx.beta_prior: Beta prior beta (default: 1.0)
--- ctx.gen_tokens: Max tokens for generation/refinement (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "ab_mcts",
    version = "0.1.0",
    description = "Adaptive Branching MCTS — Thompson Sampling with dynamic "
        .. "wider/deeper decisions. GEN node mechanism for principled branching. "
        .. "Consistently outperforms standard MCTS and repeated sampling.",
    category = "reasoning",
}

-- ─── Beta distribution sampling ───

--- Simple Beta distribution sampling via Jöhnk's method.
--- For alpha, beta >= 1, this provides accurate samples.
local function sample_beta(alpha, beta)
    -- Use the approximation: Beta(a,b) ≈ Gamma(a)/(Gamma(a)+Gamma(b))
    -- For a,b >= 1, we use the ratio of gamma variates via Marsaglia-Tsang
    -- Simplified: use the mean + noise approach for practical purposes

    if alpha <= 0 then alpha = 0.01 end
    if beta <= 0 then beta = 0.01 end

    -- Jöhnk's method for Beta sampling
    local function gamma_sample(shape)
        if shape >= 1 then
            -- Marsaglia-Tsang method
            local d = shape - 1.0 / 3.0
            local c = 1.0 / math.sqrt(9.0 * d)
            while true do
                local x, v
                repeat
                    x = math.random() * 2 - 1
                    -- Box-Muller for standard normal
                    local u1 = math.random()
                    local u2 = math.random()
                    x = math.sqrt(-2 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2)
                    v = (1 + c * x) ^ 3
                until v > 0
                local u = math.random()
                if u < 1 - 0.0331 * x * x * x * x then
                    return d * v
                end
                if math.log(u + 1e-10) < 0.5 * x * x + d * (1 - v + math.log(v + 1e-10)) then
                    return d * v
                end
            end
        else
            -- For shape < 1: use gamma(shape+1) * U^(1/shape)
            return gamma_sample(shape + 1) * math.random() ^ (1.0 / shape)
        end
    end

    local x = gamma_sample(alpha)
    local y = gamma_sample(beta)
    return x / (x + y + 1e-10)
end

-- ─── Node structure ───

local function new_node(thought, parent, depth)
    return {
        thought = thought,
        children = {},
        parent = parent,
        depth = depth or 0,
        -- Beta posteriors for this node's children quality
        gen_alpha = 1.0,   -- GEN node alpha (generate new)
        gen_beta = 1.0,    -- GEN node beta
        best_score = 0,
        visits = 0,
    }
end

--- Build path from root to node.
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
    local parts = {}
    for i, step in ipairs(path) do
        parts[#parts + 1] = string.format("Step %d: %s", i, step)
    end
    return table.concat(parts, "\n")
end

-- ─── Core operations ───

--- Selection: Thompson Sampling down the tree.
--- Returns (node, action) where action is "gen" or a child index.
local function select_node(root, alpha_prior, beta_prior)
    local node = root

    while true do
        if #node.children == 0 then
            return node, "gen"
        end

        -- Sample from GEN node's Beta posterior
        local gen_sample = sample_beta(node.gen_alpha, node.gen_beta)

        -- Sample from each child's Beta posterior
        local best_child_idx = nil
        local best_child_sample = -1

        for i, child in ipairs(node.children) do
            local child_alpha = alpha_prior + child.best_score * child.visits
            local child_beta = beta_prior + (1 - child.best_score) * child.visits
            local child_sample = sample_beta(child_alpha, child_beta)

            if child_sample > best_child_sample then
                best_child_sample = child_sample
                best_child_idx = i
            end
        end

        -- GEN wins → generate new child (go wider)
        if gen_sample > best_child_sample then
            return node, "gen"
        end

        -- Existing child wins → go deeper
        node = node.children[best_child_idx]
    end
end

--- Expand: generate a new reasoning step or refine existing.
local function expand_gen(task, parent_node, gen_tokens)
    local path = path_to_node(parent_node)
    local path_text = format_path(path)

    local existing_hint = ""
    if #parent_node.children > 0 then
        local existing = {}
        for i, child in ipairs(parent_node.children) do
            existing[#existing + 1] = string.format(
                "  [Approach %d]: %s", i,
                child.thought:sub(1, 100)
            )
        end
        existing_hint = "\n\nExisting approaches at this point:\n"
            .. table.concat(existing, "\n")
            .. "\n\nGenerate a DIFFERENT approach."
    end

    local prompt
    if #path == 0 then
        prompt = string.format(
            "Task: %s\n%s\n\n"
                .. "Propose an initial reasoning approach. Be specific and concrete.",
            task, existing_hint
        )
    else
        prompt = string.format(
            "Task: %s\n\nReasoning so far:\n%s\n%s\n\n"
                .. "Propose the next reasoning step. Be specific and concrete.",
            task, path_text, existing_hint
        )
    end

    local thought = alc.llm(prompt, {
        system = "You are a creative problem solver. Generate a distinct, "
            .. "insightful reasoning step.",
        max_tokens = gen_tokens,
    })

    local child = new_node(thought, parent_node, parent_node.depth + 1)
    parent_node.children[#parent_node.children + 1] = child
    return child
end

--- Evaluate: score a complete reasoning path.
local function evaluate(task, node)
    local path = path_to_node(node)
    local path_text = format_path(path)

    local score_str = alc.llm(
        string.format(
            "Task: %s\n\nReasoning path:\n%s\n\n"
                .. "Rate this reasoning on a 0-10 scale:\n"
                .. "- Correctness and logical soundness\n"
                .. "- Completeness toward solving the task\n"
                .. "- Quality of reasoning\n\n"
                .. "Reply with ONLY the number.",
            task, path_text
        ),
        { system = "You are a rigorous evaluator. Just the number.", max_tokens = 10 }
    )

    local score = alc.parse_score(score_str)
    return score / 10.0  -- Normalize to [0, 1]
end

--- Backpropagation: update Beta posteriors along the path.
local function backpropagate(node, score, parent_of_expansion)
    -- Update the GEN node posterior of the parent where expansion happened
    if parent_of_expansion then
        parent_of_expansion.gen_alpha = parent_of_expansion.gen_alpha + score
        parent_of_expansion.gen_beta = parent_of_expansion.gen_beta + (1 - score)
    end

    -- Update visits and best_score up the tree
    local current = node
    while current do
        current.visits = current.visits + 1
        if score > current.best_score then
            current.best_score = score
        end
        current = current.parent
    end
end

--- Find the best leaf node by best_score.
local function find_best_leaf(root)
    local best_node = root
    local best_score = -1

    local function traverse(node)
        if #node.children == 0 and node.best_score > best_score then
            best_score = node.best_score
            best_node = node
        end
        for _, child in ipairs(node.children) do
            traverse(child)
        end
    end

    traverse(root)
    return best_node
end

--- Count total nodes in tree.
local function count_nodes(root)
    local count = 1
    for _, child in ipairs(root.children) do
        count = count + count_nodes(child)
    end
    return count
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local budget = ctx.budget or 8
    local max_depth = ctx.max_depth or 3
    local alpha_prior = ctx.alpha_prior or 1.0
    local beta_prior = ctx.beta_prior or 1.0
    local gen_tokens = ctx.gen_tokens or 400

    local root = new_node(nil, nil, 0)
    root.visits = 1

    local wider_count = 0
    local deeper_count = 0

    for i = 1, budget do
        -- 1. Selection — Thompson Sampling
        local selected_node, action = select_node(root, alpha_prior, beta_prior)

        -- Depth limit: force wider at max_depth
        if selected_node.depth >= max_depth and action ~= "gen" then
            action = "gen"
            -- Go back up to find a shallower node
            local node = selected_node
            while node.depth >= max_depth and node.parent do
                node = node.parent
            end
            selected_node = node
        end

        -- Track wider vs deeper decisions
        if action == "gen" then
            wider_count = wider_count + 1
        else
            deeper_count = deeper_count + 1
        end

        -- 2. Expansion
        local new_node_result = expand_gen(task, selected_node, gen_tokens)

        -- 3. Evaluation
        local score = evaluate(task, new_node_result)

        -- 4. Backpropagation
        backpropagate(new_node_result, score, selected_node)

        alc.log("info", string.format(
            "ab_mcts: iteration %d/%d — %s at depth %d, score: %.2f",
            i, budget,
            action == "gen" and "WIDER" or "DEEPER",
            new_node_result.depth, score
        ))
    end

    -- Find best path and synthesize
    local best = find_best_leaf(root)
    local best_path = path_to_node(best)
    local path_text = format_path(best_path)

    alc.log("info", string.format(
        "ab_mcts: search complete — %d wider, %d deeper, best score: %.2f",
        wider_count, deeper_count, best.best_score
    ))

    local conclusion = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Best reasoning path found (score: %.1f/10):\n%s\n\n"
                .. "Synthesize these reasoning steps into a clear, comprehensive answer.",
            task, best.best_score * 10, path_text
        ),
        {
            system = "You are an expert synthesizer. Produce a thorough, "
                .. "well-structured answer.",
            max_tokens = gen_tokens + 200,
        }
    )

    ctx.result = {
        answer = conclusion,
        best_path = best_path,
        best_score = best.best_score,
        tree_stats = {
            total_nodes = count_nodes(root),
            budget = budget,
            wider_decisions = wider_count,
            deeper_decisions = deeper_count,
            max_depth = max_depth,
            branching_ratio = wider_count / (wider_count + deeper_count + 1e-10),
        },
    }
    return ctx
end

return M
