--- triangulate(Triangulate) — agreement-checked verification across N independent solution paths
---
--- Solve the same task N times via deliberately independent methods (alternative
--- decomposition / independent derivation / reverse-computation check) and compare
--- the structured answers. When the paths agree, the answer is confirmed with no
--- verifier call and no extra cost; when they disagree, only the mismatch is fed
--- back into a bounded reconsideration loop, so verification cost is paid only when
--- an error actually exists.
---
--- ## Usage
---
--- ```lua
--- local triangulate = require("triangulate")
--- return triangulate.run({ task = "Compute the number of trailing zeros in 100!." })
--- ```
---
--- ## Algorithm
---
--- 1. **Diversify** — build N method hints. When `ctx.methods` is given, each hint
---    drives one path (path count = `#ctx.methods`). Otherwise a default persona
---    group is used whose hints explicitly induce route independence.
--- 2. **Solve in parallel** — one `alc.llm_batch` round-trip runs all N paths at
---    once. Each path is instructed to end with a single `ANSWER:` marker line so
---    the final answer can be extracted structurally.
--- 3. **Agreement check** — extract each path's `ANSWER:` answer, normalize it
---    (trim / lowercase / whitespace-collapse / trailing-punctuation strip), and
---    test for an exact match across all paths. Agreement → confirmed, stop.
--- 4. **Reconsider on mismatch** — when paths disagree, present the per-path answers
---    (the mismatch points) back to every path and re-solve in another parallel
---    round, up to `ctx.max_rounds` times. If the paths still split, the result is
---    returned with `agreed = false` — the disagreement is surfaced, never hidden.
---
--- ## API
---
--- - `ctx.task`       — string, required. Empty / whitespace-only → error.
--- - `ctx.n`          — number, optional. Independent path count (default 2).
---   Ignored when `ctx.methods` is provided (its length wins).
--- - `ctx.methods`    — string array, optional. Per-path method hints. Omitted →
---   a default persona group that induces route independence.
--- - `ctx.max_rounds` — number, optional. Max reconsideration rounds after the
---   initial solve when paths disagree (default 1). Total solve rounds ≤
---   `1 + max_rounds`.
---
--- Result (`ctx.result`):
--- - `final`       — string, the confirmed answer when agreed; otherwise the final
---   round's plurality answer (path 1 wins ties).
--- - `agreed`      — boolean, whether the final round's paths reached exact match.
--- - `rounds_used` — number, solve rounds executed (initial round counts as 1).
--- - `answers`     — string array, the final round's per-path extracted answers.
--- - `history`     — array of `{ round, results = [ { method, answer, raw } ] }`
---   recording every round's per-path method, extracted answer, and raw response.
---
--- ## Comparison with related packages
---
--- vs `verify_select` (selection): `verify_select` generates N candidates then
--- spends a dedicated verifier pass to *select* the best — verification cost is
--- always paid. This spends no verifier: agreement across independent paths *is*
--- the acceptance signal, so the deterministic (already-agreeing) regime costs
--- only the N parallel solves.
---
--- vs `sc` (self-consistency, majority vote): `sc` samples the *same* method many
--- times and tallies identical answers, so correlated mistakes (a shared reasoning
--- flaw) survive the vote. Triangulation instead varies the *method* per path — the
--- classic surveying idea of fixing a point from independent bearings — so
--- independent routes must coincidentally share an error to agree wrongly, which
--- is far less likely than a majority of same-method samples repeating one mistake.
---
--- ## Caveats
---
--- - Agreement is only as strong as the route independence. With `ctx.methods`
---   omitted the default persona group is engineered to pull paths apart; supplying
---   near-identical `ctx.methods` collapses the guarantee toward `sc`-style
---   correlated voting.
--- - The per-call token budget (`ctx.solve_tokens`, default 500) is an
---   implementation knob left undeclared in `M.spec`; it bounds each path's
---   response and is not part of the stable contract.
--- - On a persistent split the result reports `agreed = false` rather than forcing
---   a winner. Callers that must always act should branch on `agreed` and treat
---   `final` (the plurality / path-1 answer) as a low-confidence fallback.

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "triangulate",
    version = "0.1.0",
    description = "Agreement-checked verification across N independent solution paths",
    category = "validation",
    tags = { "verification", "triangulation", "primitive" },
    alc_shapes_compat = "^0.25",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task = T.string:describe("Task/problem to solve and triangulate (required, non-empty)"),
                n = T.number:is_optional()
                    :describe("Number of independent solution paths (default: 2; implementation "
                        .. "choice — two paths already surface a disagreement while holding cost "
                        .. "at 2x; ignored when ctx.methods is provided, whose length sets the "
                        .. "path count)"),
                methods = T.array_of(T.string):is_optional()
                    :describe("Per-path method hints, one path per entry (path count becomes "
                        .. "#methods). Omitted → a default persona group whose hints induce route "
                        .. "independence (alternative decomposition / independent derivation / "
                        .. "reverse-computation check)"),
                max_rounds = T.number:is_optional()
                    :describe("Maximum reconsideration rounds after the initial solve when paths "
                        .. "disagree (default: 1; implementation choice — one re-convergence "
                        .. "attempt bounds worst-case cost; total solve rounds <= 1 + max_rounds)"),
            }),
            result = T.shape({
                final = T.string:describe("Confirmed answer when agreed; otherwise the final "
                    .. "round's plurality answer (path 1 wins ties)"),
                agreed = T.boolean:describe("True if the final round's paths reached an exact "
                    .. "normalized match"),
                rounds_used = T.number:describe("Solve rounds executed (initial round counts as 1)"),
                answers = T.array_of(T.string)
                    :describe("Final round's per-path extracted answers"),
                history = T.array_of(T.shape({
                    round = T.number:describe("1-based round index"),
                    results = T.array_of(T.shape({
                        method = T.string:describe("The path's assigned method hint"),
                        answer = T.string:describe("The path's extracted ANSWER answer"),
                        raw = T.string:describe("The path's raw LLM response"),
                    })):describe("Per-path records for the round"),
                })):describe("Ordered per-round record of every path's method/answer/raw"),
            }),
        },
    },
}

--- Literal ASCII marker each path emits on its final line. ASCII only: Lua's
--- string.match is byte-oriented, so a multibyte marker can break silently inside
--- a pattern.
local ANSWER_MARKER = "ANSWER:"

--- System persona shared by every path. Reinforces independence and the marker
--- contract so answers stay structurally extractable.
local DEFAULT_SYSTEM =
    "You are one independent solver in a triangulation ensemble. Follow your "
    .. "assigned method strictly and reason independently; do not assume how any "
    .. "other solver approached the task. End your response with a single line of "
    .. "the exact form 'ANSWER: <your final answer>'."

--- Default method hints, chosen to pull solution paths apart (route independence
--- is what makes agreement meaningful — see the docstring Comparison section).
local DEFAULT_METHODS = {
    "Decompose the problem in an unconventional way and solve via that alternative decomposition.",
    "Derive the result through a fully independent route, using a different line of reasoning "
        .. "than a direct approach.",
    "Work backwards: hypothesize a candidate answer and confirm it by reverse-computation "
        .. "(inverse check).",
    "Reformulate the problem in equivalent (dual) terms and solve that reformulation.",
    "Approximate or bound the answer first, then tighten it to an exact result through a "
        .. "separate verification.",
}

--- Trim leading/trailing whitespace from a string (nil-safe).
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Extract a path's final answer from its raw response.
---
--- Scans for a line that *starts* (after optional whitespace) with the ASCII
--- `ANSWER:` marker and returns the trimmed remainder. A plain substring match
--- (raw:find("ANSWER:")) is deliberately avoided — mirroring refine_loop's
--- standalone is_accepted match: text like "MY ANSWER: 42" or "the answer: ..."
--- mid-sentence would otherwise be captured at the wrong span and misread. The
--- marker must own its line. When no marker line exists, the trimmed whole
--- response is returned as a best-effort fallback.
local function parse_answer(raw)
    if type(raw) ~= "string" then return "" end
    for line in raw:gmatch("[^\n]+") do
        local captured = line:match("^%s*" .. ANSWER_MARKER .. "%s*(.*)$")
        if captured then
            return trim(captured)
        end
    end
    return trim(raw)
end

--- Normalize an answer for exact-match comparison: lowercase, collapse whitespace
--- runs to a single space, trim, and strip trailing sentence punctuation.
local function normalize(s)
    if type(s) ~= "string" then return "" end
    s = s:lower()
    s = s:gsub("%s+", " ")
    s = trim(s)
    s = s:gsub("[%.,;:!%?]+$", "")
    return trim(s)
end

--- True (with the shared value) when every normalized answer is identical.
--- An empty list does not agree.
local function answers_agree(normed)
    if #normed == 0 then return false, nil end
    local first = normed[1]
    for i = 2, #normed do
        if normed[i] ~= first then return false, nil end
    end
    return true, first
end

--- Pick the plurality answer's real (un-normalized) text. Frequency is counted
--- over the normalized values; ties resolve to the earliest path (path 1
--- preference). Returns the `answer` field of the earliest occurrence of the
--- winning normalized value.
local function majority_answer(normed, results)
    local count = {}
    local first_idx = {}
    for i = 1, #normed do
        local k = normed[i]
        count[k] = (count[k] or 0) + 1
        if first_idx[k] == nil then first_idx[k] = i end
    end
    local best_first, best_count = nil, -1
    for i = 1, #normed do
        local k = normed[i]
        local c = count[k]
        if c > best_count or (c == best_count and first_idx[k] < best_first) then
            best_first, best_count = first_idx[k], c
        end
    end
    if best_first == nil then return "" end
    return results[best_first].answer
end

--- Normalize ctx.methods into a list of hint strings, or nil when absent/empty.
local function normalize_methods(methods)
    if type(methods) ~= "table" then return nil end
    local out = {}
    for i = 1, #methods do
        out[i] = tostring(methods[i])
    end
    if #out == 0 then return nil end
    return out
end

--- Build N default method hints, cycling the pool with an instance suffix when
--- N exceeds the pool size (keeps every hint distinct).
local function build_default_methods(n)
    local out = {}
    local pool = #DEFAULT_METHODS
    for i = 1, n do
        if i <= pool then
            out[i] = DEFAULT_METHODS[i]
        else
            out[i] = DEFAULT_METHODS[((i - 1) % pool) + 1]
                .. " (independent instance " .. i .. ")"
        end
    end
    return out
end

--- Build the initial solve prompt for a path with its assigned method.
local function build_solve_prompt(task, method)
    return string.format(
        "Task: %s\n\n"
            .. "Assigned method (solve independently using THIS method):\n%s\n\n"
            .. "Work the task with the assigned method. Reason on your own; do not "
            .. "assume how any other solver approached it. Conclude with a single "
            .. "final line of the exact form:\n"
            .. ANSWER_MARKER
            .. " <your final answer>",
        task, method
    )
end

--- Build a human-readable summary of the per-path disagreement (the mismatch
--- points fed back into a reconsideration round).
local function build_disagreement_summary(results)
    local lines = {}
    for i = 1, #results do
        lines[i] = string.format("Path %d (%s) → %s", i, results[i].method, results[i].answer)
    end
    return table.concat(lines, "\n")
end

--- Build the reconsideration prompt for a path after a disagreement.
local function build_reconsider_prompt(task, method, own_answer, summary)
    return string.format(
        "Task: %s\n\n"
            .. "The independent solution paths disagreed. Each path's answer:\n%s\n\n"
            .. "Your assigned method:\n%s\n\n"
            .. "Your previous answer was: %s\n\n"
            .. "Re-derive the answer independently using your assigned method. Treat "
            .. "the disagreement as a signal that at least one path erred; locate the "
            .. "likely mistake, but do NOT simply copy another path — re-check on your "
            .. "own terms. Conclude with a single final line of the exact form:\n"
            .. ANSWER_MARKER
            .. " <your final answer>",
        task, summary, method, own_answer
    )
end

--- Run one parallel solve round over the given per-path prompts.
local function solve_round(prompts, max_tokens)
    local batch = {}
    for i = 1, #prompts do
        batch[i] = { prompt = prompts[i], system = DEFAULT_SYSTEM, max_tokens = max_tokens }
    end
    return alc.llm_batch(batch)
end

--- Collect a round's raw responses into per-path records plus a normalized list.
local function collect_round(raws, method_list, n)
    local results = {}
    local normed = {}
    for i = 1, n do
        local raw = tostring(raws[i] or "")
        local answer = parse_answer(raw)
        results[i] = { method = method_list[i], answer = answer, raw = raw }
        normed[i] = normalize(answer)
    end
    return results, normed
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task
    if type(task) ~= "string" or task:match("^%s*$") then
        error("ctx.task is required (non-empty string)")
    end

    -- Resolve the method list and path count. ctx.methods (if present) wins the
    -- path count; otherwise fall back to ctx.n (default 2) + default hints.
    local method_list = normalize_methods(ctx.methods)
    local n
    if method_list then
        n = #method_list
    else
        n = ctx.n or 2
        if type(n) ~= "number" or n < 1 then n = 2 end
        method_list = build_default_methods(n)
    end

    local max_rounds = ctx.max_rounds or 1
    if type(max_rounds) ~= "number" or max_rounds < 0 then max_rounds = 1 end
    local solve_tokens = ctx.solve_tokens or 500
    local total_rounds = 1 + max_rounds

    -- Round 1: initial parallel solve.
    local prompts = {}
    for i = 1, n do
        prompts[i] = build_solve_prompt(task, method_list[i])
    end
    local raws = solve_round(prompts, solve_tokens)

    local history = {}
    local answers = {}
    local last_results, last_normed = nil, nil
    local agreed = false
    local rounds_used = 0

    for round = 1, total_rounds do
        rounds_used = round
        local results, normed = collect_round(raws, method_list, n)
        last_results, last_normed = results, normed

        history[round] = { round = round, results = results }
        answers = {}
        for i = 1, n do
            answers[i] = results[i].answer
        end

        local ok = answers_agree(normed)
        if ok then
            agreed = true
            if alc.log then
                alc.log("info", string.format("triangulate: agreed at round %d", round))
            end
            break
        end

        -- Not agreed: run another reconsideration round unless the cap is reached.
        if round < total_rounds then
            local summary = build_disagreement_summary(results)
            local reprompts = {}
            for i = 1, n do
                reprompts[i] = build_reconsider_prompt(task, method_list[i], results[i].answer, summary)
            end
            raws = solve_round(reprompts, solve_tokens)
        end
    end

    ctx.result = {
        final = majority_answer(last_normed, last_results),
        agreed = agreed,
        rounds_used = rounds_used,
        answers = answers,
        history = history,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    trim = trim,
    parse_answer = parse_answer,
    normalize = normalize,
    answers_agree = answers_agree,
    majority_answer = majority_answer,
    normalize_methods = normalize_methods,
    build_default_methods = build_default_methods,
    build_solve_prompt = build_solve_prompt,
    build_disagreement_summary = build_disagreement_summary,
    build_reconsider_prompt = build_reconsider_prompt,
    ANSWER_MARKER = ANSWER_MARKER,
    DEFAULT_METHODS = DEFAULT_METHODS,
    DEFAULT_SYSTEM = DEFAULT_SYSTEM,
}

-- Malli-style self-decoration: wrapper asserts input/result against
-- M.spec.entries.run shapes when ALC_SHAPE_CHECK=1 (passthrough otherwise).
M.run = S.instrument(M, "run")

return M
