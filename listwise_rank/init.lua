--- listwise_rank — Zero-shot Listwise Reranking with Sliding Window
---
--- Ranks N pre-existing candidates by asking the LLM to output a permutation
--- of all candidates in a single call. For N exceeding the context window,
--- a sliding-window strategy progressively reranks overlapping windows from
--- the tail back to the head, merging the partial permutations into a final
--- order.
---
--- Key difference from pointwise scoring (the dominant failure mode):
---   pointwise — asks the LLM to output an absolute score (e.g. 0-10) per
---               candidate. The LLM's number-generation prior anchors output
---               to the middle of the scale (typically 5-8), compressing
---               variance and making any fixed threshold either kill nothing
---               or kill everything. The "calibration problem" of LLM-as-Judge.
---   listwise — asks the LLM to output an ORDERING. Only the relative order
---               is asked, so calibration is moot. Empirically dominates
---               pointwise on TREC-DL and BEIR.
---
--- Mathematical advantage:
---   Resolves the calibration problem by reformulating ranking as a permutation
---   generation task instead of an absolute scoring task. The LLM never has
---   to commit to a numeric value; it only commits to an order.
---
--- Empirical results (from RankGPT, Sun et al.):
---   - GPT-4 with RankGPT achieves SOTA zero-shot reranking on TREC-DL19/20.
---   - Outperforms supervised baselines (monoT5-3B) and pointwise LLM
---     baselines on BEIR benchmarks.
---   - Knowledge distillable into smaller open-source models (RankZephyr,
---     RankVicuna) which retain most of the effectiveness.
---
--- Based on:
---   Sun et al., "Is ChatGPT Good at Search? Investigating Large Language
---     Models as Re-Ranking Agents" (EMNLP 2023, arXiv:2304.09542)
---   Ma et al., "Zero-Shot Listwise Document Reranking with a Large Language
---     Model" (arXiv:2305.02156)
---   Pradeep et al., "RankZephyr: Effective and Robust Zero-Shot Listwise
---     Reranking is a Breeze!" (arXiv:2312.02724)
---
--- Usage:
---   local lr = require("listwise_rank")
---   return lr.run(ctx)
---
--- ctx.task (required): The criterion for ranking (e.g. "relevance to X",
---     "quality of business idea", "factual accuracy")
--- ctx.candidates (required): array of candidate texts to rank
--- ctx.top_k: how many to keep (default N — full ranked list)
--- ctx.window_size: sliding-window size (default 20). For N <= window_size
---     the entire ranking is done in 1 LLM call. For N > window_size, the
---     RankGPT sliding-window strategy is applied.
--- ctx.step: window stride (default ⌈window_size/2⌉)
--- ctx.gen_tokens: max tokens for the ranking response (default 400)

local M = {}

---@type AlcMeta
M.meta = {
    name = "listwise_rank",
    version = "0.1.0",
    description = "Zero-shot listwise reranking — RankGPT-style permutation "
        .. "generation in 1 LLM call. Resolves the calibration problem of "
        .. "pointwise scoring. Sliding window for large N.",
    category = "selection",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            result = "listwise_ranked",
        },
    },
}

--- Format a window of candidates as numbered passages.
local function format_window(window_candidates)
    local parts = {}
    for i, c in ipairs(window_candidates) do
        parts[#parts + 1] = string.format("[%d] %s", i, c)
    end
    return table.concat(parts, "\n\n")
end

--- Parse the LLM's permutation response. Expected format: "[3] > [1] > [4] > [2] > [5]"
--- Returns a list of 1-based indices in ranked order. Robust to:
---   - missing brackets ("3 > 1 > 4")
---   - comma separators ("3, 1, 4")
---   - newlines and prose ("Ranking: 3 > 1 > ...")
---   - missing indices (filled in at the end in original order)
---   - duplicates (first occurrence kept)
local function parse_permutation(raw, n)
    local order = {}
    local seen = {}
    -- Pass 1: prefer bracketed [N] tokens (the prompt-mandated format).
    -- This blocks numerals in surrounding prose (e.g. "Ranking 4 candidates")
    -- from polluting the ranking.
    for num in raw:gmatch("%[(%d+)%]") do
        local idx = tonumber(num)
        if idx and idx >= 1 and idx <= n and not seen[idx] then
            order[#order + 1] = idx
            seen[idx] = true
        end
    end
    -- Pass 2 (diagnostic fallback): only if NO bracketed token was found,
    -- accept bare integers at word boundaries. This keeps the package usable
    -- with weaker LLMs that drop the brackets, without silently overriding
    -- a partially-correct bracketed response.
    if #order == 0 then
        for num in raw:gmatch("%f[%d](%d+)%f[%D]") do
            local idx = tonumber(num)
            if idx and idx >= 1 and idx <= n and not seen[idx] then
                order[#order + 1] = idx
                seen[idx] = true
            end
        end
    end
    -- Fill in any missing indices at the end (preserving original order).
    -- Only candidates the LLM did not mention at all are appended; we never
    -- fabricate a ranking position for them.
    for i = 1, n do
        if not seen[i] then
            order[#order + 1] = i
        end
    end
    return order
end

--- Rank a single window of candidates with one LLM call.
--- Returns a list of 1-based indices INTO window_candidates in ranked order
--- (best first).
local function rank_window(task, window_candidates, gen_tokens)
    local n = #window_candidates
    local body = format_window(window_candidates)
    local prompt = string.format(
        "Ranking criterion: %s\n\n"
            .. "I will provide you with %d candidates, each indicated by a "
            .. "number identifier []. Rank them based on the criterion above, "
            .. "from MOST to LEAST.\n\n"
            .. "%s\n\n"
            .. "Output the ranking as a strict descending order using the "
            .. "format [a] > [b] > [c] > ... covering ALL %d candidates. "
            .. "Output ONLY the ranking line, no explanation.",
        task, n, body, n
    )
    local raw = alc.llm(prompt, {
        system = "You are a precise ranking assistant. Output only the ranking line.",
        max_tokens = gen_tokens,
    })
    return parse_permutation(raw, n)
end

--- Sliding-window reranking: single tail-to-head pass per RankGPT
--- (Sun et al. 2023). Each window's reranked order is written back to the
--- global order array. The original RankGPT design is single-pass; later
--- work (RankZephyr et al.) preserves this choice.
---
--- Head-coverage invariant: every window must have exactly `window_size`
--- items (assuming N >= window_size). Without clamping, the final iteration
--- can shrink to a tiny tail window that leaves the head under-ranked
--- (e.g. N=8, w=3, s=2 without clamp ends with window [1,2] — items 1 and 3
--- never co-appear). We clamp `last` to at least `window_size` so the final
--- head window is [1, window_size].
---
--- @param task string
--- @param order table  -- 1..N indices into the original candidates array
--- @param candidates table
--- @param window_size number
--- @param step number
--- @param gen_tokens number
--- @return number   total LLM calls used
local function sliding_window_rerank(task, order, candidates, window_size, step, gen_tokens)
    local calls = 0
    local n_total = #order
    -- If N < window_size the caller should have taken the single-window path.
    if n_total < window_size then window_size = n_total end
    -- Start from the tail and walk back toward the head one stride at a time.
    -- Window is the inclusive range [first, last].
    local last = n_total
    while true do
        local first = math.max(1, last - window_size + 1)
        if last - first + 1 < 2 then break end

        local window_cands = {}
        for k = first, last do
            window_cands[#window_cands + 1] = candidates[order[k]]
        end
        local local_order = rank_window(task, window_cands, gen_tokens)
        calls = calls + 1

        -- Write back: position (first + i - 1) gets the original index
        -- order[first + local_order[i] - 1].
        local snapshot = {}
        for i = first, last do snapshot[i] = order[i] end
        for i, lo in ipairs(local_order) do
            order[first + i - 1] = snapshot[first + lo - 1]
        end

        if first == 1 then break end
        -- Clamp so the final window is a full head window [1, window_size].
        last = math.max(window_size, last - step)
    end
    return calls
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local candidates = ctx.candidates
        or error("ctx.candidates (array of strings) is required")
    if type(candidates) ~= "table" or #candidates < 2 then
        error("ctx.candidates must be a non-empty array (>= 2)", 2)
    end
    local n = #candidates
    local top_k = ctx.top_k or n
    if top_k < 1 then top_k = 1 end
    if top_k > n then top_k = n end
    local window_size = ctx.window_size or 20
    if window_size < 2 then window_size = 2 end
    local step = ctx.step or math.max(1, math.ceil(window_size / 2))
    local gen_tokens = ctx.gen_tokens or 400

    -- Initial order = identity
    local order = {}
    for i = 1, n do order[i] = i end

    local total_calls
    if n <= window_size then
        -- Single call covers everything
        local local_order = rank_window(task, candidates, gen_tokens)
        for i = 1, n do order[i] = local_order[i] end
        total_calls = 1
    else
        total_calls = sliding_window_rerank(
            task, order, candidates, window_size, step, gen_tokens
        )
    end

    -- Build ranked output
    local ranked = {}
    for rank = 1, n do
        local idx = order[rank]
        ranked[rank] = {
            rank = rank,
            index = idx,
            text = candidates[idx],
        }
    end

    local kept = {}
    local killed = {}
    for i = 1, n do
        if i <= top_k then
            kept[#kept + 1] = ranked[i]
        else
            killed[#killed + 1] = ranked[i]
        end
    end

    alc.log("info", string.format(
        "listwise_rank: ranked %d candidates in %d LLM call(s); "
            .. "kept top %d, killed %d",
        n, total_calls, top_k, #killed
    ))

    ctx.result = {
        ranked = ranked,
        top_k = kept,
        killed = killed,
        best = ranked[1].text,
        best_index = ranked[1].index,
        n_candidates = n,
        total_llm_calls = total_calls,
    }
    require("alc_shapes").assert_dev(ctx.result, "listwise_ranked", "listwise_rank.run")
    return ctx
end

return M
