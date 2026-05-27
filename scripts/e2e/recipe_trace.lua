--- E2E: recipe_trace
---
--- Run: agent-block -s scripts/e2e/recipe_trace.lua -p .
---
--- Flow: wraps recipe_quick_vote with recipe_trace to verify that
--- per-call LLM traces are collected alongside normal recipe output.
---
--- The agent runs recipe_trace.run with recipe_quick_vote as the
--- inner recipe. After completion it should report both the recipe
--- result (answer, outcome, verdict) and the trace data (total_calls,
--- per-call entries with prompt/response/duration_ms).

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local prompt = [[
Use algocline to run a traced recipe execution. Follow these steps:

1. Call alc_run with this Lua code:

```lua
local trace = require("recipe_trace")
local recipe = require("recipe_quick_vote")
return trace.run({
    task = "What is 17 + 25? Answer with just the number.",
    recipe = recipe,
    p0 = 0.5,
    p1 = 0.80,
    alpha = 0.05,
    beta = 0.10,
    min_n = 3,
    max_n = 8,
    gen_tokens = 200,
})
```

2. Each alc.llm call returns status "needs_response" — reply through
   alc_continue with session_id + your genuine answer.

IMPORTANT: You ARE the LLM being queried.
- Reasoning prompts: think carefully and give your final answer clearly.
- Extraction prompts: return ONLY the extracted answer (a number here).
- Be consistent: 17 + 25 = 42 every time.

3. When the recipe completes, report ALL of the following:
   a. Final answer
   b. Outcome (confirmed / rejected / truncated)
   c. trace.total_calls (number of traced LLM calls)
   d. Whether trace.completed is true
   e. Number of entries in trace.calls array
   f. For the first trace call: the prompt substring and response
]]

common.run({
    name = "recipe_trace",
    prompt = prompt,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("42", "answer_42"),
        common.grader_max_turns(22),
        common.grader_max_tokens(500000),
        {
            name = "trace_total_calls_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("total_calls", 1, true) or c:find("total calls", 1, true)
                    or c:find("traced.*calls", 1, false) then
                    return true, nil
                end
                return false, "trace.total_calls not reported"
            end,
        },
        {
            name = "trace_completed_true",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("completed.*true", 1, false)
                    or c:find("trace.*completed", 1, false) then
                    return true, nil
                end
                return false, "trace.completed=true not reported"
            end,
        },
        {
            name = "trace_calls_entries",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if c:find("trace%.calls", 1, false) or c:find("trace.calls", 1, true)
                    or c:find("calls array", 1, true) or c:find("call entries", 1, true)
                    or c:find("entries in", 1, true) then
                    return true, nil
                end
                return false, "trace.calls entries not reported"
            end,
        },
    },
})
