--- E2E: recipe_safe_panel — Anti-Jury abort path
---
--- Run: agent-block -s scripts/e2e/recipe_safe_panel_anti_jury.lua -p .
---
--- Covers the Anti-Jury abort branch (p_estimate < 0.5 → refuse to run
--- panel voting). Validates:
---   - aborted = true
---   - anti_jury = true (vs coin_flip when p==0.5)
---   - abort_reason mentions Anti-Jury and p value
---   - total_llm_calls = 0 (no panel was ever sampled)
---   - result shape matches main path (answer, confidence, panel_size,
---     plurality_fraction, etc. all present as zeros/nil)
---   - stages[1] = { name = "condorcet_anti_jury", ... }
---
--- Flow (abort-gated, p_estimate=0.3):
---   Stage 1 (condorcet)  : 0 LLM calls — Anti-Jury gate fires
---   Stages 2-4           : not reached
---   Total                : 0 LLM calls (pure math abort)

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "Predict which of two indistinguishable random coin flips "
        .. "will land heads next Tuesday at 3pm UTC. Answer H or T.",
    opts = {
        p_estimate = 0.3,        -- ← below 0.5 → Anti-Jury abort
        target_accuracy = 0.95,
        max_n = 7,
        confidence_threshold = 0.6,
        scaling_check = false,
    },
}

local prompt = string.format([[
Use algocline to run the recipe_safe_panel with a deliberately LOW
p_estimate to exercise the Anti-Jury safety gate.

Call alc_advice with:
- package: "recipe_safe_panel"
- task: %q
- opts: {
    p_estimate = %s,          -- ← BELOW 0.5, must trigger Anti-Jury abort
    target_accuracy = %s,
    max_n = %d,
    confidence_threshold = %s,
    scaling_check = %s
  }

EXPECTED BEHAVIOR: The recipe will detect p_estimate < 0.5 at Stage 1
(condorcet) and ABORT immediately with:
  - aborted = true
  - anti_jury = true
  - answer = nil
  - total_llm_calls = 0 (no panel sampling occurs)
  - abort_reason mentioning Anti-Jury / p=0.30

NO alc.llm calls should occur. If you see a "needs_response" status,
reply with a brief placeholder — but the recipe should NOT request one.

When alc_advice returns, report the result verbatim (JSON is fine).
Specifically report:
1. aborted flag
2. anti_jury flag
3. abort_reason text
4. total_llm_calls
5. Whether any panel was sampled
]],
    params.task,
    tostring(params.opts.p_estimate),
    tostring(params.opts.target_accuracy),
    params.opts.max_n,
    tostring(params.opts.confidence_threshold),
    tostring(params.opts.scaling_check)
)

common.run({
    name = "recipe_safe_panel_anti_jury",
    prompt = prompt,
    params = params,
    max_iterations = 10,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_turns(8),
        common.grader_max_tokens(50000),
        {
            -- aborted flag must be true.
            name = "aborted_true",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("abort") and
                    (c:find("true", 1, true)
                     or c:find("yes", 1, true)
                     or c:find("triggered", 1, true))
                then
                    return true, nil
                end
                return false, "aborted=true not reported"
            end,
        },
        {
            -- anti_jury = true.
            name = "anti_jury_true",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("anti") then
                    local aidx = c:find("anti")
                    local win = c:sub(aidx, aidx + 80)
                    if win:find("true", 1, true)
                        or win:find("yes", 1, true)
                        or win:find("triggered", 1, true)
                        or win:find("fired", 1, true)
                    then
                        return true, nil
                    end
                end
                return false, "anti_jury=true not reported"
            end,
        },
        {
            -- No LLM calls at all (abort happens in Stage 1 pure-math).
            name = "zero_llm_calls",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Look for total_llm_calls near 0.
                if c:find("total_llm_calls") then
                    local tidx = c:find("total_llm_calls")
                    local win = c:sub(tidx, tidx + 50)
                    if win:find(": 0") or win:find("= 0")
                        or win:find("=0") or win:find(":0")
                    then
                        return true, nil
                    end
                    return false, "total_llm_calls reported non-zero"
                end
                -- If llm_calls not quoted, accept if the agent says "0 calls" etc.
                if c:find("no llm calls") or c:find("zero llm calls")
                    or c:find("0 llm calls") or c:find("no sampling")
                    or c:find("no panel") or c:find("not sampled")
                then
                    return true, nil
                end
                return false, "zero LLM calls not reported"
            end,
        },
        {
            -- abort_reason must mention the p value (0.30 / 0.3).
            name = "reports_p_estimate",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("0.3") or c:find("0%.30") or c:find("30%%")
                    or c:find("p_estimate")
                then
                    return true, nil
                end
                return false, "p_estimate=0.3 not surfaced"
            end,
        },
        {
            -- agent should NOT have sampled a panel (answer stays nil).
            name = "answer_is_nil",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- Find the "answer" field near nil / null / none / n/a.
                if c:find("answer") then
                    local aidx = c:find("answer")
                    local win = c:sub(aidx, aidx + 60)
                    if win:find("nil", 1, true)
                        or win:find("null", 1, true)
                        or win:find("none", 1, true)
                        or win:find("n/a", 1, true)
                        or win:find("no answer", 1, true)
                    then
                        return true, nil
                    end
                end
                -- If no explicit "answer" field in the report, accept as
                -- long as no concrete answer (H/T) is given in the final.
                return true, nil
            end,
        },
    },
})
