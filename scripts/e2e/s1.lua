--- E2E: s1 (Simple test-time scaling, Muennighoff et al. 2025).
---
--- Run: agent-block -s scripts/e2e/s1.lua -p .
---
--- Flow: prompt-level approximation of paper budget forcing — initial
---   thinking pass → N "Wait" extensions → final answer extraction.
---
--- Graders:
---   * agent_ok                    — agent block terminated normally
---   * max_tokens(120000)          — budget guard (initial + extensions + finalize)
---   * output_present              — final report non-empty
---   * extensions_marker_present   — extensions usage surfaced in report
---   * final_answer_marker_present — final answer surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task                = "What is the largest perfect square that is less than 100? Show your reasoning briefly.",
    max_extensions      = 2,
    max_thinking_tokens = 400,
    final_answer_tokens = 200,
}

local prompt = string.format([[
Use algocline to run the s1 package on a reasoning task.

Call alc_advice with:
- package: "s1"
- entry: "run"
- task: %q
- opts: {
    max_extensions      = %d,
    max_thinking_tokens = %d,
    final_answer_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" — reply
through alc_continue with a genuine response.

Phase 1 (initial thinking): respond with a short reasoning trace that stops
  short of stating a final answer.
Phase 2 (Wait extensions): the package will append "Wait" to the trace and
  ask you to continue. Continue reasoning in 1-2 sentences each time.
Phase 3 (finalize): produce a concise final answer (e.g. "81").

When the run completes, report DIRECTLY from the alc_advice payload:
1. The final answer
2. The number of Wait extensions actually executed (extensions_used)
3. Whether the trace accumulated the "Wait" continuation cue

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_extensions,
    params.max_thinking_tokens,
    params.final_answer_tokens
)

common.run({
    name           = "s1",
    prompt         = prompt,
    params         = params,
    max_iterations = 20,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(120000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — s1 output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "extensions_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("extension", 1, true)
                    or c:find("wait", 1, true)
                    or c:find("extensions_used", 1, true)
                then
                    return true, nil
                end
                return false, "extension / Wait usage not surfaced in report"
            end,
        },
        {
            name = "final_answer_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("final answer", 1, true)
                    or c:find("answer", 1, true)
                    or c:find("81", 1, true)
                then
                    return true, nil
                end
                return false, "final answer not surfaced in report"
            end,
        },
    },
})
