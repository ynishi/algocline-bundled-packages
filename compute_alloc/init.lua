--- compute_alloc — Compute-Optimal Test-Time Scaling Allocation
---
--- Meta-strategy that dynamically selects the optimal reasoning method
--- and budget allocation based on problem difficulty. Implements the key
--- finding from Snell et al. (ICLR 2025): "scaling test-time compute
--- optimally can be more effective than scaling model parameters."
---
--- Key difference from orch_escalate / router_daao:
---   orch_escalate — fixed 3-level cascade (quick → structured → thorough).
---                   Always starts light and escalates linearly.
---   router_daao   — classifies difficulty and routes to a strategy name.
---                   Classification only; doesn't allocate compute budget.
---   compute_alloc — estimates difficulty, then selects from {parallel, sequential,
---                   hybrid} paradigms AND allocates token budget across them.
---                   Uses existing AlgoCline packages as components.
---                   Key insight: the optimal method CHANGES with difficulty level.
---                   Easy=single-shot, Medium=parallel(sc/usc), Hard=sequential(reflect)+verify.
---
--- Based on: Snell et al., "Scaling LLM Test-Time Compute Optimally can be
--- More Effective than Scaling Model Parameters" (ICLR 2025, arXiv:2408.03314)
--- Also: TTS Survey (arXiv:2503.24235, 2025)
---
--- Usage:
---   local ca = require("compute_alloc")
---   return ca.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.budget: Total token budget hint ("low"|"medium"|"high", default: "medium")
--- ctx.strategies: Custom strategy map (overrides defaults)
--- ctx.gen_tokens: Max tokens per LLM call (default: 400)

local S = require("alc_shapes")
local T = S.T

local M = {}

---@type AlcMeta
M.meta = {
    name = "compute_alloc",
    version = "0.1.0",
    description = "Compute-optimal test-time scaling — dynamically selects "
        .. "reasoning method (parallel/sequential/hybrid) and budget allocation "
        .. "based on problem difficulty. Uses existing packages as components.",
    category = "orchestration",
}

---@type AlcSpec
M.spec = {
    entries = {
        run = {
            input = T.shape({
                task       = T.string:describe("The problem to solve"),
                budget     = T.string:is_optional():describe("Budget hint: 'low' | 'medium' | 'high' (default: 'medium')"),
                strategies = T.table:is_optional():describe("Custom difficulty→strategy map (overrides DEFAULT_STRATEGIES)"),
                gen_tokens = T.number:is_optional():describe("Max tokens per LLM call (default: 400)"),
            }),
            result = T.shape({
                answer          = T.string:describe("Final answer produced by the selected paradigm"),
                difficulty      = T.string:describe("Classified difficulty: 'easy' | 'medium' | 'hard' | 'very_hard'"),
                strategy        = T.string:describe("Selected strategy name (e.g., 'direct', 'parallel', 'sequential', 'hybrid')"),
                paradigm        = T.string:describe("Execution paradigm: 'single' | 'parallel' | 'sequential' | 'hybrid'"),
                candidates      = T.array_of(T.string):is_optional():describe("Parallel candidates (set only for parallel / hybrid paradigms)"),
                total_llm_calls = T.number:describe("Total LLM calls (classification + execution)"),
            }),
        },
    },
}

--- Difficulty levels and their default strategy mappings.
--- Based on the TTS compute-optimal frontier findings:
---   Easy tasks  → single-shot is sufficient (waste to do more)
---   Medium tasks → parallel sampling + selection (sc/usc style)
---   Hard tasks  → sequential refinement + verification (reflect + verify)
---   Very hard   → tree search or full hybrid (MCTS-style)
local DEFAULT_STRATEGIES = {
    easy = {
        name = "direct",
        description = "Single-shot — sufficient for straightforward tasks",
        paradigm = "single",
    },
    medium = {
        name = "parallel",
        description = "Parallel sampling + consistency selection (USC-style)",
        paradigm = "parallel",
        n_samples = 3,
    },
    hard = {
        name = "sequential",
        description = "Sequential refinement with verification",
        paradigm = "sequential",
        max_rounds = 2,
    },
    very_hard = {
        name = "hybrid",
        description = "Parallel candidates + sequential refinement + verification",
        paradigm = "hybrid",
        n_samples = 3,
        max_refine = 1,
    },
}

--- Classify problem difficulty via a single LLM call.
--- Returns: "easy", "medium", "hard", or "very_hard"
local function classify_difficulty(task)
    local raw = alc.llm(
        string.format(
            "Classify the difficulty of this task for an AI system:\n\n"
                .. "Task: %s\n\n"
                .. "Consider:\n"
                .. "- Number of reasoning steps required\n"
                .. "- Need for specialized knowledge\n"
                .. "- Ambiguity or complexity of constraints\n"
                .. "- Risk of error propagation\n\n"
                .. "Classify as exactly one of: EASY, MEDIUM, HARD, VERY_HARD\n"
                .. "Then one sentence justification.",
            task
        ),
        {
            system = "You are a task difficulty classifier. Be calibrated: "
                .. "most factual Q&A is EASY, multi-step reasoning is MEDIUM, "
                .. "complex math/logic is HARD, open research problems are VERY_HARD. "
                .. "Reply with the classification first.",
            max_tokens = 80,
        }
    )

    if raw:match("VERY_HARD") then return "very_hard" end
    if raw:match("HARD") then return "hard" end
    if raw:match("MEDIUM") then return "medium" end
    return "easy"
end

--- Execute direct (single-shot) strategy.
local function exec_direct(task, gen_tokens)
    local answer = alc.llm(
        string.format("Task: %s\n\nProvide a thorough answer.", task),
        {
            system = "You are an expert. Give a clear, accurate response.",
            max_tokens = gen_tokens,
        }
    )
    return { answer = answer, llm_calls = 1 }
end

--- Execute parallel strategy (USC-style: sample N, select most consistent).
local function exec_parallel(task, strategy, gen_tokens)
    local n = strategy.n_samples or 3
    local candidates = {}

    for i = 1, n do
        candidates[i] = alc.llm(
            string.format(
                "Task: %s\n\nApproach #%d: Provide a thorough answer.",
                task, i
            ),
            {
                system = string.format(
                    "You are expert #%d. Give a careful, thorough response "
                        .. "using a distinctive approach.", i
                ),
                max_tokens = gen_tokens,
            }
        )
    end

    -- USC-style selection
    local candidates_text = ""
    for i, c in ipairs(candidates) do
        candidates_text = candidates_text .. string.format(
            "=== Response %d ===\n%s\n\n", i, c
        )
    end

    local selection = alc.llm(
        string.format(
            "Question: %s\n\n%d responses:\n\n%s"
                .. "Which response is most consistent with the majority? "
                .. "State the response number and provide the final answer.",
            task, n, candidates_text
        ),
        {
            system = "Select the response most consistent with overall consensus. "
                .. "Provide the selected answer.",
            max_tokens = gen_tokens,
        }
    )

    return {
        answer = selection,
        candidates = candidates,
        llm_calls = n + 1,
    }
end

--- Execute sequential strategy (reflect-style + step verification).
local function exec_sequential(task, strategy, gen_tokens)
    local max_rounds = strategy.max_rounds or 2

    -- Initial generation
    local draft = alc.llm(
        string.format("Task: %s\n\nSolve step by step.", task),
        {
            system = "You are a methodical reasoner. Show clear steps.",
            max_tokens = gen_tokens,
        }
    )
    local llm_calls = 1

    for _ = 1, max_rounds do
        -- Verify + critique
        local critique = alc.llm(
            string.format(
                "Task: %s\n\nCurrent solution:\n%s\n\n"
                    .. "Verify each reasoning step. Identify any errors, "
                    .. "unjustified leaps, or missing steps.\n"
                    .. "If the solution is correct, output: VERIFIED_CORRECT",
                task, draft
            ),
            {
                system = "You are a rigorous verifier. Check each step for "
                    .. "correctness. Be specific about errors.",
                max_tokens = 300,
            }
        )
        llm_calls = llm_calls + 1

        if critique:match("VERIFIED_CORRECT") then
            break
        end

        -- Revise based on critique
        draft = alc.llm(
            string.format(
                "Task: %s\n\nPrevious attempt:\n%s\n\nErrors found:\n%s\n\n"
                    .. "Fix all identified errors and provide a corrected solution.",
                task, draft, critique
            ),
            {
                system = "Fix all identified errors. Preserve correct parts.",
                max_tokens = gen_tokens,
            }
        )
        llm_calls = llm_calls + 1
    end

    return { answer = draft, llm_calls = llm_calls }
end

--- Execute hybrid strategy (parallel + sequential refinement).
local function exec_hybrid(task, strategy, gen_tokens)
    local n = strategy.n_samples or 3
    local max_refine = strategy.max_refine or 1

    -- Phase 1: Parallel candidates
    local candidates = {}
    for i = 1, n do
        candidates[i] = alc.llm(
            string.format("Task: %s\n\nApproach #%d: Solve step by step.", task, i),
            {
                system = string.format("Expert #%d. Be thorough and distinctive.", i),
                max_tokens = gen_tokens,
            }
        )
    end
    local llm_calls = n

    -- Phase 2: Select best candidate
    local candidates_text = ""
    for i, c in ipairs(candidates) do
        candidates_text = candidates_text .. string.format(
            "=== Candidate %d ===\n%s\n\n", i, c
        )
    end

    local best = alc.llm(
        string.format(
            "Task: %s\n\n%s"
                .. "Select the best candidate. Explain why, then output the "
                .. "full selected solution.",
            task, candidates_text
        ),
        {
            system = "Select the most correct and complete solution.",
            max_tokens = gen_tokens,
        }
    )
    llm_calls = llm_calls + 1

    -- Phase 3: Sequential refinement on the best
    for _ = 1, max_refine do
        local critique = alc.llm(
            string.format(
                "Task: %s\n\nSolution:\n%s\n\n"
                    .. "Verify each step. If correct, output: VERIFIED_CORRECT",
                task, best
            ),
            {
                system = "Rigorous step-by-step verifier.",
                max_tokens = 300,
            }
        )
        llm_calls = llm_calls + 1

        if critique:match("VERIFIED_CORRECT") then
            break
        end

        best = alc.llm(
            string.format(
                "Task: %s\n\nSolution:\n%s\n\nErrors:\n%s\n\nFix all errors.",
                task, best, critique
            ),
            {
                system = "Fix errors. Preserve correct parts.",
                max_tokens = gen_tokens,
            }
        )
        llm_calls = llm_calls + 1
    end

    return {
        answer = best,
        candidates = candidates,
        llm_calls = llm_calls,
    }
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local strategies = ctx.strategies or DEFAULT_STRATEGIES
    local gen_tokens = ctx.gen_tokens or 400

    -- Budget hint can override difficulty classification
    local budget = ctx.budget or "medium"
    local budget_override = {
        low = "easy",
        medium = nil,   -- use classification
        high = "hard",
    }

    -- Step 1: Classify difficulty
    local difficulty
    if budget_override[budget] then
        difficulty = budget_override[budget]
        alc.log("info", string.format(
            "compute_alloc: budget override → difficulty=%s", difficulty
        ))
    else
        difficulty = classify_difficulty(task)
        alc.log("info", string.format(
            "compute_alloc: classified difficulty=%s", difficulty
        ))
    end

    local strategy = strategies[difficulty]
    if not strategy then
        -- Fallback to medium if unknown difficulty
        strategy = strategies.medium or DEFAULT_STRATEGIES.medium
        difficulty = "medium"
    end

    alc.log("info", string.format(
        "compute_alloc: selected strategy=%s (paradigm=%s)",
        strategy.name, strategy.paradigm
    ))

    -- Step 2: Execute the selected strategy
    local exec_result
    if strategy.paradigm == "single" then
        exec_result = exec_direct(task, gen_tokens)
    elseif strategy.paradigm == "parallel" then
        exec_result = exec_parallel(task, strategy, gen_tokens)
    elseif strategy.paradigm == "sequential" then
        exec_result = exec_sequential(task, strategy, gen_tokens)
    elseif strategy.paradigm == "hybrid" then
        exec_result = exec_hybrid(task, strategy, gen_tokens)
    else
        error("Unknown paradigm: " .. tostring(strategy.paradigm))
    end

    -- +1 for difficulty classification (unless budget override)
    local classification_calls = budget_override[budget] and 0 or 1
    local total_calls = classification_calls + exec_result.llm_calls

    ctx.result = {
        answer = exec_result.answer,
        difficulty = difficulty,
        strategy = strategy.name,
        paradigm = strategy.paradigm,
        candidates = exec_result.candidates,
        total_llm_calls = total_calls,
    }
    return ctx
end

-- Malli-style self-decoration (see alc_shapes/README). inline T.shape
-- for both input and result; wrapper validates in ALC_SHAPE_CHECK=1.
M.run = S.instrument(M, "run")

return M
