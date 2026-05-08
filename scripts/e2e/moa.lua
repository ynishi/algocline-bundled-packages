--- E2E: moa (Mixture-of-Agents, Wang et al. arXiv:2406.04692, 2024).
---
--- Run: agent-block -s scripts/e2e/moa.lua -p .
---
--- Flow: layered multi-agent aggregation — N agents generate independent
---   responses in Layer 1, N agents improve upon all Layer 1 outputs in
---   Layer 2, aggregator synthesizes final answer.
---
--- Graders:
---   * agent_ok              — agent block terminated normally
---   * max_tokens(200000)    — cumulative budget guard (n_agents * n_layers + 1 calls)
---   * output_present        — final output non-empty
---   * n_agents_reported     — n_agents surfaced in report
---   * final_answer_present  — final synthesized answer in output

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task       = "What is the best way to learn a new programming language quickly?",
    n_agents   = 2,
    n_layers   = 2,
    gen_tokens = 200,
    agg_tokens = 300,
}

local prompt = string.format([[
Use algocline to run the moa (Mixture-of-Agents) package on a reasoning task.
Paper: Wang et al. 2024 "Mixture-of-Agents Enhances Large Language Model
Capabilities" (arXiv:2406.04692).

Call alc_advice with:
- package: "moa"
- entry: "run"
- task: %q
- opts: {
    n_agents   = %d,
    n_layers   = %d,
    gen_tokens = %d,
    agg_tokens = %d,
  }

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Layer 1 (independent agents): each agent generates an independent response.
  Provide a concise, genuine answer for each agent's perspective.

Layer 2 (improvement agents): each agent sees ALL Layer 1 responses and
  improves upon them. Provide an improved synthesis.

Aggregation: synthesize the best answer from the final layer outputs.

When the run completes, report DIRECTLY from the alc_advice payload:
1. n_agents — agents per layer used
2. n_layers — layers executed
3. total_calls — total LLM invocations
4. answer — the final synthesized answer

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.n_agents,
    params.n_layers,
    params.gen_tokens,
    params.agg_tokens
)

common.run({
    name           = "moa",
    prompt         = prompt,
    params         = params,
    max_iterations = 30,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(200000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — moa output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "n_agents_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("n_agents", 1, true)
                    or c:find("n agents", 1, true)
                    or c:find("agents", 1, true)
                then
                    return true, nil
                end
                return false, "n_agents not surfaced in report"
            end,
        },
        {
            name = "final_answer_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("answer", 1, true)
                    or c:find("final", 1, true)
                    or c:find("programming", 1, true)
                then
                    return true, nil
                end
                return false, "final synthesized answer not found in report"
            end,
        },
    },
})
