--- speculative_rejection(SpeculativeRejection) — iterative reward-pruned best-of-N
---
--- Adapts Sun et al. NeurIPS 2024 "Fast Best-of-N Decoding via Speculative
--- Rejection" (arXiv:2410.20290, Algorithm 1) to the `alc.llm` text-generation
--- context. The paper's original scheme operates at token-level: N candidates
--- share the same GPU forward pass, a reward model scores each partial at
--- checkpoint token positions t_1, t_2, ..., and the bottom-alpha fraction is
--- rejected between checkpoints so that at end-of-decode only the strongest
--- candidate remains. The paper reports up to ~24x speedup vs vanilla
--- Best-of-N on LLM alignment benchmarks (Sun 2024 §5).
---
--- The adaptation here operates at **alc.llm call granularity** (not token
--- granularity — see Caveats). Each rejection round is one `alc.llm_batch`
--- generation/extension pass plus one `alc.llm` scoring pass. A final
--- `alc.llm` selector emits SELECTED + RATIONALE over whatever survives.
---
--- ## Usage
---
--- ```lua
--- local sr = require("speculative_rejection")
--- return sr.run({ task = "Prove the AM-GM inequality." })
--- ```
---
--- ## Algorithm
---
--- **Paper original (Sun 2024, Algorithm 1, token-level)**:
---
--- 1. Start with N candidates decoding in parallel (paper uses N=1000).
--- 2. At checkpoint token position t_1, a reward model scores every partial.
--- 3. Reject the bottom alpha fraction (alpha=0.5 in the paper, §4.1).
--- 4. Continue survivors to t_2, re-score, reject bottom alpha. Repeat.
--- 5. Return the surviving candidate with the highest final reward.
---
--- **Adaptation to alc.llm (call-level)**:
---
--- 1. Round 1 — `alc.llm_batch` generates N short partial completions
---    (default `partial_tokens = 100` tokens each).
--- 2. Round 1 scoring — a single `alc.llm` pass scores every partial 0-10
---    against `reward_rubric`.
--- 3. Reject the bottom `alpha` fraction of scored partials.
--- 4. Round 2..`rounds` — `alc.llm_batch` extends each surviving partial by
---    `extend_tokens` more tokens; re-score; reject bottom alpha.
--- 5. Final — one `alc.llm` selector pass emits SELECTED + RATIONALE over
---    the final survivors (may be one candidate; the call still runs to
---    produce a rationale for the caller).
---
--- Call budget = rounds x (1 alc.llm_batch + 1 alc.llm) + 1 alc.llm selector
--- = 3 x 2 + 1 = 7 calls at defaults. This is NOT a strict win over
--- `verify_select`'s 2 calls — see Comparison.
---
--- ## API
---
--- - `ctx.task`           — string, required. Empty / whitespace-only -> error.
--- - `ctx.n`              — number, optional. Initial candidate count
---   (default 8).
--- - `ctx.alpha`          — number, optional. Rejection ratio per round in
---   [0, 1] (default 0.5).
--- - `ctx.rounds`         — number, optional. Number of rejection stages
---   (default 3).
--- - `ctx.reward_rubric`  — string, optional. Scoring rubric injected verbatim
---   into every scoring prompt (default: generic quality rubric).
--- - `ctx.partial_tokens` — number, optional. Tokens per initial generation
---   (default 100).
--- - `ctx.extend_tokens`  — number, optional. Tokens added per extension round
---   (default 200).
---
--- Result (`ctx.result`):
--- - `selected`           — string, the winning full completion.
--- - `candidates_initial` — number, initial N.
--- - `candidates_final`   — number, how many candidates survived the final
---   round.
--- - `rejection_history`  — array, one entry per rejection round, in order.
---   Each entry is `{ round, survivors_before, survivors_after,
---   rejected_indices, scores }`. `rejected_indices` are ORIGINAL 1-based
---   indices into the initial batch (stable identity across rounds). `scores`
---   is the dense per-survivor score array from that round's reward pass.
--- - `rationale`          — string, the final selector's justification.
---
--- ## Comparison with related packages
---
--- vs `verify_select`: `verify_select` generates full N candidates then picks
--- the best in 2 calls (1 batch + 1 verifier). `speculative_rejection`
--- prunes iteratively so that losers do not consume extension-round tokens,
--- trading MORE sequential `alc.llm` calls (7 vs 2 at defaults) for FEWER
--- generation tokens spent on eventual losers. It is a win when generations
--- are long and losers can be identified early (rounds >= 2), a loss when
--- generations are already short (verify_select is cheaper end-to-end). Not
--- a strict Pareto improvement — pick per token-vs-latency budget.
---
--- vs `sc`: `sc` (self-consistency, Wang 2023) is majority vote over
--- identical answers, appropriate when the task admits a single canonical
--- answer that convergent sampling should hit. `speculative_rejection` is
--- quality-based selection for divergent, reward-scorable answers — the
--- adaptive-cost variant of `verify_select`.
---
--- vs `mbr_select`: `mbr_select` uses inter-candidate similarity (MBR).
--- `speculative_rejection` uses an external reward model score, and prunes
--- iteratively — orthogonal signal source, orthogonal cost profile.
---
--- ## Caveats
---
--- **Token-level to call-level adaptation (implementation choice)**. The
--- paper's central efficiency claim relies on token-level parallel decoding:
--- one shared GPU forward pass produces N partials simultaneously, so
--- rejecting half of them mid-decode literally halves subsequent compute.
--- `alc.llm` / `alc.llm_batch` are call-level primitives with no token-stream
--- access from the Lua host, so the adaptation collapses each "checkpoint"
--- into one `alc.llm_batch` + one `alc.llm` scoring pass. Consequently the
--- paper's headline speedup (~24x vs BoN) does NOT carry over verbatim; the
--- adaptation captures the pruning-early quality signal without the shared-
--- forward-pass compute savings. This is an unavoidable adaptation gap and
--- callers should understand the package as "iterative reward-pruned BoN at
--- LLM-call granularity", not a literal reproduction of Sun 2024.
---
--- **Diversity is host-side**. Each initial-batch item carries a distinct
--- system persona (candidate #i) to nudge divergence, but genuine sampling
--- diversity requires temperature > 0 on the host / provider side.
---
--- **Reward model quality dominates**. The rubric-based `alc.llm` scoring
--- pass is a soft reward model. If the reward LLM cannot reliably rank
--- partial responses against the rubric, aggressive alpha will prune good
--- candidates early. Start with alpha=0.5 (paper canonical) and tune based
--- on empirical retention behavior.
---
--- **Extension points (all optional, override at your own risk)**:
--- `ctx.n` (default 8; implementation choice — paper uses N=1000 for
--- token-level, at LLM-call granularity 8 is a practical starting cost),
--- `ctx.alpha` (default 0.5; Sun 2024 §4.1 canonical value — overriding
--- forfeits paper alignment), `ctx.rounds` (default 3; implementation choice
--- to bound `alc.llm_batch` cost), `ctx.reward_rubric` (default generic
--- quality rubric; override for domain-specific reward), `ctx.partial_tokens`
--- (default 100; implementation choice), `ctx.extend_tokens` (default 200;
--- implementation choice).
---
--- ## References
---
--- - Sun, H., Haider, M., Zhang, R., Yang, H., Qiu, J., Yin, M., Wang, M.,
---   Bartlett, P., Zanette, A. (2024). "Fast Best-of-N Decoding via
---   Speculative Rejection." NeurIPS 2024. arXiv:2410.20290. Algorithm 1
---   (rejection sampling schedule), §4.1 (alpha=0.5 canonical setting),
---   §5 (empirical speedup).

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "speculative_rejection",
    version = "0.1.0",
    description = "Iterative reward-pruned best-of-N selection "
        .. "(Sun 2024 speculative rejection, adapted to alc.llm call granularity)",
    category = "selection",
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task = T.string:describe("Problem to solve (required, non-empty)"),
                n = T.number:is_optional()
                    :describe("Initial candidate count (default: 8; "
                        .. "implementation choice — paper uses N=1000 for "
                        .. "token-level parallel decoding, but at alc.llm-call "
                        .. "granularity 8 is a practical starting cost)"),
                alpha = T.number:is_optional()
                    :describe("Rejection ratio per round in [0, 1] "
                        .. "(default: 0.5; Sun 2024 §4.1 canonical setting)"),
                rounds = T.number:is_optional()
                    :describe("Number of rejection stages (default: 3; "
                        .. "implementation choice to bound alc.llm_batch cost — "
                        .. "paper runs until decode completes at token level)"),
                reward_rubric = T.string:is_optional()
                    :describe("Rubric injected verbatim into every scoring "
                        .. "prompt (default: generic quality rubric; override "
                        .. "for domain-specific reward)"),
                partial_tokens = T.number:is_optional()
                    :describe("Tokens per initial generation (default: 100; "
                        .. "implementation choice — paper checkpoints at "
                        .. "token positions, not call boundaries)"),
                extend_tokens = T.number:is_optional()
                    :describe("Tokens added per extension round (default: 200; "
                        .. "implementation choice sized to typical continuation "
                        .. "budget between rejection checkpoints)"),
            }),
            result = T.shape({
                selected = T.string:describe("The winning full completion"),
                candidates_initial = T.number:describe("Initial candidate count"),
                candidates_final = T.number:describe(
                    "Number of candidates surviving the final rejection round"),
                rejection_history = T.array_of(T.shape({
                    round = T.number:describe("1-based rejection round index"),
                    survivors_before = T.number:describe(
                        "Candidate count entering this round's rejection"),
                    survivors_after = T.number:describe(
                        "Candidate count remaining after this round's rejection"),
                    rejected_indices = T.array_of(T.number):describe(
                        "Original 1-based indices (into the initial batch) of "
                            .. "candidates rejected this round"),
                    scores = T.array_of(T.number):describe(
                        "Dense per-survivor score array from this round's "
                            .. "reward pass (0 for unparsed)"),
                })):describe("Ordered per-round rejection records"),
                rationale = T.string:describe(
                    "Final selector's justification for the winning candidate"),
            }),
        },
    },
}

--- Default reward rubric used when the caller omits `ctx.reward_rubric`.
local DEFAULT_REWARD_RUBRIC =
    "Correctness and factual accuracy; on-task focus and completeness; "
    .. "clarity and directness; coherence of the partial or full response; "
    .. "absence of unsupported or fabricated claims."

--- Trim leading/trailing whitespace from a string (nil-safe).
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse the reward LLM's score block into a map `i -> score`.
---
--- Expected best-effort format, one candidate per line:
---   Candidate <i> score: <0-10>
---
--- Unparsed candidates get no entry (caller substitutes 0 so they sort to
--- the bottom and are rejected first).
local function parse_scores(text)
    local scores = {}
    if type(text) ~= "string" then return scores end
    for line in text:gmatch("[^\n]+") do
        local ci, sc = line:match("[Cc]andidate%s+(%d+)%s+score:%s*([%-%d%.]+)")
        if ci and sc then
            local i = tonumber(ci)
            local s = tonumber(sc)
            if i and s then scores[i] = s end
        end
    end
    return scores
end

--- Given per-candidate scores and a rejection ratio alpha, return
--- (survivor_indices, rejected_indices) as arrays of 1-based indices into
--- the input, both in ascending original order.
---
--- Semantics:
---   alpha <= 0     -> keep all
---   alpha >= 1     -> keep exactly 1 (top scorer)
---   otherwise      -> keep = max(1, ceil(n * (1 - alpha)))
---
--- Ties are broken by ascending original index (stable), so the identity of
--- kept candidates is deterministic in tests.
local function reject_bottom_alpha(scores, alpha)
    local n = #scores
    if n == 0 then return {}, {} end

    local keep_count
    if alpha <= 0 then
        keep_count = n
    elseif alpha >= 1 then
        keep_count = 1
    else
        keep_count = math.ceil(n * (1 - alpha))
        if keep_count < 1 then keep_count = 1 end
        if keep_count > n then keep_count = n end
    end

    -- Sort indices by score desc, ties broken by index asc.
    local idx = {}
    for i = 1, n do idx[i] = i end
    table.sort(idx, function(a, b)
        if scores[a] ~= scores[b] then
            return scores[a] > scores[b]
        end
        return a < b
    end)

    local kept = {}
    for k = 1, keep_count do
        kept[idx[k]] = true
    end

    local survivors, rejected = {}, {}
    for i = 1, n do
        if kept[i] then
            survivors[#survivors + 1] = i
        else
            rejected[#rejected + 1] = i
        end
    end
    return survivors, rejected
end

--- Build the initial-generation batch (round 1).
local function build_initial_batch(task, n, partial_tokens)
    local batch = {}
    for i = 1, n do
        batch[i] = {
            prompt = string.format(
                "Task: %s\n\nBegin your response. Write approximately %d tokens "
                    .. "as an opening; you may be asked to continue in a later round.",
                task, partial_tokens
            ),
            system = string.format(
                "You are candidate generator #%d. Produce a high-quality, "
                    .. "coherent response. Take a distinctive approach so that "
                    .. "candidates differ from one another.",
                i
            ),
            max_tokens = partial_tokens,
        }
    end
    return batch
end

--- Build the extension batch for round r > 1.
local function build_extend_batch(task, survivors, extend_tokens)
    local batch = {}
    for i, s in ipairs(survivors) do
        batch[i] = {
            prompt = string.format(
                "Task: %s\n\nPartial response so far:\n%s\n\n"
                    .. "Continue writing from where this leaves off, adding "
                    .. "approximately %d more tokens. Do NOT restart; do NOT "
                    .. "summarize what came before; just continue the response.",
                task, s.text, extend_tokens
            ),
            max_tokens = extend_tokens,
        }
    end
    return batch
end

--- Build the scoring (reward) prompt for a round.
local function build_scoring_prompt(task, survivors, reward_rubric)
    local listing = ""
    for i, s in ipairs(survivors) do
        listing = listing .. string.format("[Candidate %d]\n%s\n\n", i, s.text)
    end
    return string.format(
        "Task: %s\n\n"
            .. "Candidates (partial or full responses):\n%s"
            .. "Rubric (scoring criteria):\n%s\n\n"
            .. "Score EACH candidate from 0 to 10 against the rubric.\n"
            .. "Output EXACTLY this format, one line per candidate, in order:\n"
            .. "Candidate <i> score: <0-10>",
        task, listing, reward_rubric
    )
end

--- Build the final selector prompt.
local function build_selector_prompt(task, survivors)
    local listing = ""
    for i, s in ipairs(survivors) do
        listing = listing .. string.format("[Candidate %d]\n%s\n\n", i, s.text)
    end
    return string.format(
        "Task: %s\n\n"
            .. "Final candidates (survivors of iterative reward rejection):\n%s"
            .. "Select the single best candidate. Output EXACTLY:\n"
            .. "SELECTED: <candidate number>\n"
            .. "RATIONALE: <one-paragraph justification>",
        task, listing
    )
end

--- Parse the final selector's SELECTED / RATIONALE block.
local function parse_selector(text)
    local selected_idx, rationale = nil, nil
    if type(text) ~= "string" then return nil, nil end
    for line in text:gmatch("[^\n]+") do
        local sel = line:match("SELECTED:%s*(%d+)")
        if sel then selected_idx = tonumber(sel) end
        local rat = line:match("RATIONALE:%s*(.+)")
        if rat then rationale = trim(rat) end
    end
    return selected_idx, rationale
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task
    if type(task) ~= "string" or task:match("^%s*$") then
        error("ctx.task is required (non-empty string)")
    end
    local n = ctx.n or 8
    local alpha = ctx.alpha or 0.5
    local rounds = ctx.rounds or 3
    local reward_rubric = ctx.reward_rubric or DEFAULT_REWARD_RUBRIC
    local partial_tokens = ctx.partial_tokens or 100
    local extend_tokens = ctx.extend_tokens or 200

    -- Round 1: initial-generation batch.
    local initial = alc.llm_batch(build_initial_batch(task, n, partial_tokens))

    -- Survivors carry a stable `original_index` so rejection_history refers
    -- to the initial batch identity across rounds.
    local survivors = {}
    for i = 1, #initial do
        survivors[i] = { original_index = i, text = tostring(initial[i]) }
    end

    local rejection_history = {}

    for r = 1, rounds do
        if r > 1 then
            local extensions = alc.llm_batch(
                build_extend_batch(task, survivors, extend_tokens))
            for i = 1, #survivors do
                survivors[i].text = survivors[i].text .. tostring(extensions[i] or "")
            end
        end

        -- Reward pass: single alc.llm scores every current survivor.
        local scoring_out = alc.llm(
            build_scoring_prompt(task, survivors, reward_rubric),
            {
                system = "You are a rigorous reward model. Judge strictly "
                    .. "against the provided rubric and follow the output format exactly.",
                max_tokens = 100 + 20 * #survivors,
            }
        )
        local scores_map = parse_scores(scoring_out)
        local scores = {}
        for i = 1, #survivors do
            scores[i] = scores_map[i] or 0
        end

        local survivor_local, rejected_local = reject_bottom_alpha(scores, alpha)

        local rejected_original = {}
        for _, li in ipairs(rejected_local) do
            rejected_original[#rejected_original + 1] = survivors[li].original_index
        end

        rejection_history[#rejection_history + 1] = {
            round = r,
            survivors_before = #survivors,
            survivors_after = #survivor_local,
            rejected_indices = rejected_original,
            scores = scores,
        }

        local next_survivors = {}
        for _, li in ipairs(survivor_local) do
            next_survivors[#next_survivors + 1] = survivors[li]
        end
        survivors = next_survivors

        if alc.log then
            alc.log("info", string.format(
                "speculative_rejection: round %d, %d -> %d survivors",
                r, rejection_history[#rejection_history].survivors_before,
                #survivors))
        end
    end

    -- Final selector: one alc.llm call over the final survivors (may be one
    -- candidate; still called so the caller receives a rationale).
    local selector_out = alc.llm(
        build_selector_prompt(task, survivors),
        {
            system = "You are the final selector. Choose the strongest response "
                .. "and briefly justify the choice.",
            max_tokens = 400,
        }
    )
    local selected_idx, rationale = parse_selector(selector_out)
    if not selected_idx or not survivors[selected_idx] then
        selected_idx = 1
    end

    ctx.result = {
        selected = (survivors[selected_idx] and survivors[selected_idx].text) or "",
        candidates_initial = n,
        candidates_final = #survivors,
        rejection_history = rejection_history,
        rationale = rationale or trim(selector_out),
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    trim = trim,
    parse_scores = parse_scores,
    reject_bottom_alpha = reject_bottom_alpha,
    build_initial_batch = build_initial_batch,
    build_extend_batch = build_extend_batch,
    build_scoring_prompt = build_scoring_prompt,
    build_selector_prompt = build_selector_prompt,
    parse_selector = parse_selector,
    DEFAULT_REWARD_RUBRIC = DEFAULT_REWARD_RUBRIC,
}

-- Malli-style self-decoration: wrapper asserts input/result against
-- M.spec.entries.run shapes when ALC_SHAPE_CHECK=1 (passthrough otherwise).
M.run = S.instrument(M, "run")

return M
