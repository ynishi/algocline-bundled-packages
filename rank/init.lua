--- Rank — generate candidates and select best via pairwise comparison
---
--- Generates N candidate responses, then uses LLM-as-Judge to perform
--- pairwise tournament selection. Produces a winner with reasoning.
---
--- Key difference from ensemble: ensemble uses majority vote (same answer
--- wins), rank uses quality comparison (best answer wins).
---
--- Based on: Best-of-N sampling, LLM-as-Judge (Zheng et al., 2023)
---
--- Usage:
---   local rank = require("rank")
---   return rank.run(ctx)
---
--- ctx.task (required): The task to generate candidates for
--- ctx.candidates: Number of candidates to generate (default: 4)
--- ctx.criteria: Judging criteria (default: "quality, accuracy, completeness")
--- ctx.gen_tokens: Max tokens per candidate (default: 400)

local M = {}

M.meta = {
    name = "rank",
    version = "0.1.0",
    description = "Tournament selection — generate candidates, pairwise LLM-as-Judge ranking",
    category = "selection",
}

--- Pairwise comparison: returns "A" or "B".
local function compare(task, a, b, criteria)
    local verdict = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Evaluate these two responses:\n\n"
                .. "--- Response A ---\n%s\n\n"
                .. "--- Response B ---\n\n%s\n\n"
                .. "Judging criteria: %s\n\n"
                .. "Which response is better? Answer with exactly one word: A or B\n"
                .. "Then one sentence explaining why.",
            task, a, b, criteria
        ),
        {
            system = "You are an impartial judge. Compare strictly on the stated criteria. "
                .. "Respond with A or B first, then a brief justification.",
            max_tokens = 100,
        }
    )

    if verdict:match("^%s*B") or verdict:match("Response B") then
        return "B", verdict
    end
    return "A", verdict
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.candidates or 4
    local criteria = ctx.criteria or "quality, accuracy, completeness"
    local gen_tokens = ctx.gen_tokens or 400

    -- Phase 1: Generate candidates in parallel
    local candidates = alc.map(
        (function()
            local t = {}
            for i = 1, n do t[i] = i end
            return t
        end)(),
        function(i)
            return alc.llm(
                string.format(
                    "Task: %s\n\nProvide your best response.",
                    task
                ),
                {
                    system = string.format(
                        "You are expert #%d. Give a thorough, high-quality response. "
                            .. "Take a distinctive approach.",
                        i
                    ),
                    max_tokens = gen_tokens,
                }
            )
        end
    )

    alc.log("info", string.format("rank: %d candidates generated, starting tournament", n))

    -- Phase 2: Tournament (single elimination)
    local bracket = {}
    for i, c in ipairs(candidates) do
        bracket[i] = { index = i, text = c, wins = 0 }
    end

    local match_log = {}

    while #bracket > 1 do
        local next_round = {}
        for i = 1, #bracket, 2 do
            if i + 1 <= #bracket then
                local a = bracket[i]
                local b = bracket[i + 1]
                local winner_label, reason = compare(task, a.text, b.text, criteria)
                local winner, loser
                if winner_label == "A" then
                    winner = a
                    loser = b
                else
                    winner = b
                    loser = a
                end
                winner.wins = winner.wins + 1
                match_log[#match_log + 1] = {
                    a = a.index,
                    b = b.index,
                    winner = winner.index,
                    reason = reason,
                }
                next_round[#next_round + 1] = winner
            else
                -- Odd one out gets a bye
                next_round[#next_round + 1] = bracket[i]
            end
        end
        bracket = next_round
    end

    local winner = bracket[1]

    ctx.result = {
        best = winner.text,
        best_index = winner.index,
        total_wins = winner.wins,
        candidates = candidates,
        matches = match_log,
    }
    return ctx
end

return M
