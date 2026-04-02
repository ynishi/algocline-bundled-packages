--- orch_nver — N-version Programming Orchestration
--- Execute N parallel variants, evaluate each, select best.
--- Trades cost for quality. Mitigates 29.6% regression rate (SWE-Bench).
---
--- Based on N-version approach from Agentic SE Roadmap (arxiv 2509.06216).
---
--- Usage:
---   local orch = require("orch_nver")
---   return orch.run(ctx)
---
--- ctx.task      (required): Task description
--- ctx.n         (optional): Number of parallel variants (default: 3)
--- ctx.phases    (optional): Phase definitions for each variant's pipeline
--- ctx.selection (optional): "score" | "vote" (default: "score")

local M = {}

--- Expand template variables safely (% in values won't break).
local function expand(template, vars)
    local result = template
    for k, v in pairs(vars) do
        local sv = tostring(v)
        result = result:gsub("{" .. k .. "}", function() return sv end)
    end
    return result
end

---@type AlcMeta
M.meta = {
    name = "orch_nver",
    version = "0.1.0",
    description = "N-version programming: execute N parallel variants, "
        .. "evaluate each, select best. Trades cost for quality. "
        .. "Based on N-version approach from Agentic SE Roadmap (arxiv 2509.06216). "
        .. "Mitigates 29.6% regression rate found in SWE-Bench audits.",
    category = "orchestration",
}

local EVAL_SYSTEM = [[You are an evaluator for software engineering outputs.
Score the following output on a scale of 1-10 based on:
- Correctness: Does it solve the task?
- Completeness: Does it cover all requirements?
- Quality: Is the code/plan clean and well-structured?
- Risk: Are there potential regressions or issues?

Respond with ONLY a JSON object: {"score": N, "reasoning": "brief explanation"}]]

--- Parse JSON from a potentially noisy LLM response.
local function parse_json(raw)
    local ok, decoded = pcall(alc.json_decode, raw)
    if ok and type(decoded) == "table" then
        return decoded
    end
    local json_str = raw:match("%b{}")
    if json_str then
        local ok2, decoded2 = pcall(alc.json_decode, json_str)
        if ok2 and type(decoded2) == "table" then
            return decoded2
        end
    end
    return nil
end

--- Majority vote: find the most common answer by grouping similar outputs.
--- Uses LLM to cluster N outputs into groups and pick the majority.
local function majority_vote(variants, task, total_llm_calls)
    if #variants <= 1 then
        return variants[1] and variants[1].output or "", total_llm_calls
    end

    -- Build summary of all variants for LLM comparison
    local parts = {}
    for i, v in ipairs(variants) do
        -- Truncate long outputs for the vote prompt
        local out = v.output
        if #out > 500 then out = out:sub(1, 500) .. "..." end
        parts[#parts + 1] = string.format("--- Variant %d ---\n%s", i, out)
    end

    local raw = alc.llm(
        string.format(
            "Task: %s\n\nThe following %d variants were produced. "
            .. "Select the variant number that best represents the majority consensus. "
            .. "Respond with ONLY the variant number (e.g., 2).\n\n%s",
            task, #variants, table.concat(parts, "\n\n")
        ),
        { system = "You are a fair judge. Pick the majority answer.", max_tokens = 20 }
    )
    total_llm_calls = total_llm_calls + 1

    local chosen = tonumber(raw:match("%d+")) or 1
    if chosen < 1 or chosen > #variants then chosen = 1 end

    return variants[chosen].output, total_llm_calls
end

---@param ctx AlcCtx
---@return AlcCtx
function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n = ctx.n or 3
    local phases = ctx.phases
    local selection = ctx.selection or "score"

    local total_llm_calls = 0

    -- Phase 1: Generate N variants
    alc.log("info", string.format("nver: generating %d variants", n))

    local variants = {}

    if phases then
        -- Multi-phase: each variant runs through a mini-pipeline
        for i = 1, n do
            local prev = ""
            local phase_outputs = {}
            for _, phase in ipairs(phases) do
                local prompt = expand(phase.prompt, {
                    task = task,
                    prev_output = prev,
                    variant = tostring(i),
                })

                local out = alc.llm(prompt, {
                    system = phase.system or "You are variant #" .. i .. ".",
                    max_tokens = phase.max_tokens or 2000,
                })
                total_llm_calls = total_llm_calls + 1
                phase_outputs[#phase_outputs + 1] = {
                    name = phase.name,
                    output = out,
                }
                prev = out
            end
            variants[i] = {
                variant_id = i,
                output = prev,
                phase_outputs = phase_outputs,
            }
        end
    else
        -- Single prompt: generate N responses
        for i = 1, n do
            local out = alc.llm(
                string.format("Solve this task (variant %d of %d):\n\n%s", i, n, task),
                {
                    system = "You are a senior software engineer. Provide a complete solution.",
                    max_tokens = 3000,
                }
            )
            total_llm_calls = total_llm_calls + 1
            variants[i] = { variant_id = i, output = out }
        end
    end

    -- Phase 2: Selection
    if selection == "vote" then
        alc.log("info", "nver: selecting by majority vote")
        local voted_output
        voted_output, total_llm_calls = majority_vote(variants, task, total_llm_calls)

        ctx.result = {
            status = "completed",
            selected = voted_output,
            method = "vote",
            variants = variants,
            total_llm_calls = total_llm_calls,
        }
        return ctx
    end

    -- Score selection: evaluate each variant
    alc.log("info", "nver: evaluating variants by score")

    local scored = {}
    for _, v in ipairs(variants) do
        local raw = alc.llm(
            string.format("Task: %s\n\nOutput to evaluate:\n%s", task, v.output),
            { system = EVAL_SYSTEM, max_tokens = 100 }
        )
        total_llm_calls = total_llm_calls + 1

        local parsed = parse_json(raw)
        local score = 5  -- fallback
        local reasoning = ""
        if parsed then
            score = tonumber(parsed.score) or 5
            reasoning = parsed.reasoning or ""
        end

        scored[#scored + 1] = {
            variant_id = v.variant_id,
            output = v.output,
            phase_outputs = v.phase_outputs,
            score = score,
            reasoning = reasoning,
        }
    end

    -- Phase 3: Ranking
    table.sort(scored, function(a, b) return a.score > b.score end)

    local best = scored[1]

    ctx.result = {
        status = "completed",
        selected = best.output,
        best_score = best.score,
        best_reasoning = best.reasoning,
        method = "score",
        rankings = scored,
        total_llm_calls = total_llm_calls,
    }

    return ctx
end

return M
