--- GoT — Graph of Thoughts reasoning
--- Models reasoning as a DAG (Directed Acyclic Graph) enabling operations
--- impossible in tree structures: aggregation of multiple thought paths,
--- self-refinement loops, and hierarchical decomposition with merge.
---
--- Key difference from ToT: GoT supports Aggregate (many-to-one merge)
--- where independent reasoning branches combine into a superior synthesis.
--- ToT is limited to tree structures where branches never reconverge.
---
--- Based on: Besta et al., "Graph of Thoughts: Solving Elaborate Problems
--- with Large Language Models" (AAAI 2024, arXiv:2308.09687)
---
--- Operations:
---   Generate   — branch one thought into k new thoughts (1-to-many)
---   Aggregate  — merge k thoughts into one synthesis (many-to-1, GoT-unique)
---   Refine     — improve a thought in-place (self-loop)
---   Score      — evaluate thought quality (LLM or custom function)
---   KeepBest   — prune to top-n thoughts by score
---
--- Pipeline (default GoO):
---   Generate(k) → Score → KeepBest(n) → Refine → Aggregate → Refine → Answer
---
--- Usage:
---   local got = require("got")
---   return got.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.k_generate: Branches per Generate (default: 3)
--- ctx.keep_best: Nodes to keep after pruning (default: 2)
--- ctx.max_refine: Max refinement attempts (default: 2)
--- ctx.gen_tokens: Max tokens for generation (default: 300)
--- ctx.agg_tokens: Max tokens for aggregation (default: 500)
--- ctx.refine_tokens: Max tokens for refinement (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "got",
    version = "0.1.0",
    description = "Graph of Thoughts — DAG-structured reasoning with aggregation, "
        .. "refinement, and multi-path synthesis. Enables thought merging "
        .. "impossible in tree-based approaches (ToT).",
    category = "reasoning",
}

-- ─── Graph primitives ───

local function new_graph()
    return {
        nodes = {},
        next_id = 1,
    }
end

local function create_node(graph, state, origin_op, parent_ids)
    local id = graph.next_id
    graph.next_id = id + 1
    local node = {
        id = id,
        state = state,
        score = nil,
        origin_op = origin_op,
        parents = parent_ids or {},
        children = {},
    }
    graph.nodes[id] = node
    -- Update parent references
    for _, pid in ipairs(node.parents) do
        local parent = graph.nodes[pid]
        if parent then
            parent.children[#parent.children + 1] = id
        end
    end
    return node
end

--- Collect leaf nodes (nodes with no children).
local function get_leaves(graph)
    local leaves = {}
    for _, node in pairs(graph.nodes) do
        if #node.children == 0 then
            leaves[#leaves + 1] = node
        end
    end
    return leaves
end

-- ─── Operations ───

--- Generate: branch one node into k new thoughts (parallel).
local function op_generate(graph, nodes, k, task, gen_tokens)
    local all_new = {}

    for _, node in ipairs(nodes) do
        local indices = {}
        for i = 1, k do indices[i] = i end

        local results = alc.map(indices, function(i)
            local existing_hint = ""
            if i > 1 then
                existing_hint = "\n\nProvide a DIFFERENT approach from previous ones."
            end

            return alc.llm(
                string.format(
                    "Task: %s\n\n"
                        .. "Current reasoning state:\n\"\"\"\n%s\n\"\"\"\n\n"
                        .. "Generate reasoning approach #%d of %d.%s\n"
                        .. "Be specific and concrete. Explore a distinct angle.",
                    task, node.state, i, k, existing_hint
                ),
                {
                    system = "You are a creative problem solver. Each thought must "
                        .. "explore a genuinely different reasoning direction.",
                    max_tokens = gen_tokens,
                }
            )
        end)

        for _, result in ipairs(results) do
            local child = create_node(graph, result, "generate", { node.id })
            all_new[#all_new + 1] = child
        end
    end

    return all_new
end

--- Aggregate: merge multiple thoughts into one synthesis (GoT-unique).
local function op_aggregate(graph, nodes, task, agg_tokens)
    local thoughts_text = ""
    for i, node in ipairs(nodes) do
        thoughts_text = thoughts_text .. string.format(
            "--- Thought %d (score: %s) ---\n%s\n\n",
            i, node.score and string.format("%.1f", node.score) or "?",
            node.state
        )
    end

    local merged = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Multiple independent reasoning paths:\n\n%s"
                .. "Synthesize the strongest elements from ALL paths into a single, "
                .. "superior reasoning. Combine complementary insights, resolve "
                .. "contradictions by analyzing which reasoning is more sound, "
                .. "and produce a unified solution that is better than any individual path.",
            task, thoughts_text
        ),
        {
            system = "You are an expert synthesizer. Combine the best elements "
                .. "of multiple reasoning approaches. The result must be strictly "
                .. "better than any single input.",
            max_tokens = agg_tokens,
        }
    )

    local parent_ids = {}
    for _, n in ipairs(nodes) do parent_ids[#parent_ids + 1] = n.id end
    return create_node(graph, merged, "aggregate", parent_ids)
end

--- Refine: improve a thought in-place (self-loop).
local function op_refine(graph, node, task, refine_tokens)
    local improved = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Current reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Critically review and improve this reasoning:\n"
                .. "- Fix any logical errors or gaps\n"
                .. "- Strengthen weak arguments with evidence\n"
                .. "- Add depth where the reasoning is superficial\n"
                .. "- Ensure the conclusion follows from the premises",
            task, node.state
        ),
        {
            system = "You are a rigorous reviewer improving reasoning quality. "
                .. "Be specific about what you changed and why.",
            max_tokens = refine_tokens,
        }
    )

    node.state = improved
    node.origin_op = "refine"
    return node
end

--- Score: evaluate thought quality via LLM (parallel).
local function op_score(graph, nodes, task)
    local scores = alc.map(nodes, function(node)
        return alc.llm(
            string.format(
                "Task: %s\n\nReasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Rate this reasoning on a 1-10 scale:\n"
                    .. "- Correctness: Is the logic sound?\n"
                    .. "- Completeness: Does it address the full task?\n"
                    .. "- Insight: Does it show genuine understanding?\n\n"
                    .. "Reply with ONLY the number.",
                task, node.state
            ),
            { system = "You are a critical evaluator. Just the number.", max_tokens = 10 }
        )
    end)

    for i, node in ipairs(nodes) do
        node.score = alc.parse_score(scores[i])
    end
end

--- KeepBest: prune to top-n by score.
local function op_keep_best(graph, nodes, n)
    table.sort(nodes, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    local kept = {}
    local removed = {}
    for i, node in ipairs(nodes) do
        if i <= n then
            kept[#kept + 1] = node
        else
            removed[#removed + 1] = node
        end
    end

    -- Mark removed nodes as non-leaves by giving them a sentinel
    for _, node in ipairs(removed) do
        node.pruned = true
    end

    return kept
end

-- ─── Main ───

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local k_generate = ctx.k_generate or 3
    local keep_n = ctx.keep_best or 2
    local max_refine = ctx.max_refine or 2
    local gen_tokens = ctx.gen_tokens or 300
    local agg_tokens = ctx.agg_tokens or 500
    local refine_tokens = ctx.refine_tokens or 400

    local graph = new_graph()

    -- Create root node
    create_node(graph, task, "init", {})

    -- ─── Phase 1: Generate — branch into k diverse thoughts ───
    alc.log("info", string.format("got: Phase 1 — Generate (%d branches)", k_generate))
    local roots = get_leaves(graph)
    local generated = op_generate(graph, roots, k_generate, task, gen_tokens)

    -- ─── Phase 2: Score all generated thoughts ───
    alc.log("info", string.format("got: Phase 2 — Score (%d nodes)", #generated))
    op_score(graph, generated, task)

    -- ─── Phase 3: KeepBest — prune to top-n ───
    alc.log("info", string.format("got: Phase 3 — KeepBest (%d → %d)", #generated, keep_n))
    local kept = op_keep_best(graph, generated, keep_n)

    local score_summary = {}
    for _, node in ipairs(kept) do
        score_summary[#score_summary + 1] = string.format(
            "node %d: %.0f/10", node.id, node.score or 0
        )
    end
    alc.log("info", "got: kept nodes — " .. table.concat(score_summary, ", "))

    -- ─── Phase 4: Refine — improve each kept thought ───
    for r = 1, max_refine do
        alc.log("info", string.format("got: Phase 4 — Refine round %d/%d", r, max_refine))
        for _, node in ipairs(kept) do
            op_refine(graph, node, task, refine_tokens)
        end
    end

    -- ─── Phase 5: Aggregate — merge all kept thoughts (GoT-unique) ───
    alc.log("info", string.format(
        "got: Phase 5 — Aggregate (%d thoughts → 1)", #kept
    ))
    local merged = op_aggregate(graph, kept, task, agg_tokens)

    -- ─── Phase 6: Final Refine on aggregated result ───
    alc.log("info", "got: Phase 6 — Final Refine")
    op_refine(graph, merged, task, refine_tokens)

    -- ─── Phase 7: Synthesize final answer ───
    alc.log("info", "got: Phase 7 — Synthesize final answer")
    local conclusion = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Best synthesized reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Produce a clear, comprehensive final answer based on "
                .. "this reasoning.",
            task, merged.state
        ),
        {
            system = "You are an expert. Produce a thorough, well-structured answer.",
            max_tokens = agg_tokens,
        }
    )

    -- Build graph stats
    local node_count = 0
    local op_counts = {}
    for _, node in pairs(graph.nodes) do
        node_count = node_count + 1
        op_counts[node.origin_op] = (op_counts[node.origin_op] or 0) + 1
    end

    ctx.result = {
        answer = conclusion,
        aggregated_reasoning = merged.state,
        graph_stats = {
            total_nodes = node_count,
            operations = op_counts,
            branches_generated = k_generate,
            branches_kept = keep_n,
            refine_rounds = max_refine,
        },
    }
    return ctx
end

return M
