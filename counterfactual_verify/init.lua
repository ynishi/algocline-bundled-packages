--- counterfactual_verify — Causal faithfulness verification via counterfactual simulation
---
--- Tests whether a reasoning chain is genuinely faithful to its inputs by
--- checking: "If the input changed, would the conclusion change accordingly?"
--- Unlike cove (factual correctness) or verify_first (reverse verification),
--- this detects pattern-matching and memorization by testing causal dependence
--- between premises and conclusions.
---
--- Based on: Hase et al., "Counterfactual Simulation Training for
--- Chain-of-Thought Faithfulness" (arXiv:2602.20710, 2026)
---
--- Pipeline (2 + 3*N LLM calls, N = counterfactuals):
---   Step 1: Solve         — generate CoT + answer for original problem
---   Step 2: Counterfactual — generate N variants by changing one condition each
---   Step 3: Predict       — from original CoT, predict answer under each variant
---   Step 4: Solve CF      — solve each variant independently (parallel)
---   Step 5: Judge         — compare predicted vs actual for each variant
---   Step 6: Verdict       — if unfaithful, re-solve with explicit grounding
---
--- Usage:
---   local cf = require("counterfactual_verify")
---   return cf.run(ctx)
---
--- ctx.task (required): The problem to solve
--- ctx.n_counterfactuals: Number of counterfactual variants (default: 2)
--- ctx.gen_tokens: Max tokens for solving (default: 600)
--- ctx.cf_tokens: Max tokens for counterfactual generation (default: 400)

local M = {}

M.meta = {
    name = "counterfactual_verify",
    version = "0.1.0",
    description = "Counterfactual faithfulness verification — tests whether "
        .. "reasoning causally depends on inputs by simulating condition changes. "
        .. "Detects pattern-matching and unfaithful CoT.",
    category = "validation",
}

--- Parse individual counterfactuals from LLM output.
--- Expects CHANGE: and MODIFIED PROBLEM: markers in any numbered format.
--- Handles the last block (no trailing delimiter) correctly.
local function parse_counterfactuals(raw)
    local cfs = {}

    -- Collect all CHANGE: positions
    local change_positions = {}
    local pos = 1
    while true do
        local s = raw:lower():find("change:", pos, true)
        if not s then break end
        change_positions[#change_positions + 1] = s
        pos = s + 1
    end

    -- For each CHANGE:, extract the block until the next CHANGE: or end
    for i, start in ipairs(change_positions) do
        local block_end = change_positions[i + 1]
            and (change_positions[i + 1] - 1)
            or #raw
        local block = raw:sub(start, block_end)

        local change = block:match("[Cc][Hh][Aa][Nn][Gg][Ee]:%s*(.-)%s*\n")
        -- MODIFIED PROBLEM: captures everything after the marker to block end
        local modified = block:match(
            "[Mm][Oo][Dd][Ii][Ff][Ii][Ee][Dd]%s+[Pp][Rr][Oo][Bb][Ll][Ee][Mm]:%s*(.-)%s*$"
        )

        if change and modified and #modified > 0 then
            cfs[#cfs + 1] = { change = change, modified_task = modified }
        end
    end

    return cfs
end

--- Parse MATCH/MISMATCH verdict.
local function parse_match(text)
    local lower = text:lower()
    if lower:match("mismatch") or lower:match("disagree")
        or lower:match("differ") or lower:match("inconsistent") then
        return false
    end
    return true
end

function M.run(ctx)
    local task = ctx.task or error("ctx.task is required")
    local n_cf = ctx.n_counterfactuals or 2
    local gen_tokens = ctx.gen_tokens or 600
    local cf_tokens = ctx.cf_tokens or 400

    -- ─── Step 1: Solve original with explicit CoT ───
    alc.log("info", "counterfactual_verify: Step 1 — solving original problem")

    local original_cot = alc.llm(
        string.format(
            "Task: %s\n\n"
                .. "Solve step by step. For each reasoning step, explicitly state "
                .. "which input conditions you are relying on and how they lead "
                .. "to your conclusion.",
            task
        ),
        {
            system = "You are a careful reasoner. Make your reasoning chain explicit — "
                .. "for each step, name the specific facts or conditions that justify it. "
                .. "End with a clear final answer.",
            max_tokens = gen_tokens,
        }
    )

    -- ─── Step 2: Generate counterfactual variants ───
    alc.log("info", string.format(
        "counterfactual_verify: Step 2 — generating %d counterfactuals", n_cf
    ))

    local cf_raw = alc.llm(
        string.format(
            "Original problem:\n\"\"\"\n%s\n\"\"\"\n\n"
                .. "Generate exactly %d counterfactual variants of this problem. "
                .. "For each variant, change ONE meaningful condition that should "
                .. "affect the answer. The change must be:\n"
                .. "- Specific (not vague)\n"
                .. "- Consequential (should change the answer)\n"
                .. "- Minimal (change only one thing)\n\n"
                .. "For each variant, provide:\n"
                .. "CHANGE: [what condition is modified]\n"
                .. "MODIFIED PROBLEM: [the complete revised problem text]",
            task, n_cf
        ),
        {
            system = "You generate counterfactual problem variants for testing "
                .. "reasoning faithfulness. Each variant should differ in exactly "
                .. "one condition that meaningfully affects the answer.",
            max_tokens = cf_tokens,
        }
    )

    local counterfactuals = parse_counterfactuals(cf_raw)

    -- Ensure we have counterfactuals to work with
    if #counterfactuals == 0 then
        alc.log("warn", "counterfactual_verify: failed to parse counterfactuals, "
            .. "attempting single-block extraction")
        -- Fallback: treat entire output as one counterfactual
        counterfactuals = { {
            change = "condition modified",
            modified_task = cf_raw,
        } }
    end

    -- Cap at requested number
    while #counterfactuals > n_cf do
        table.remove(counterfactuals)
    end

    alc.log("info", string.format(
        "counterfactual_verify: parsed %d counterfactuals", #counterfactuals
    ))

    -- ─── Step 3: Predict from CoT (what SHOULD change?) ───
    -- ─── Step 4: Solve each counterfactual independently ───
    -- Run predictions and independent solutions in parallel

    alc.log("info", "counterfactual_verify: Steps 3+4 — predict + solve counterfactuals")

    local predictions = alc.map(counterfactuals, function(cf)
        return alc.llm(
            string.format(
                "Original problem:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Original reasoning:\n\"\"\"\n%s\n\"\"\"\n\n"
                    .. "A condition has changed: %s\n\n"
                    .. "Based ONLY on the reasoning chain above (not your own knowledge), "
                    .. "predict: How would the answer change under this modification? "
                    .. "Trace through the reasoning steps and identify which steps "
                    .. "are affected by this change.",
                task, original_cot, cf.change
            ),
            {
                system = "You are testing reasoning faithfulness. Predict the answer "
                    .. "change based ONLY on the given reasoning chain. Do not solve "
                    .. "the problem from scratch — trace through the existing reasoning.",
                max_tokens = gen_tokens,
            }
        )
    end)

    local actuals = alc.map(counterfactuals, function(cf)
        return alc.llm(
            string.format(
                "Solve this problem step by step:\n\n%s",
                cf.modified_task
            ),
            {
                system = "You are an expert problem solver. Solve from scratch. "
                    .. "Show your reasoning and end with a clear final answer.",
                max_tokens = gen_tokens,
            }
        )
    end)

    -- ─── Step 5: Judge match between predicted and actual ───
    alc.log("info", "counterfactual_verify: Step 5 — judging faithfulness")

    local judgments = alc.map(counterfactuals, function(cf, i)
        return alc.llm(
            string.format(
                "A reasoning chain was tested for faithfulness.\n\n"
                    .. "Condition changed: %s\n\n"
                    .. "Predicted answer (from tracing the original reasoning):\n"
                    .. "\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Actual answer (solved independently):\n"
                    .. "\"\"\"\n%s\n\"\"\"\n\n"
                    .. "Do these answers agree on the key conclusion?\n"
                    .. "Reply: MATCH or MISMATCH\n"
                    .. "REASON: [brief explanation]",
                cf.change,
                predictions[i] or "",
                actuals[i] or ""
            ),
            {
                system = "You are a precise judge comparing two answers. "
                    .. "Focus on the key conclusion, not surface wording.",
                max_tokens = 200,
            }
        )
    end)

    -- Parse results
    local results = {}
    local mismatches = {}
    local match_count = 0

    for i, cf in ipairs(counterfactuals) do
        local is_match = parse_match(judgments[i] or "")
        local reason = (judgments[i] or ""):match("[Rr][Ee][Aa][Ss][Oo][Nn]:%s*(.-)$") or ""

        results[#results + 1] = {
            change = cf.change,
            predicted = predictions[i],
            actual = actuals[i],
            match = is_match,
            reason = reason,
        }

        if is_match then
            match_count = match_count + 1
        else
            mismatches[#mismatches + 1] = {
                change = cf.change,
                reason = reason,
            }
        end
    end

    local is_faithful = #mismatches == 0

    alc.log("info", string.format(
        "counterfactual_verify: %d/%d counterfactuals matched — %s",
        match_count, #counterfactuals,
        is_faithful and "FAITHFUL" or "UNFAITHFUL"
    ))

    -- ─── Step 6: Re-solve if unfaithful ───
    local final_answer = original_cot

    if not is_faithful then
        alc.log("info", "counterfactual_verify: Step 6 — re-solving with grounding")

        local mismatch_desc = {}
        for _, m in ipairs(mismatches) do
            mismatch_desc[#mismatch_desc + 1] = string.format(
                "- When '%s' changed: %s", m.change, m.reason
            )
        end

        final_answer = alc.llm(
            string.format(
                "Task: %s\n\n"
                    .. "Previous reasoning was found UNFAITHFUL — the conclusions "
                    .. "did not properly depend on the input conditions:\n\n%s\n\n"
                    .. "Re-solve this problem. For each reasoning step, explicitly "
                    .. "state which specific input conditions it depends on and "
                    .. "how changing those conditions would change the conclusion.",
                task, table.concat(mismatch_desc, "\n")
            ),
            {
                system = "Your previous reasoning was unfaithful (conclusions did not "
                    .. "causally follow from premises). Re-reason carefully, grounding "
                    .. "every step in specific input conditions.",
                max_tokens = gen_tokens,
            }
        )
    end

    ctx.result = {
        answer = final_answer,
        faithful = is_faithful,
        match_count = match_count,
        total_counterfactuals = #counterfactuals,
        original_cot = original_cot,
        counterfactual_results = results,
        mismatches = mismatches,
    }
    return ctx
end

return M
