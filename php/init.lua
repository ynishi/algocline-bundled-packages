--- PHP — Progressive-Hint Prompting
--- Iteratively re-solves the problem using previous answers as hints.
--- Each round feeds the prior answer back as a "hint", allowing the model
--- to self-correct by building on (or departing from) its previous attempt.
--- Converges when two consecutive answers agree.
---
--- Based on: Zheng et al., "Progressive-Hint Prompting Improves Reasoning
--- in Large Language Models" (2023, arXiv:2304.09797)
---
--- Usage:
---   local php = require("php")
---   return php.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.max_rounds: Maximum hint-retry cycles (default: 4)

local M = {}

M.meta = {
    name = "php",
    version = "0.1.0",
    description = "Progressive-Hint Prompting — iterative re-solving with prior answers as hints",
    category = "reasoning",
}

--- Extract the core conclusion from an answer for convergence comparison.
local function extract_conclusion(task, answer)
    return alc.llm(
        string.format(
            "Task: %s\n\nFull answer:\n%s\n\n"
                .. "Extract ONLY the core conclusion or final answer in 1-2 sentences. "
                .. "No reasoning, no explanation — just the bottom-line answer.",
            task, answer
        ),
        { system = "Extract the core conclusion. Be extremely concise.", max_tokens = 100 }
    )
end

--- Check if two conclusions are semantically equivalent.
local function conclusions_match(task, conc_a, conc_b)
    local verdict = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Conclusion A: %s\n"
                .. "Conclusion B: %s\n\n"
                .. "Do these two conclusions reach the SAME answer? "
                .. "Reply SAME or DIFFERENT.",
            task, conc_a, conc_b
        ),
        { system = "Compare conclusions strictly. Reply SAME or DIFFERENT.", max_tokens = 10 }
    )
    return verdict:match("SAME") ~= nil
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local max_rounds = ctx.max_rounds or 4

    -- Round 1: Initial attempt without hints
    local current_answer = alc.llm(
        string.format("Task: %s\n\nSolve this step by step.", task),
        {
            system = "You are a careful problem solver. Show your reasoning.",
            max_tokens = 400,
        }
    )

    local current_conclusion = extract_conclusion(task, current_answer)
    local rounds = { {
        round = 1,
        answer = current_answer,
        conclusion = current_conclusion,
        hint_used = false,
    } }

    -- Subsequent rounds: use previous answer as hint
    for round = 2, max_rounds do
        local hints_text = ""
        for _, r in ipairs(rounds) do
            hints_text = hints_text .. string.format(
                "  Attempt %d conclusion: %s\n", r.round, r.conclusion
            )
        end

        local new_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Previous attempts and their conclusions:\n%s\n"
                    .. "These previous answers serve as HINTS. They may be correct or incorrect.\n"
                    .. "Re-solve the problem from scratch, using the hints to guide (or correct) "
                    .. "your reasoning. If you agree with a previous answer, explain why. "
                    .. "If you disagree, explain what was wrong.",
                task, hints_text
            ),
            {
                system = "You are a careful problem solver. Use the hints to either confirm "
                    .. "or correct your approach. Show your full reasoning.",
                max_tokens = 400,
            }
        )

        local new_conclusion = extract_conclusion(task, new_answer)

        rounds[#rounds + 1] = {
            round = round,
            answer = new_answer,
            conclusion = new_conclusion,
            hint_used = true,
        }

        -- Check convergence: does this match the previous conclusion?
        if conclusions_match(task, current_conclusion, new_conclusion) then
            alc.log("info", string.format(
                "php: converged at round %d — consecutive answers agree", round
            ))
            current_answer = new_answer
            current_conclusion = new_conclusion
            break
        end

        current_answer = new_answer
        current_conclusion = new_conclusion
    end

    ctx.result = {
        answer = current_answer,
        conclusion = current_conclusion,
        rounds = rounds,
        total_rounds = #rounds,
        converged = #rounds >= 2 and conclusions_match(
            task,
            rounds[#rounds - 1].conclusion,
            rounds[#rounds].conclusion
        ),
    }
    return ctx
end

return M
