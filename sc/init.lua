--- SC — Self-Consistency: independent sampling with majority vote
--- Samples multiple reasoning paths for the same problem,
--- then selects the most consistent answer by majority voting.
---
--- Based on: Wang et al., "Self-Consistency Improves Chain of Thought
--- Reasoning in Language Models" (2022, arXiv:2203.11171)
---
--- Usage:
---   local sc = require("sc")
---   return sc.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n: Number of reasoning paths to sample (default: 5)
--- ctx.temperature_hint: Hint text for diversity (default: varies per sample)
--- ctx.gen_tokens: Max tokens per reasoning path (default: 400). Controls
---     how long each independent chain-of-thought can be. Setting this too
---     low truncates reasoning and lowers per-agent accuracy p, which
---     directly weakens Condorcet guarantees for downstream consumers.
--- ctx.extract_tokens: Max tokens for the per-path answer extraction step
---     (default: 100). Keep this small — the extraction prompt asks for
---     ONE short sentence, so more tokens waste budget without improving
---     the vote signal.
--- ctx.consensus_tokens: Max tokens for the final LLM-side vote-count
---     synthesis (default: 300). The structured `vote_counts` field is
---     computed independently, so this only affects the human-readable
---     `consensus` string.

local M = {}

---@type AlcMeta
M.meta = {
    name = "sc",
    version = "0.1.0",
    description = "Independent multi-path sampling with majority vote aggregation",
    category = "aggregation",
}

--- Extract a concise final answer from a reasoning chain.
local function extract_answer(reasoning, task, extract_tokens)
    return alc.llm(
        string.format(
            "Original question: %s\n\nReasoning:\n%s\n\nExtract ONLY the final answer in one short sentence. No explanation.",
            task, reasoning
        ),
        {
            system = "Extract the final answer concisely. One sentence max.",
            max_tokens = extract_tokens,
        }
    )
end

--- Trim leading/trailing whitespace and strip trailing punctuation.
--- Preserves original casing (used for display / downstream prompts).
local function clean_answer(s)
    if type(s) ~= "string" then return "" end
    local t = s:gsub("^%s+", ""):gsub("%s+$", "")
    t = t:gsub("%s+", " ")
    t = t:gsub("[%.%!%?%,%;%:]+$", "")
    return t
end

--- Normalize an answer string for vote counting.
--- Lowercase on top of clean_answer.
local function normalize_for_vote(s)
    return clean_answer(s):lower()
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n or 5
    local gen_tokens = ctx.gen_tokens or 400
    local extract_tokens = ctx.extract_tokens or 100
    local consensus_tokens = ctx.consensus_tokens or 300

    -- Diversity hints to encourage different reasoning paths
    local diversity_hints = {
        "Think step by step carefully.",
        "Approach this from first principles.",
        "Consider an alternative perspective.",
        "Work backwards from the expected outcome.",
        "Break this into smaller sub-problems.",
        "Use an analogy to reason about this.",
        "Consider edge cases and exceptions first.",
    }

    -- Count LLM calls during execution rather than computing it post-hoc.
    -- This stays correct if any branch ever changes (e.g. caching the
    -- extract step, or making consensus conditional).
    local total_llm_calls = 0

    -- Sample N independent reasoning paths
    local paths = {}
    for i = 1, n do
        local hint = diversity_hints[((i - 1) % #diversity_hints) + 1]
        local reasoning = alc.llm(
            string.format(
                "Question: %s\n\n%s Show your reasoning, then give a clear final answer.",
                task, hint
            ),
            {
                system = "You are a careful reasoner. Think through the problem thoroughly before answering.",
                max_tokens = gen_tokens,
            }
        )
        total_llm_calls = total_llm_calls + 1
        local answer = extract_answer(reasoning, task, extract_tokens)
        total_llm_calls = total_llm_calls + 1
        paths[i] = { reasoning = reasoning, answer = answer }
    end

    -- Ask LLM to cluster answers and pick the majority
    local answers_list = ""
    for i, p in ipairs(paths) do
        answers_list = answers_list .. string.format("Path %d answer: %s\n", i, p.answer)
    end

    local consensus = alc.llm(
        string.format(
            "Question: %s\n\nMultiple reasoning paths produced these answers:\n%s\n"
                .. "Group similar answers together. Which answer appears most frequently? "
                .. "State the majority answer and the vote count (e.g., '3 out of 5 paths agreed').",
            task, answers_list
        ),
        {
            system = "You are a precise vote counter. Identify the majority answer. Be exact.",
            max_tokens = consensus_tokens,
        }
    )
    total_llm_calls = total_llm_calls + 1

    -- Build vote distribution from extracted answers for downstream consumers
    -- (recipe_safe_panel, inverse_u, calibrate) that need the raw vote signal
    -- rather than only the LLM-synthesized consensus string.
    --
    -- For `answer` (the representative string passed to downstream prompts)
    -- we use the clean_answer'd form of the first raw match, not the raw
    -- string. This guarantees downstream consumers see "Tokyo" rather than
    -- either "Tokyo." or "tokyo" depending on sampling order.
    local votes = {}
    local vote_counts = {}
    local first_clean_by_norm = {}
    for i, p in ipairs(paths) do
        local norm = normalize_for_vote(p.answer)
        votes[i] = norm
        vote_counts[norm] = (vote_counts[norm] or 0) + 1
        if first_clean_by_norm[norm] == nil then
            first_clean_by_norm[norm] = clean_answer(p.answer)
        end
    end

    -- Majority answer: highest count, tie-broken by first occurrence.
    local majority_norm, majority_count = nil, 0
    for i = 1, #paths do
        local norm = votes[i]
        local c = vote_counts[norm]
        if c > majority_count then
            majority_norm, majority_count = norm, c
        end
    end
    local answer = majority_norm and first_clean_by_norm[majority_norm] or nil

    ctx.result = {
        consensus = consensus,
        answer = answer,
        answer_norm = majority_norm,
        paths = paths,
        votes = votes,
        vote_counts = vote_counts,
        n_sampled = n,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    clean_answer = clean_answer,
    normalize_for_vote = normalize_for_vote,
}

return M
