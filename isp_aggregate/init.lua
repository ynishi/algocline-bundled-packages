--- isp_aggregate — LLM Aggregation via 2nd-order Belief
---
--- Implements Inverse Surprising Popularity (ISP) and Optimal Weight (OW)
--- aggregation from Zhang et al., "Beyond Majority Voting: LLM Aggregation
--- by Leveraging Higher-Order Information" (arXiv:2510.01499, 2025-10).
---
--- Each agent answers the 1st-order question (which option?) and the
--- 2nd-order question (how do you think other agents will answer?).
--- ISP score: c1(y) / c2_hat(y)  — rewards answers that were more popular
---   than predicted (surprisingly popular, Prelec 2004).
--- OW score:  c1(y) - n*c2_hat(y) — linear variant (paper §3.2).
---
--- Usage:
---   local isp = require("isp_aggregate")
---   return isp.run(ctx)
---
--- ctx.task     (required): Question to ask
--- ctx.options  (required): Array of option strings (e.g. {"A","B","C"})
--- ctx.n        (optional): Number of agents to sample (default: 5)
--- ctx.method   (optional): "isp" or "ow" (default: "isp")
--- ctx.gen_tokens (optional): Max tokens per LLM call (default: 400)

local M = {}

---@type AlcMeta
M.meta = {
    name        = "isp_aggregate",
    version     = "0.1.0",
    description = "LLM aggregation via 2nd-order belief (Inverse Surprising Popularity / Optimal Weight). Zhang et al. 2025, arXiv:2510.01499.",
    category    = "aggregation",
}

local T = require("alc_shapes").T

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string,
                options    = T.array_of(T.string),
                n          = T.number:is_optional(),
                method     = T.one_of({ "isp", "ow" }):is_optional(),
                gen_tokens = T.number:is_optional(),
            }, { open = true }),
            result = "isp_voted",
        },
    },
}

--- Trim leading/trailing whitespace, collapse internal runs, strip trailing punctuation.
--- Preserves original casing.
local function clean_answer(s)
    if type(s) ~= "string" then return "" end
    local t = s:gsub("^%s+", ""):gsub("%s+$", "")
    t = t:gsub("%s+", " ")
    t = t:gsub("[%.%!%?%,%;%:]+$", "")
    return t
end

--- Lowercase on top of clean_answer. Used for option matching.
local function normalize(s)
    return clean_answer(s):lower()
end

--- Diversity hints to encourage independent reasoning paths.
local diversity_hints = {
    "Think step by step carefully.",
    "Approach this from first principles.",
    "Consider an alternative perspective.",
    "Work backwards from the expected outcome.",
    "Break this into smaller sub-problems.",
    "Use an analogy to reason about this.",
    "Consider edge cases and exceptions first.",
}

--- Parse verbalized probability output from a 2nd-order LLM response.
--- Looks for content between <probs> and </probs> tags.
--- Pattern: "option_label: float" lines.
--- Returns a table { [option_label] = probability } on success.
--- Returns nil if parsing fails (< 2 matches or total < 0.1).
---
--- @param raw string  raw LLM response
--- @param options table  array of option strings (original casing)
--- @return table|nil
local function parse_probabilities(raw, options)
    if type(raw) ~= "string" then return nil end

    -- Extract content inside <probs>...</probs>
    local inner = raw:match("<probs>%s*(.-)%s*</probs>")
    if not inner then return nil end

    -- Build normalized option lookup: normalized -> original
    local opt_lookup = {}
    for _, opt in ipairs(options) do
        opt_lookup[normalize(opt)] = opt
    end

    local result = {}
    local match_count = 0

    for line in (inner .. "\n"):gmatch("([^\n]+)\n") do
        -- Match "label: float" pattern
        local label, prob_str = line:match("^([^:]+)%s*:%s*([%d%.]+)%s*$")
        if label and prob_str then
            local norm_label = normalize(label)
            local original = opt_lookup[norm_label]
            if original then
                local prob = tonumber(prob_str)
                if prob then
                    result[original] = prob
                    match_count = match_count + 1
                end
            end
        end
    end

    if match_count == 0 then return nil end

    -- Check total probability is meaningful
    local total = 0
    for _, p in pairs(result) do
        total = total + p
    end
    if total < 0.1 then return nil end

    return result
end

--- Compute ISP scores: c1(y) / max(c2_hat(y), epsilon)
---
--- @param c1 table  { [option] = vote_count }
--- @param c2_hat table  { [option] = predicted_probability_mean }
--- @param options table  array of option strings
--- @return table  { [option] = score }
local function score_isp(c1, c2_hat, options)
    local epsilon = 1e-9
    local scores = {}
    for _, opt in ipairs(options) do
        local count = c1[opt] or 0
        local pred  = c2_hat[opt] or 0
        scores[opt] = count / math.max(pred, epsilon)
    end
    return scores
end

--- Compute OW (Optimal Weight) scores: c1(y) - n * c2_hat(y)
--- c1 is raw count, c2_hat is average probability, so scale by n to align units.
---
--- @param c1 table  { [option] = vote_count }
--- @param c2_hat table  { [option] = predicted_probability_mean }
--- @param options table  array of option strings
--- @param n number  number of agents (scale factor)
--- @return table  { [option] = score }
local function score_ow(c1, c2_hat, options, n)
    local scores = {}
    for _, opt in ipairs(options) do
        local count = c1[opt] or 0
        local pred  = c2_hat[opt] or 0
        scores[opt] = count - n * pred
    end
    return scores
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task    = ctx.task    or error("isp_aggregate.run: ctx.task is required", 2)
    local options = ctx.options or error("isp_aggregate.run: ctx.options is required", 2)
    if type(options) ~= "table" or #options == 0 then
        error("isp_aggregate.run: ctx.options must be a non-empty array", 2)
    end

    local n          = ctx.n          or 5
    local method     = ctx.method     or "isp"
    local gen_tokens = ctx.gen_tokens or 400

    local total_llm_calls = 0

    -- Format options for prompts
    local options_str = table.concat(options, ", ")

    -- Collect per-agent results
    local paths = {}

    for i = 1, n do
        local hint = diversity_hints[((i - 1) % #diversity_hints) + 1]

        -- 1st-order: ask the question directly
        local first_order_raw = alc.llm(
            string.format(
                "Question: %s\nOptions: %s\n%s\nPick ONE option. Answer with only the option label.",
                task, options_str, hint
            ),
            {
                system     = "You are a careful reasoner. Answer with only the option label.",
                max_tokens = gen_tokens,
            }
        )
        total_llm_calls = total_llm_calls + 1

        local first_order = clean_answer(first_order_raw)

        -- 2nd-order: ask how other agents will answer (includes agent's own 1st-order answer for context)
        local second_order_raw = alc.llm(
            string.format(
                "Question: %s\nOptions: %s\n\nYou just answered: %s.\nNow predict how the other %d agents will answer the same question.\nFor each option, give your estimated probability of that option being chosen.\nOutput format:\n<probs>\n%s\n</probs>",
                task,
                options_str,
                first_order,
                n - 1,
                table.concat((function()
                    local lines = {}
                    for _, opt in ipairs(options) do
                        lines[#lines + 1] = opt .. ": 0.X"
                    end
                    return lines
                end)(), "\n")
            ),
            {
                system     = "You are predicting how other agents will answer. Output only the <probs> block.",
                max_tokens = gen_tokens,
            }
        )
        total_llm_calls = total_llm_calls + 1

        local second_order_parsed = parse_probabilities(second_order_raw, options)
        if not second_order_parsed then
            local ok = pcall(function()
                alc.log.warn("isp_aggregate: 2nd-order parse failed for agent " .. i .. ", using uniform")
            end)
            if not ok then
                io.stderr:write("isp_aggregate: 2nd-order parse failed for agent " .. i .. ", using uniform\n")
            end
        end

        paths[i] = {
            first_order          = first_order,
            second_order_raw     = second_order_raw,
            second_order_parsed  = second_order_parsed,
        }
    end

    -- Compute c1: 1st-order vote counts
    -- Build normalized option lookup: normalized -> original
    local opt_lookup = {}
    for _, opt in ipairs(options) do
        opt_lookup[normalize(opt)] = opt
    end

    local c1 = {}
    for _, opt in ipairs(options) do
        c1[opt] = 0
    end
    for _, path in ipairs(paths) do
        local norm = normalize(path.first_order)
        local original = opt_lookup[norm]
        if original then
            c1[original] = c1[original] + 1
        end
        -- votes for unrecognized options are silently dropped (invalid vote)
    end

    -- Compute c2_hat: mean of 2nd-order predicted probabilities
    -- uniform fallback for agents that failed to parse
    local uniform_prob = 1 / #options
    local c2_hat = {}
    for _, opt in ipairs(options) do
        c2_hat[opt] = 0
    end
    for _, path in ipairs(paths) do
        local dist = path.second_order_parsed
        for _, opt in ipairs(options) do
            if dist then
                c2_hat[opt] = c2_hat[opt] + (dist[opt] or 0)
            else
                c2_hat[opt] = c2_hat[opt] + uniform_prob
            end
        end
    end
    for _, opt in ipairs(options) do
        c2_hat[opt] = c2_hat[opt] / n
    end

    -- Compute scores
    local scores
    if method == "ow" then
        scores = score_ow(c1, c2_hat, options, n)
    else
        scores = score_isp(c1, c2_hat, options, n)
    end

    -- Find argmax (tie-break: first occurrence in options array)
    local best_opt   = nil
    local best_score = nil
    for _, opt in ipairs(options) do
        local s = scores[opt]
        if best_score == nil or s > best_score then
            best_score = s
            best_opt   = opt
        end
    end

    ctx.result = {
        answer          = best_opt,
        answer_norm     = best_opt and normalize(best_opt) or nil,
        scores          = scores,
        c1              = c1,
        c2_hat          = c2_hat,
        paths           = paths,
        method          = method,
        n_sampled       = n,
        total_llm_calls = total_llm_calls,
    }
    return ctx
end

-- ─── Test hooks ───
M._internal = {
    clean_answer         = clean_answer,
    normalize            = normalize,
    parse_probabilities  = parse_probabilities,
    score_isp            = score_isp,
    score_ow             = score_ow,
}

-- Malli-style self-decoration: wrapper asserts ret.result against
-- M.spec.entries.run.result ("isp_voted") when ALC_SHAPE_CHECK=1.
M.run = require("alc_shapes").instrument(M, "run")

return M
