--- E2E: recipe_evolve_reason
---
--- Run: agent-block -s scripts/e2e/recipe_evolve_reason.lua -p .
---
--- Flow (simple arithmetic, small population):
---   Gen 0: 4 initial reasoning paths        4 LLM calls
---   Gen 1: 6 peer eval + 2 mutate + 2 inherit  10 LLM calls
---   Gen 2: 6 peer eval (final, no reproduce)    6 LLM calls
---   Expected total: ~20 LLM calls
---
---   Uses pop_size=4, max_gen=2, elite_ratio=0.5 for fast smoke test.
---   Easy task (17+25=42) should produce correct answer across generations.

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task = "What is 17 + 25? Answer with just the number.",
    opts = {
        pop_size    = 4,
        max_gen     = 2,
        elite_ratio = 0.5,
        gen_tokens  = 200,
    },
}

local prompt = string.format([[
Use algocline to run the recipe_evolve_reason on a simple arithmetic question.

Call alc_advice with:
- package: "recipe_evolve_reason"
- task: %q
- opts: {
    pop_size = %d,
    max_gen = %d,
    elite_ratio = %s,
    gen_tokens = %d
  }

The recipe maintains a population of %d reasoning slots across %d generations.
Each generation:
1. LLM generates/improves reasoning paths
2. Peer evaluation scores each pair (LLM-as-judge)
3. Elite selection via transition rules
4. Mutation (LLM improves parent reasoning) + knowledge inheritance

Each alc.llm call returns status "needs_response" — reply through
alc_continue with session_id + your genuine answer.

IMPORTANT: You ARE the LLM being queried.
- Reasoning prompts: think step by step, give final answer clearly.
- Evaluation prompts: score each reasoning honestly on 1-10 scale.
  Reply EXACTLY: "Score_A: <n>\nScore_B: <n>"
- Mutation prompts: improve the reasoning, fix errors.
- Insight extraction: return 1-2 sentence key insight.
- Be consistent: 17 + 25 = 42 every time.

When the recipe completes, report:
1. Best answer (the reasoning from the highest-scoring slot)
2. Best slot index and score
3. Number of generations run
4. Total LLM calls
5. Number of lineage edges (parent-child relationships created)
]],
    params.task,
    params.opts.pop_size,
    params.opts.max_gen,
    tostring(params.opts.elite_ratio),
    params.opts.gen_tokens,
    params.opts.pop_size,
    params.opts.max_gen
)

common.run({
    name = "recipe_evolve_reason",
    prompt = prompt,
    params = params,
    max_iterations = 35,
    graders = {
        common.grader_agent_ok(),
        common.grader_content_contains("42", "answer_42"),
        common.grader_max_turns(32),
        common.grader_max_tokens(800000),
        {
            name = "reports_generations",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("generation", 1, true) then
                    return true, nil
                end
                return false, "generation count not reported"
            end,
        },
        {
            name = "reports_llm_calls",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("llm call", 1, true) or c:find("llm_call", 1, true) then
                    return true, nil
                end
                return false, "total LLM calls not reported"
            end,
        },
        {
            name = "reports_lineage",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("lineage", 1, true) or c:find("edge", 1, true) then
                    return true, nil
                end
                return false, "lineage edges not reported"
            end,
        },
    },
})
