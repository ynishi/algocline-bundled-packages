--- setwise_rank — Setwise Tournament Reranking
---
--- Ranks N candidates by repeatedly asking the LLM "which is the best
--- among these k items?" and advancing winners through tournament rounds.
--- Each comparison spans a SET (size k) rather than a pair, dramatically
--- reducing LLM calls vs pairwise while keeping the LLM task simpler than
--- listwise (it only picks ONE best, not a full permutation).
---
--- Position on the cost/accuracy spectrum:
---   listwise_rank — 1 LLM call to rank ALL. Cheapest. Limited by context.
---                   List-position bias risk.
---   setwise_rank  — Tournament with set comparisons of size k.
---                   O(top_k * N / k) LLM calls. Mid-cost / mid-accuracy.
---                   Sweet spot when N is moderate (10–50) and you need
---                   stronger guarantees than a single listwise pass.
---   pairwise_rank — Pure pairwise. O(N²) or O(N log N). Highest accuracy.
---
--- Mathematical motivation:
---   Setwise reduces the LLM's burden to selecting the single best from a
---   small set — a task substantially easier than producing a full ordering
---   and free of the absolute-score calibration problem of pointwise
---   judging. Empirically Zhuang et al. show setwise matches or beats
---   listwise on TREC-DL and BEIR while using comparable or fewer tokens.
---
--- Empirical results (Zhuang et al., SIGIR 2024):
---   - Setwise with Flan-T5 matches RankGPT (listwise) on TREC-DL19/20.
---   - More efficient than pairwise; comparable accuracy to listwise with
---     better robustness to position bias.
---
--- Based on:
---   Zhuang et al., "A Setwise Approach for Effective and Highly Efficient
---     Zero-shot Ranking with Large Language Models" (SIGIR 2024,
---     arXiv:2310.09497)
---
--- Algorithm (iterative top-k extraction):
---   active ← {1..N}
---   for rank = 1 .. top_k do
---     while #active > 1 do
---       partition active into groups of size set_size (last group may be smaller)
---       for each group of size >= 2: LLM picks the best index
---       active ← winners ∪ singleton-groups
---     end
---     ranked[rank] ← active[1]
---     remove ranked[rank] from the original pool, restart with remaining
---   end
---
--- Usage:
---   local sr = require("setwise_rank")
---   return sr.run(ctx)
---
--- ctx.task (required): The criterion for ranking
--- ctx.candidates (required): array of candidate texts
--- ctx.top_k: how many to keep (default N — full ranked list)
--- ctx.set_size: tournament group size (default 4)
--- ctx.gen_tokens: max tokens per pick response (default 20)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "setwise_rank",
    version = "0.1.0",
    description = "Setwise tournament reranking — LLM picks the best from "
        .. "small sets and winners advance. Mid-cost/mid-accuracy sweet "
        .. "spot between listwise and pairwise. Resolves calibration issue.",
    category = "selection",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("Ranking criterion"),
                candidates = T.array_of(T.string):describe("Candidate texts to rank (>= 2)"),
                top_k      = T.number:is_optional():describe("How many to keep (default: N = full ranked list)"),
                set_size   = T.number:is_optional():describe("Tournament group size (default: 4)"),
                gen_tokens = T.number:is_optional():describe("Max tokens per pick response (default: 20)"),
            }),
            result = T.shape({
                ranked          = T.array_of(T.shape({
                    rank  = T.number,
                    index = T.number,
                    text  = T.string,
                })):describe("Full ranked list: top_k winners followed by unranked tail"),
                top_k           = T.array_of(T.shape({
                    rank  = T.number,
                    index = T.number,
                    text  = T.string,
                })):describe("Winners (the top-k portion of ranked)"),
                killed          = T.array_of(T.shape({
                    rank  = T.number,
                    index = T.number,
                    text  = T.string,
                })):describe("Unranked tail (candidates not extracted into top_k)"),
                best            = T.string:describe("Text of the #1 candidate"),
                best_index      = T.number:describe("Original 1-based index of the #1 candidate"),
                set_size        = T.number:describe("Tournament group size actually used"),
                n_candidates    = T.number:describe("Total number of input candidates"),
                total_llm_calls = T.number:describe("Count of pick_best LLM calls performed"),
            }),
        },
    },
}

--- Ask the LLM to pick the index of the best candidate in a set.
--- Returns a 1-based index INTO the group (1..#group). Errors on parse
--- failure — silent fallback would systematically bias the tournament
--- toward the first slot and contradict setwise's position-bias claim.
local function pick_best(task, group_texts, gen_tokens)
    local parts = {}
    for i, t in ipairs(group_texts) do
        parts[#parts + 1] = string.format("[%d] %s", i, t)
    end
    local body = table.concat(parts, "\n\n")
    local prompt = string.format(
        "Selection criterion: %s\n\n"
            .. "I will provide you with %d candidates, each indicated by a "
            .. "number identifier []. Pick the SINGLE BEST candidate "
            .. "according to the criterion above.\n\n"
            .. "%s\n\n"
            .. "Reply with EXACTLY one token: the number identifier of the "
            .. "best candidate (e.g. '2'). No explanation.",
        task, #group_texts, body
    )
    local raw = alc.llm(prompt, {
        system = "You are a precise selector. Output only the number.",
        max_tokens = gen_tokens,
    })
    -- Extract the first integer in range
    for num in raw:gmatch("(%d+)") do
        local idx = tonumber(num)
        if idx and idx >= 1 and idx <= #group_texts then
            return idx
        end
    end
    error(
        "setwise_rank: cannot parse pick from LLM response: "
            .. tostring(raw):sub(1, 200),
        2
    )
end

--- Run a single tournament over an active set of original indices.
--- Returns the winning original index and the LLM call count consumed.
local function tournament(task, active, candidates, set_size, gen_tokens)
    local calls = 0
    local current = {}
    for i, v in ipairs(active) do current[i] = v end

    while #current > 1 do
        local next_round = {}
        local i = 1
        while i <= #current do
            local last = math.min(i + set_size - 1, #current)
            if last == i then
                -- Singleton — auto-advance
                next_round[#next_round + 1] = current[i]
            else
                local group_idx = {}
                local group_text = {}
                for k = i, last do
                    group_idx[#group_idx + 1] = current[k]
                    group_text[#group_text + 1] = candidates[current[k]]
                end
                local pick = pick_best(task, group_text, gen_tokens)
                calls = calls + 1
                next_round[#next_round + 1] = group_idx[pick]
            end
            i = last + 1
        end
        current = next_round
    end
    return current[1], calls
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
    local set_size = ctx.set_size or 4
    if set_size < 2 then set_size = 2 end
    local gen_tokens = ctx.gen_tokens or 20

    -- active = remaining original indices
    local active = {}
    for i = 1, n do active[i] = i end

    local ranked = {}
    local total_calls = 0

    for rank = 1, top_k do
        if #active == 0 then break end
        if #active == 1 then
            ranked[rank] = {
                rank = rank,
                index = active[1],
                text = candidates[active[1]],
            }
            table.remove(active, 1)
        else
            local winner, calls = tournament(
                task, active, candidates, set_size, gen_tokens
            )
            total_calls = total_calls + calls
            ranked[rank] = {
                rank = rank,
                index = winner,
                text = candidates[winner],
            }
            -- Remove winner from active
            for i = 1, #active do
                if active[i] == winner then
                    table.remove(active, i)
                    break
                end
            end
        end
    end

    -- Build the killed tail (remaining unranked candidates) and the
    -- full ranked view = kept ++ killed.
    local killed = {}
    for i, idx in ipairs(active) do
        killed[i] = {
            rank = #ranked + i,
            index = idx,
            text = candidates[idx],
        }
    end

    local full_ranked = {}
    for i, r in ipairs(ranked) do full_ranked[i] = r end
    for i, r in ipairs(killed) do full_ranked[#full_ranked + 1] = r end

    alc.log("info", string.format(
        "setwise_rank: ranked top %d of %d candidates in %d LLM call(s) "
            .. "(set_size=%d)",
        top_k, n, total_calls, set_size
    ))

    ctx.result = {
        ranked = full_ranked,
        top_k = ranked,
        killed = killed,
        best = ranked[1] and ranked[1].text or nil,
        best_index = ranked[1] and ranked[1].index or nil,
        set_size = set_size,
        n_candidates = n,
        total_llm_calls = total_calls,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
