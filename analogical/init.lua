--- Analogical — reasoning by self-generated analogies
--- Instead of solving directly, generates relevant analogous problems,
--- solves them, extracts transferable patterns, then applies to the original.
---
--- Based on: Yasunaga et al., "Large Language Models as Analogical Reasoners"
--- (2023, arXiv:2310.01714)
---
--- Usage:
---   local analogical = require("analogical")
---   return analogical.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n_analogies: Number of analogies to generate (default: 3)
--- ctx.domain_hint: Optional domain to draw analogies from

local M = {}

---@type AlcMeta
M.meta = {
    name = "analogical",
    version = "0.1.0",
    description = "Analogical prompting — self-generate analogies, extract patterns, apply to original",
    category = "reasoning",
}

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n_analogies or 3
    local domain_hint = ctx.domain_hint

    -- Phase 1: Generate analogous problems and their solutions
    local analogies = {}

    for i = 1, n do
        local existing_analogies = ""
        if #analogies > 0 then
            for j, a in ipairs(analogies) do
                existing_analogies = existing_analogies .. string.format(
                    "  [%d] %s\n", j, a.problem
                )
            end
        end

        local domain_context = ""
        if domain_hint then
            domain_context = string.format(" Draw from the domain of %s.", domain_hint)
        end

        -- Generate analogous problem
        local analog_problem = alc.llm(
            string.format(
                "Original problem: %s\n\n"
                    .. "%s"
                    .. "Think of a DIFFERENT but structurally similar problem (analogy #%d).%s\n"
                    .. "The analogy should share the same underlying pattern or reasoning structure, "
                    .. "but be from a different context.\n\n"
                    .. "State the analogous problem clearly.",
                task,
                #analogies > 0 and ("Analogies already proposed:\n" .. existing_analogies .. "\nPropose a DIFFERENT analogy.\n\n") or "",
                i, domain_context
            ),
            {
                system = "You are an expert at finding structural analogies. The analogous "
                    .. "problem must share the same reasoning pattern but differ in surface features.",
                max_tokens = 200,
            }
        )

        -- Solve the analogous problem
        local analog_solution = alc.llm(
            string.format(
                "Problem: %s\n\nSolve this step by step.",
                analog_problem
            ),
            {
                system = "You are a clear, methodical problem solver. Show your reasoning.",
                max_tokens = 300,
            }
        )

        analogies[#analogies + 1] = {
            problem = analog_problem,
            solution = analog_solution,
        }
    end

    -- Phase 2: Extract transferable patterns
    local analogy_text = ""
    for i, a in ipairs(analogies) do
        analogy_text = analogy_text .. string.format(
            "Analogy %d:\n  Problem: %s\n  Solution: %s\n\n",
            i, a.problem, a.solution
        )
    end

    local patterns = alc.llm(
        string.format(
            "Original problem: %s\n\n"
                .. "Analogous problems and their solutions:\n%s"
                .. "What common patterns, strategies, or reasoning structures appear "
                .. "across these solutions? Extract the transferable insights.\n\n"
                .. "List the key patterns that can be applied to the original problem.",
            task, analogy_text
        ),
        {
            system = "You are an expert at pattern recognition. Identify the abstract "
                .. "reasoning strategies that transfer across problems.",
            max_tokens = 300,
        }
    )

    -- Phase 3: Apply patterns to solve the original
    local solution = alc.llm(
        string.format(
            "Original problem: %s\n\n"
                .. "Transferable patterns from analogous problems:\n%s\n\n"
                .. "Analogies for reference:\n%s"
                .. "Now solve the original problem by applying these patterns. "
                .. "Show how each pattern maps to the original context.",
            task, patterns, analogy_text
        ),
        {
            system = "You are an expert problem solver. Apply the extracted patterns "
                .. "methodically to the original problem. Be thorough and precise.",
            max_tokens = 600,
        }
    )

    ctx.result = {
        answer = solution,
        analogies = analogies,
        patterns = patterns,
        total_analogies = #analogies,
    }
    return ctx
end

return M
