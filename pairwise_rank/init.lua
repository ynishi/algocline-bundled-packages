--- pairwise_rank — Pairwise Ranking Prompting (PRP)
---
--- Ranks N candidates by asking the LLM "is A or B better?" for pairs and
--- aggregating the wins (Copeland-style score). PRP is the most accurate
--- known LLM-as-judge method when the LLM is small or the task is hard,
--- because it asks the LLM the simplest possible question (a single
--- pairwise preference) at the cost of more LLM calls.
---
--- Key difference from listwise_rank / setwise_rank:
---   listwise_rank — 1 LLM call to rank everything. Cheapest. Limited by
---                   context window. Can suffer from list-position bias.
---   setwise_rank  — Tournament with set comparisons of size k. O(N log N)
---                   calls. Mid-cost, mid-accuracy.
---   pairwise_rank — Pure pairwise. O(N²) "all-pairs" or O(N log N)
---                   "tournament" call modes. Highest accuracy when N is
---                   modest. Position bias mitigated by querying both
---                   orderings (A,B) and (B,A) and counting wins.
---
--- Mathematical advantage:
---   By only ever asking the LLM to compare two items at a time, PRP
---   reduces the LLM's task complexity to its minimum, sidestepping
---   numeric calibration AND list-positional reasoning. The paper
---   explicitly identifies "resolving the calibration issue" as PRP's
---   motivation.
---
--- Empirical results (from PRP, Qin et al.):
---   - Flan-UL2 (20B params) with PRP-Allpair matches GPT-4 (~50× larger)
---     on TREC-DL 2019 and 2020.
---   - Outperforms pointwise LLM rankers by >10% NDCG@10 on average across
---     7 BEIR tasks.
---   - Outperforms blackbox ChatGPT listwise reranking by 4.2% NDCG@10.
---
--- Based on:
---   Qin et al., "Large Language Models are Effective Text Rankers with
---     Pairwise Ranking Prompting" (NAACL 2024 Findings, arXiv:2306.17563)
---
--- Modes:
---   "allpair" — every unordered pair compared in BOTH directions to
---               cancel position bias. 2 * C(N,2) = N*(N-1) LLM calls.
---               Most accurate. Use for N ≤ 12.
---   "sorting" — heap-style insertion sort using pairwise comparisons.
---               O(N log N) calls in expectation. Use for larger N.
---
--- Usage:
---   local pr = require("pairwise_rank")
---   return pr.run(ctx)
---
--- ctx.task (required): The criterion for comparison
--- ctx.candidates (required): array of candidate texts
--- ctx.top_k: how many to keep (default N — full ranked list)
--- ctx.method: "allpair" | "sorting" (default "allpair")
--- ctx.gen_tokens: max tokens per pairwise judgment (default 20)

local M = {}

---@type AlcMeta
M.meta = {
    name = "pairwise_rank",
    version = "0.1.0",
    description = "Pairwise Ranking Prompting (PRP) — pairwise LLM-as-judge "
        .. "comparison with bidirectional position-bias cancellation. "
        .. "Highest-accuracy LLM reranker on TREC-DL/BEIR. Resolves the "
        .. "calibration problem.",
    category = "selection",
    result_shape = "pairwise_ranked",
}

--- Ask the LLM which of two candidates is better. Returns one of:
---   "A"  — first is better
---   "B"  — second is better
---   "tie" — explicit tie
--- Errors out if the response cannot be parsed (no silent default — a misread
--- verdict would systematically corrupt the Copeland aggregation).
local function compare_pair(task, a_text, b_text, gen_tokens)
    local prompt = string.format(
        "Comparison criterion: %s\n\n"
            .. "Candidate A:\n%s\n\n"
            .. "Candidate B:\n%s\n\n"
            .. "Decide which candidate is better. Reply on a single line in "
            .. "EXACTLY this format (no other text):\n"
            .. "Verdict: A\n  or\nVerdict: B\n  or\nVerdict: tie",
        task, a_text, b_text
    )
    local raw = alc.llm(prompt, {
        system = "You are a strict pairwise judge. Output only the Verdict line.",
        max_tokens = gen_tokens,
    })
    -- 1. Strict: look for "Verdict: <token>" first.
    local v = raw:match("[Vv]erdict:%s*(%a+)")
    if v then
        v = v:lower()
        if v == "a" then return "A" end
        if v == "b" then return "B" end
        if v:find("tie") then return "tie" end
    end
    -- 2. Lenient fallback: standalone A / B at a word boundary
    --    (excludes "a" inside "answer", "B" inside "Both", etc).
    local upper = raw:upper()
    local has_A = upper:find("%f[%a]A%f[%A]") ~= nil
    local has_B = upper:find("%f[%a]B%f[%A]") ~= nil
    if has_A and not has_B then return "A" end
    if has_B and not has_A then return "B" end
    if raw:lower():find("tie") then return "tie" end
    -- 3. Unparseable — fail loudly. Silent tie would bias every comparison.
    error(
        "pairwise_rank: cannot parse verdict from LLM response: "
            .. tostring(raw):sub(1, 200),
        2
    )
end

--- Bidirectional comparison: query (A,B) and (B,A), aggregate to remove
--- position bias. Returns an integer score in {-2,-1,0,+1,+2} from i's
--- perspective:
---   +2 = i wins both orderings
---   +1 = i wins one ordering, the other is tie
---    0 = both tie, or split (one each)
---   -1 = j wins one ordering, the other is tie
---   -2 = j wins both orderings
local function bidir_compare(task, i_text, j_text, gen_tokens)
    local r1 = compare_pair(task, i_text, j_text, gen_tokens)
    local r2 = compare_pair(task, j_text, i_text, gen_tokens)
    -- r1: A=i, B=j ; r2: A=j, B=i
    local i_pts = 0
    if r1 == "A" then i_pts = i_pts + 1 end
    if r1 == "B" then i_pts = i_pts - 1 end
    if r2 == "B" then i_pts = i_pts + 1 end
    if r2 == "A" then i_pts = i_pts - 1 end
    -- Detect position-bias split: both verdicts non-tie but disagree.
    -- (r1, r2) ∈ { (A,A), (B,B) } means the LLM picked the SAME slot
    -- regardless of which candidate occupied it — pure position bias.
    local split = (r1 == "A" and r2 == "A") or (r1 == "B" and r2 == "B")
    local both_tie = (r1 == "tie" and r2 == "tie")
    return i_pts, 2, split, both_tie
end

-- ─── Mode: allpair ───
-- Every unordered pair in both directions. Wins are aggregated into a
-- Copeland-style score. Returns ranking + total calls.

local function allpair_rank(task, candidates, gen_tokens)
    local n = #candidates
    local score = {}
    for i = 1, n do score[i] = 0 end
    local calls = 0
    local splits = 0
    local ties = 0
    for i = 1, n do
        for j = i + 1, n do
            local diff, c, split, both_tie = bidir_compare(
                task, candidates[i], candidates[j], gen_tokens
            )
            calls = calls + c
            score[i] = score[i] + diff
            score[j] = score[j] - diff
            if split then splits = splits + 1 end
            if both_tie then ties = ties + 1 end
        end
    end
    return score, calls, splits, ties
end

-- ─── Mode: sorting ───
-- Insertion sort using bidirectional pairwise comparisons. O(N log N) in the
-- best case, O(N²) worst case but with much smaller constant than allpair.
-- Returns a `rank_inverse` score (rank-1 → n, rank-n → 1) consumed by the
-- shared ranking step in M.run; see `score_semantics` in result.

local function sorting_rank(task, candidates, gen_tokens)
    local n = #candidates
    local sorted_idx = { 1 }  -- 1-based original indices, in ranked order
    local calls = 0
    local splits = 0
    local ties = 0
    for k = 2, n do
        -- Insert k into sorted_idx using binary search by pairwise compare
        local lo, hi = 1, #sorted_idx + 1
        while lo < hi do
            local mid = (lo + hi) // 2
            local diff, c, split, both_tie = bidir_compare(
                task, candidates[k], candidates[sorted_idx[mid]], gen_tokens
            )
            calls = calls + c
            if split then splits = splits + 1 end
            if both_tie then ties = ties + 1 end
            if diff > 0 then
                hi = mid       -- k is better → insert before mid
            elseif diff < 0 then
                lo = mid + 1   -- k is worse → search right
            else
                lo = mid + 1   -- tie → break to the right
            end
        end
        table.insert(sorted_idx, lo, k)
    end
    -- Sorting mode produces a rank-inverse score (n, n-1, ..., 1), NOT a
    -- Copeland score. Returned as `rank_inverse` to keep the field
    -- semantically distinct from allpair's Copeland `score`.
    local rank_inverse = {}
    for i = 1, n do rank_inverse[i] = 0 end
    for rank, idx in ipairs(sorted_idx) do
        rank_inverse[idx] = (n - rank + 1)
    end
    return rank_inverse, calls, splits, ties
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
    local method = ctx.method or "allpair"
    local gen_tokens = ctx.gen_tokens or 20

    if method ~= "allpair" and method ~= "sorting" then
        error("pairwise_rank: method must be 'allpair' or 'sorting'", 2)
    end

    local scores, calls, splits, ties
    local score_semantics
    if method == "allpair" then
        scores, calls, splits, ties = allpair_rank(task, candidates, gen_tokens)
        score_semantics = "copeland"
    else
        scores, calls, splits, ties = sorting_rank(task, candidates, gen_tokens)
        score_semantics = "rank_inverse"
    end

    -- Rank by score (descending). Stable secondary key = original index.
    local ranking_pairs = {}
    for i = 1, n do
        ranking_pairs[i] = { index = i, score = scores[i] }
    end
    table.sort(ranking_pairs, function(a, b)
        if a.score == b.score then return a.index < b.index end
        return a.score > b.score
    end)

    local ranked = {}
    for rank, p in ipairs(ranking_pairs) do
        ranked[rank] = {
            rank = rank,
            index = p.index,
            score = p.score,
            text = candidates[p.index],
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
        "pairwise_rank[%s]: ranked %d candidates in %d LLM call(s); "
            .. "kept top %d; position-bias splits=%d both-tie=%d",
        method, n, calls, top_k, splits, ties
    ))

    ctx.result = {
        ranked = ranked,
        top_k = kept,
        killed = killed,
        best = ranked[1].text,
        best_index = ranked[1].index,
        method = method,
        score_semantics = score_semantics,
        n_candidates = n,
        total_llm_calls = calls,
        position_bias_splits = splits,
        both_tie_pairs = ties,
    }
    require("alc_shapes").assert_dev(ctx.result, "pairwise_ranked", "pairwise_rank.run")
    return ctx
end

return M
