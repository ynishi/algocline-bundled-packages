--- Maieutic — recursive explanation tree with logical consistency filtering
---
--- Given a proposition, generates supporting and opposing explanations
--- recursively (depth-limited tree), then checks logical consistency
--- between parent-child pairs to filter contradictions.
---
--- Based on: Jung et al., "Maieutic Prompting: Logically Consistent
--- Reasoning with Recursive Explanations" (2022, arXiv:2205.11822)
---
--- Usage:
---   local maieutic = require("maieutic")
---   return maieutic.run(ctx)
---
--- ctx.proposition (required): The claim to analyze
--- ctx.max_depth: Tree depth (default: 2)
--- ctx.gen_tokens: Max tokens per explanation (default: 300)
--- ctx.consistency_tokens: Max tokens per consistency check (default: 100)

local M = {}

---@type AlcMeta
M.meta = {
    name = "maieutic",
    version = "0.1.0",
    description = "Maieutic prompting — recursive explanation tree with logical consistency verification",
    category = "reasoning",
}

--- Generate supporting and opposing explanations for a proposition.
local function generate_explanations(proposition, gen_tokens)
    local results = alc.map({ "support", "oppose" }, function(stance)
        return alc.llm(
            string.format(
                "Proposition: \"%s\"\n\n"
                    .. "Provide a clear, specific explanation that %sS this proposition.\n"
                    .. "State it as a factual claim that can itself be evaluated as true or false.",
                proposition, stance:upper()
            ),
            {
                system = string.format(
                    "You are generating a %sing explanation. "
                        .. "The explanation must be a concrete, verifiable claim — "
                        .. "not an opinion or vague statement.",
                    stance
                ),
                max_tokens = gen_tokens,
            }
        )
    end)
    return results[1], results[2]
end

--- Check logical consistency between parent and child propositions.
--- Returns "consistent", "contradictory", or "independent".
local function check_consistency(parent, child, relation, consistency_tokens)
    local verdict = alc.llm(
        string.format(
            "Parent proposition: \"%s\"\n"
                .. "Child proposition (%s): \"%s\"\n\n"
                .. "The child is supposed to %s the parent.\n\n"
                .. "Are these logically consistent?\n"
                .. "- CONSISTENT: the child genuinely %ss the parent\n"
                .. "- CONTRADICTORY: the child actually undermines its stated relation\n"
                .. "- INDEPENDENT: the child is irrelevant to the parent\n\n"
                .. "Answer with one word: CONSISTENT, CONTRADICTORY, or INDEPENDENT.",
            parent, relation, child, relation, relation
        ),
        {
            system = "You are a logic evaluator. Assess whether the stated "
                .. "logical relationship actually holds. Be strict.",
            max_tokens = consistency_tokens,
        }
    )

    if verdict:match("CONTRADICTORY") then
        return "contradictory"
    elseif verdict:match("INDEPENDENT") then
        return "independent"
    else
        return "consistent"
    end
end

--- Build explanation tree recursively.
local function build_tree(proposition, depth, max_depth, gen_tokens, consistency_tokens)
    local node = {
        proposition = proposition,
        depth = depth,
        children = {},
    }

    if depth >= max_depth then
        return node
    end

    local support, oppose = generate_explanations(proposition, gen_tokens)

    -- Check consistency of each child with parent
    local support_status = check_consistency(
        proposition, support, "support", consistency_tokens
    )
    local oppose_status = check_consistency(
        proposition, oppose, "oppose", consistency_tokens
    )

    local support_node = {
        proposition = support,
        relation = "support",
        consistency = support_status,
        depth = depth + 1,
        children = {},
    }

    local oppose_node = {
        proposition = oppose,
        relation = "oppose",
        consistency = oppose_status,
        depth = depth + 1,
        children = {},
    }

    -- Only recurse into consistent nodes
    if support_status == "consistent" and depth + 1 < max_depth then
        support_node = build_tree(support, depth + 1, max_depth, gen_tokens, consistency_tokens)
        support_node.relation = "support"
        support_node.consistency = support_status
    end

    if oppose_status == "consistent" and depth + 1 < max_depth then
        oppose_node = build_tree(oppose, depth + 1, max_depth, gen_tokens, consistency_tokens)
        oppose_node.relation = "oppose"
        oppose_node.consistency = oppose_status
    end

    node.children = { support_node, oppose_node }

    alc.log("info", string.format(
        "maieutic: depth=%d, support=%s, oppose=%s",
        depth, support_status, oppose_status
    ))

    return node
end

--- Count consistent/contradictory/independent nodes in tree.
local function count_statuses(node)
    local counts = { consistent = 0, contradictory = 0, independent = 0 }

    local function walk(n)
        if n.consistency then
            counts[n.consistency] = (counts[n.consistency] or 0) + 1
        end
        for _, child in ipairs(n.children or {}) do
            walk(child)
        end
    end

    walk(node)
    return counts
end

--- Collect consistent support/oppose leaf propositions.
local function collect_evidence(node)
    local support = {}
    local oppose = {}

    local function walk(n)
        if n.relation and n.consistency == "consistent" then
            if n.relation == "support" then
                support[#support + 1] = n.proposition
            elseif n.relation == "oppose" then
                oppose[#oppose + 1] = n.proposition
            end
        end
        for _, child in ipairs(n.children or {}) do
            walk(child)
        end
    end

    walk(node)
    return support, oppose
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local proposition = ctx.proposition or error("ctx.proposition is required")
    local max_depth = ctx.max_depth or 2
    local gen_tokens = ctx.gen_tokens or 300
    local consistency_tokens = ctx.consistency_tokens or 100

    -- Build explanation tree
    local tree = build_tree(proposition, 0, max_depth, gen_tokens, consistency_tokens)
    local counts = count_statuses(tree)
    local support_evidence, oppose_evidence = collect_evidence(tree)

    -- Final synthesis based on consistent evidence
    local evidence_text = ""
    if #support_evidence > 0 then
        evidence_text = evidence_text .. "Supporting evidence:\n"
        for i, e in ipairs(support_evidence) do
            evidence_text = evidence_text .. string.format("  %d. %s\n", i, e)
        end
    end
    if #oppose_evidence > 0 then
        evidence_text = evidence_text .. "Opposing evidence:\n"
        for i, e in ipairs(oppose_evidence) do
            evidence_text = evidence_text .. string.format("  %d. %s\n", i, e)
        end
    end

    local synthesis = alc.llm(
        string.format(
            "Original proposition: \"%s\"\n\n"
                .. "After recursive analysis, the following logically consistent "
                .. "evidence was found:\n\n%s\n"
                .. "(%d contradictory and %d independent claims were filtered out.)\n\n"
                .. "Based ONLY on the consistent evidence above, "
                .. "what is your assessment of the original proposition?\n"
                .. "VERDICT: [likely true | likely false | insufficient evidence]\n"
                .. "REASONING: [explanation]",
            proposition, evidence_text, counts.contradictory, counts.independent
        ),
        {
            system = "You are a logical reasoner. Weigh the consistent evidence "
                .. "from both sides. Do not introduce new evidence — only reason "
                .. "about what was presented.",
            max_tokens = gen_tokens,
        }
    )

    local verdict = synthesis:match("VERDICT:%s*(.-)%s*\n") or "unknown"

    ctx.result = {
        verdict = verdict:lower(),
        synthesis = synthesis,
        tree = tree,
        evidence = {
            support = support_evidence,
            oppose = oppose_evidence,
        },
        consistency = counts,
    }
    return ctx
end

return M
