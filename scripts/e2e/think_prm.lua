--- E2E: think_prm (ThinkPRM, Khalifa et al. 2025).
---
--- Run: agent-block -s scripts/e2e/think_prm.lua -p .
---
--- Flow: zero-shot verifier-as-LLM that produces a per-step thinking
---   chain with \boxed{correct|incorrect} verdicts and aggregates to a
---   solution-level binary verdict (training-free path; force-decode
---   aggregation is out of scope, see pkg ## Caveats).
---
--- Graders:
---   * agent_ok            — agent block terminated normally
---   * max_tokens(100000)  — budget guard (single verifier chain by default)
---   * output_present      — final report non-empty
---   * verdict_marker      — solution-level verdict surfaced in report
---   * boxed_marker        — per-step \boxed verdict surfaced or score reported

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

-- Intentional mid-chain mistake: step 2 should be 14, not 16. The
-- verifier should mark step 2 as incorrect → solution incorrect.
local params = {
    problem = "Tom has 7 apples and Mary has 7 apples. They put them in one basket together with 2 more apples. How many apples are in the basket?",
    solution_steps = {
        "Tom contributes 7 apples.",
        "Together Tom and Mary have 7 + 7 = 16 apples.",
        "They add 2 more, so the basket holds 16 + 2 = 18 apples.",
    },
    n_parallel_cots     = 1,
    max_thinking_tokens = 500,
    temperature         = 0.1,
}

local solution_steps_lua = "{"
for i, s in ipairs(params.solution_steps) do
    solution_steps_lua = solution_steps_lua
        .. (i > 1 and ", " or "")
        .. string.format("%q", s)
end
solution_steps_lua = solution_steps_lua .. "}"

local prompt = string.format([[
Use algocline to run the think_prm package as a step-level verifier.

Call alc_advice with:
- package: "think_prm"
- entry: "run"
- opts: {
    problem             = %q,
    solution_steps      = %s,
    n_parallel_cots     = %d,
    max_thinking_tokens = %d,
    temperature         = %s,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine verifier chain that follows
the requested format EXACTLY:

  Let's verify step by step:
  Step 1: <critique>...The step is \boxed{correct} or \boxed{incorrect}
  Step 2: <critique>...The step is \boxed{correct} or \boxed{incorrect}
  Step 3: <critique>...The step is \boxed{correct} or \boxed{incorrect}

The literal token `\boxed{correct}` or `\boxed{incorrect}` per step is
REQUIRED for the parser to extract verdicts.

Hint: step 2 contains an arithmetic error (7 + 7 should equal 14, not
16), so it should be marked incorrect, and a strict verifier may stop
there per the prompt instructions.

When the run completes, report DIRECTLY from the alc_advice payload:
1. The solution-level binary verdict (correct field)
2. The continuous score (fraction of valid chains judging correct)
3. The per-step verdicts that were extracted

IMPORTANT:
- Do NOT modify the opts from the values above.
- Use the EXACT \boxed{...} format — no markdown, no LaTeX rendering.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.problem,
    solution_steps_lua,
    params.n_parallel_cots,
    params.max_thinking_tokens,
    tostring(params.temperature)
)

common.run({
    name           = "think_prm",
    prompt         = prompt,
    params         = params,
    max_iterations = 15,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(100000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — think_prm output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "verdict_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("verdict", 1, true)
                    or c:find("correct", 1, true)
                    or c:find("incorrect", 1, true)
                    or c:find("score", 1, true)
                then
                    return true, nil
                end
                return false, "verdict / correct / score not surfaced in report"
            end,
        },
        {
            name = "boxed_or_step_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("\\boxed", 1, true)
                    or c:find("boxed", 1, true)
                    or c:find("step", 1, true)
                    or c:find("verdicts", 1, true)
                then
                    return true, nil
                end
                return false, "boxed / step / verdicts marker not surfaced in report"
            end,
        },
    },
})
