--- coevolve — Challenger-Solver Co-evolution
---
--- Two LLM roles evolve together: Challenger generates problems at the edge
--- of Solver's ability, Solver attempts to solve them. As Solver improves,
--- Challenger generates harder problems. This adversarial co-evolution
--- automatically expands the exploration space — unlike cooperative methods
--- (panel, rstar) that work within a fixed problem scope.
---
--- Based on:
---   [1] Singh et al. "Self-Play for LLM Reasoning: Challenger-Solver
---       Co-evolution" (2025, arXiv:2510.27072)
---       GSM-PLUS: +8.92% via co-evolutionary self-play
---   [2] Faldor et al. "OMNI-EPIC: Open-endedness via Models of human
---       Notions of Interestingness" (ICLR 2025, arXiv:2405.15568)
---   [3] Sukhbaatar et al. "Intrinsic Motivation and Automatic Curricula
---       via Asymmetric Self-Play" (ICLR 2018)
---
--- Pipeline (rounds × (problems × 2 + 2) LLM calls):
---   Seed     — initial problem set (provided or generated)
---   Loop (per round):
---     Solve      — Solver attempts each problem
---     Analyze    — review success/failure patterns
---     Challenge  — Challenger generates new problems targeting weaknesses
---     Calibrate  — adjust difficulty based on success rate
---   Final: Solver answers the original task using accumulated skill
---
--- Usage:
---   local coevolve = require("coevolve")
---   return coevolve.run(ctx)
---
--- ctx.task (required): The domain/problem to explore
--- ctx.seed_problems: Initial problem set (optional, will generate if nil)
--- ctx.rounds: Co-evolution rounds (default: 4)
--- ctx.problems_per_round: Problems Challenger generates per round (default: 3)
--- ctx.difficulty_target: Target success rate for calibration (default: 0.5)
--- ctx.solver_tokens: Max tokens for Solver responses (default: 400)

local M = {}

M.meta = {
    name = "coevolve",
    version = "0.1.0",
    description = "Challenger-Solver Co-evolution — adversarial self-play where "
        .. "Challenger generates problems at Solver's ability boundary and "
        .. "Solver evolves to solve them. Automatic search space expansion.",
    category = "exploration",
}

-- ─── Problem generation ───

--- Generate seed problems for the domain.
local function generate_seeds(task, count)
    local problems = {}
    for i = 1, count do
        local existing = ""
        if #problems > 0 then
            local items = {}
            for j, p in ipairs(problems) do
                items[#items + 1] = string.format("  %d. %s", j, p.text:sub(1, 80))
            end
            existing = "\n\nExisting problems (generate DIFFERENT ones):\n"
                .. table.concat(items, "\n")
        end

        local text = alc.llm(
            string.format(
                "Domain: %s\n%s\n\n"
                    .. "Generate problem #%d for this domain. It should be:\n"
                    .. "- Specific and well-defined\n"
                    .. "- Solvable with reasoning (not trivial, not impossible)\n"
                    .. "- Different from existing problems\n\n"
                    .. "State the problem in 1-3 sentences.",
                task, existing, i
            ),
            {
                system = "You are a problem designer. Create clear, challenging problems.",
                max_tokens = 150,
            }
        )
        problems[#problems + 1] = {
            text = text,
            round = 0,
            difficulty = "medium",
        }
    end
    return problems
end

--- Challenger: generate problems targeting Solver's weaknesses.
local function challenge(task, failure_patterns, success_patterns, difficulty_hint, count)
    local problems = {}

    local failures_text = "None yet"
    if #failure_patterns > 0 then
        local items = {}
        for i, f in ipairs(failure_patterns) do
            items[#items + 1] = string.format("  %d. %s", i, f)
        end
        failures_text = table.concat(items, "\n")
    end

    local successes_text = "None yet"
    if #success_patterns > 0 then
        local items = {}
        for i, s in ipairs(success_patterns) do
            items[#items + 1] = string.format("  %d. %s", i, s)
        end
        successes_text = table.concat(items, "\n")
    end

    for i = 1, count do
        local prev = ""
        if #problems > 0 then
            local items = {}
            for j, p in ipairs(problems) do
                items[#items + 1] = string.format("  %d. %s", j, p.text:sub(1, 80))
            end
            prev = "\n\nAlready generated this round (be DIFFERENT):\n"
                .. table.concat(items, "\n")
        end

        local text = alc.llm(
            string.format(
                "Domain: %s\n\n"
                    .. "You are the CHALLENGER. Your job is to generate problems that "
                    .. "expose the Solver's weaknesses.\n\n"
                    .. "Solver's failure patterns:\n%s\n\n"
                    .. "Solver's success patterns:\n%s\n\n"
                    .. "Difficulty target: %s\n"
                    .. "Generate a problem at the BOUNDARY of the Solver's ability — "
                    .. "hard enough to be challenging, not so hard as to be impossible.%s\n\n"
                    .. "State the problem in 1-3 sentences.",
                task, failures_text, successes_text, difficulty_hint, prev
            ),
            {
                system = "You are an adversarial problem designer. Target weaknesses. "
                    .. "Problems should be solvable but challenging.",
                max_tokens = 150,
            }
        )
        problems[#problems + 1] = {
            text = text,
            round = -1,  -- will be set by caller
            difficulty = difficulty_hint,
        }
    end
    return problems
end

-- ─── Solver ───

--- Solver attempts a problem.
local function solve(task, problem, solver_tokens)
    return alc.llm(
        string.format(
            "Domain: %s\n\n"
                .. "Problem:\n%s\n\n"
                .. "Solve this problem step by step. Be thorough and precise.",
            task, problem.text
        ),
        {
            system = "You are an expert problem solver. Show your reasoning clearly.",
            max_tokens = solver_tokens,
        }
    )
end

--- Judge whether Solver's answer is correct/good.
local function judge(task, problem, answer)
    local verdict_str = alc.llm(
        string.format(
            "Domain: %s\n\n"
                .. "Problem:\n%s\n\n"
                .. "Solver's answer:\n%s\n\n"
                .. "Judge the answer:\n"
                .. "- CORRECT: The answer fully and correctly solves the problem\n"
                .. "- PARTIAL: The answer is on the right track but incomplete or has minor errors\n"
                .. "- WRONG: The answer is fundamentally incorrect or misses the point\n\n"
                .. "Reply with ONE word: CORRECT, PARTIAL, or WRONG.\n"
                .. "Then on the next line, explain in ONE sentence why.",
            task, problem.text, answer
        ),
        {
            system = "You are an impartial judge. Be strict but fair.",
            max_tokens = 60,
        }
    )

    local verdict = "wrong"
    local upper = verdict_str:upper()
    -- Match WRONG first to avoid "INCORRECT" matching "CORRECT"
    if upper:match("WRONG") then
        verdict = "wrong"
    elseif upper:match("PARTIAL") then
        verdict = "partial"
    elseif upper:match("CORRECT") then
        verdict = "correct"
    end

    local reason = verdict_str:match("\n(.+)") or verdict_str

    return verdict, reason
end

--- Analyze patterns in results.
local function analyze_patterns(results)
    local failure_patterns = {}
    local success_patterns = {}

    for _, r in ipairs(results) do
        local summary = r.problem.text:sub(1, 60)
        if r.verdict == "correct" then
            success_patterns[#success_patterns + 1] = summary
        else
            failure_patterns[#failure_patterns + 1] = string.format(
                "%s (verdict: %s, reason: %s)",
                summary, r.verdict, (r.reason or ""):sub(1, 60)
            )
        end
    end

    return failure_patterns, success_patterns
end

-- ─── Main ───

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local rounds = ctx.rounds or 4
    local problems_per_round = ctx.problems_per_round or 3
    local difficulty_target = ctx.difficulty_target or 0.5
    local solver_tokens = ctx.solver_tokens or 400

    -- Phase 1: Seed problems
    local all_results = {}
    local problems

    if ctx.seed_problems and #ctx.seed_problems > 0 then
        problems = {}
        for _, text in ipairs(ctx.seed_problems) do
            problems[#problems + 1] = { text = text, round = 0, difficulty = "medium" }
        end
    else
        problems = generate_seeds(task, problems_per_round)
    end

    local cumulative_failure_patterns = {}
    local cumulative_success_patterns = {}
    local round_stats = {}

    -- Phase 2: Co-evolution loop
    for round = 1, rounds do
        -- Set round on problems
        for _, p in ipairs(problems) do
            if p.round == -1 then p.round = round end
        end

        -- Solver attempts each problem
        local round_results = {}
        local correct_count = 0

        for _, problem in ipairs(problems) do
            local answer = solve(task, problem, solver_tokens)
            local verdict, reason = judge(task, problem, answer)

            if verdict == "correct" then
                correct_count = correct_count + 1
            end

            local result = {
                problem = problem,
                answer = answer,
                verdict = verdict,
                reason = reason,
                round = round,
            }
            round_results[#round_results + 1] = result
            all_results[#all_results + 1] = result
        end

        -- Analyze patterns
        local fail_p, succ_p = analyze_patterns(round_results)
        for _, f in ipairs(fail_p) do
            cumulative_failure_patterns[#cumulative_failure_patterns + 1] = f
        end
        for _, s in ipairs(succ_p) do
            cumulative_success_patterns[#cumulative_success_patterns + 1] = s
        end

        -- Keep patterns bounded
        while #cumulative_failure_patterns > 10 do
            table.remove(cumulative_failure_patterns, 1)
        end
        while #cumulative_success_patterns > 10 do
            table.remove(cumulative_success_patterns, 1)
        end

        local success_rate = correct_count / #problems

        -- Difficulty calibration
        local difficulty_hint
        if success_rate > difficulty_target + 0.2 then
            difficulty_hint = "harder — Solver is finding problems too easy"
        elseif success_rate < difficulty_target - 0.2 then
            difficulty_hint = "easier — Solver is struggling, back off slightly"
        else
            difficulty_hint = "similar — difficulty is well calibrated"
        end

        round_stats[#round_stats + 1] = {
            round = round,
            problems = #problems,
            correct = correct_count,
            success_rate = success_rate,
            difficulty_hint = difficulty_hint,
        }

        alc.log("info", string.format(
            "coevolve: round %d/%d — %d/%d correct (%.0f%%), next: %s",
            round, rounds, correct_count, #problems,
            success_rate * 100, difficulty_hint
        ))

        -- Challenger generates next round's problems (unless last round)
        if round < rounds then
            problems = challenge(
                task,
                cumulative_failure_patterns,
                cumulative_success_patterns,
                difficulty_hint,
                problems_per_round
            )
        end
    end

    -- Phase 3: Final synthesis — Solver answers the original task
    -- using accumulated knowledge from all rounds
    local lessons = ""
    for _, r in ipairs(all_results) do
        if r.verdict == "correct" then
            lessons = lessons .. string.format(
                "  [solved] %s\n", r.problem.text:sub(1, 80)
            )
        else
            lessons = lessons .. string.format(
                "  [failed: %s] %s\n", r.verdict, r.problem.text:sub(1, 80)
            )
        end
    end

    local answer = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "You have been trained through %d rounds of increasingly "
                .. "challenging problems. Here is your performance history:\n%s\n"
                .. "Using everything you learned from these challenges, "
                .. "provide your best, most comprehensive answer to the original task.",
            task, rounds, lessons
        ),
        {
            system = "You are an expert who has been battle-tested through "
                .. "adversarial challenges. Use your accumulated insights.",
            max_tokens = solver_tokens + 200,
        }
    )

    ctx.result = {
        answer = answer,
        round_stats = round_stats,
        total_problems = #all_results,
        total_correct = 0,
        total_partial = 0,
        total_wrong = 0,
        all_results = all_results,
    }

    -- Count totals
    for _, r in ipairs(all_results) do
        if r.verdict == "correct" then
            ctx.result.total_correct = ctx.result.total_correct + 1
        elseif r.verdict == "partial" then
            ctx.result.total_partial = ctx.result.total_partial + 1
        else
            ctx.result.total_wrong = ctx.result.total_wrong + 1
        end
    end

    alc.log("info", string.format(
        "coevolve: complete — %d problems, %d correct, %d partial, %d wrong",
        ctx.result.total_problems, ctx.result.total_correct,
        ctx.result.total_partial, ctx.result.total_wrong
    ))

    return ctx
end

return M
