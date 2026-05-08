--- E2E: decompose (TDAG / HiPlan / Agent-Oriented Planning, 2025).
---
--- Run: agent-block -s scripts/e2e/decompose.lua -p .
---
--- Flow: LLM-driven task decomposition — plan sub-tasks, execute in parallel,
---   merge results into a unified answer.
---
--- Graders:
---   * agent_ok             — agent block terminated normally
---   * max_tokens(200000)   — cumulative budget guard (parallel sub-tasks)
---   * output_present       — final output non-empty
---   * subtask_count_reported — subtask count surfaced in report
---   * merge_marker_present   — merged answer assembled

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task           = "Describe the water cycle: explain evaporation, condensation, and precipitation as separate aspects.",
    max_subtasks   = 3,
    subtask_tokens = 200,
    merge_tokens   = 300,
}

local prompt = string.format([[
Use algocline to run the decompose package on a multi-part task.

Call alc_advice with:
- package: "decompose"
- entry: "run"
- task: %q
- opts: {
    max_subtasks   = %d,
    subtask_tokens = %d,
    merge_tokens   = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Phase 1 (decomposition): respond with a numbered list of sub-tasks, e.g.:
  1. Explain evaporation
  2. Explain condensation
  3. Explain precipitation

Phase 2 (parallel sub-task execution): the package sends all sub-tasks in a
  single batch — respond to each with a short paragraph.

Phase 3 (merge): synthesize the sub-task results into a cohesive answer.

When the run completes, report DIRECTLY from the alc_advice payload:
1. The number of sub-tasks that were decomposed
2. The final merged answer (answer field)
3. subtask_results — whether multiple sub-results are present

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_subtasks,
    params.subtask_tokens,
    params.merge_tokens
)

common.run({
    name           = "decompose",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — decompose output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "subtask_count_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("subtask", 1, true)
                    or c:find("sub-task", 1, true)
                    or c:find("sub_task", 1, true)
                then
                    return true, nil
                end
                return false, "subtask count not surfaced in report"
            end,
        },
        {
            name = "merged_answer_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("answer", 1, true)
                    or c:find("merged", 1, true)
                    or c:find("unified", 1, true)
                    or c:find("water cycle", 1, true)
                then
                    return true, nil
                end
                return false, "merged answer not surfaced in report"
            end,
        },
    },
})
