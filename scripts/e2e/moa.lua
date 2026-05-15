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
    task              = "What is the best way to learn a new programming language quickly?",
    personas          = { "Analyst (logic + rigor)", "Critic (edge cases)" },
    n_layers          = 2,    -- MoA-Lite (Wang 2024 §3 cost-efficient variant)
    proposer_tokens   = 256,
    aggregator_tokens = 384,
}

local prompt = string.format([[
Use algocline to run the moa (Mixture-of-Agents, paper-explicit v0.2.0)
package on a reasoning task.
Paper: Wang et al. 2024 "Mixture-of-Agents Enhances Large Language Model
Capabilities" (arXiv:2406.04692, §2.2 layered aggregation,
§3 MoA-Lite L=2 variant).

Call alc_advice with:
- package: "moa"
- entry: "run"
- task: %q
- opts: {
    personas          = { "Analyst (logic + rigor)", "Critic (edge cases)" },
    n_layers          = %d,
    proposer_tokens   = %d,
    aggregator_tokens = %d,
  }

This uses the non-paper-faithful `personas` alternative path (single
model, persona-rotated proposers) for OSS-callable smoke testing. The
paper-faithful path requires distinct proposer model IDs and is out of
scope for this E2E.

Each alc.llm call inside the package returns status "needs_response" —
reply through alc_continue with a genuine response.

Per layer there are 2 proposer calls (one per persona) followed by 1
aggregator call (Aggregate-and-Synthesize, Wang 2024 Table 1 verbatim).
Total LLM calls = L · (n + 1) = 2 · (2 + 1) = 6.

For proposer calls: provide a concise, genuine answer from that
persona's perspective.

For aggregator calls: produce a synthesized answer that critically
evaluates and integrates the listed proposer responses.

When the run completes, report DIRECTLY from the alc_advice payload:
1. n_proposers — proposers per layer used (should be 2)
2. n_layers — layers executed (should be 2)
3. total_llm_calls — total LLM invocations (should be 6)
4. answer — the final aggregator output from layer L

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep responses concise.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.n_layers,
    params.proposer_tokens,
    params.aggregator_tokens
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
            name = "n_proposers_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("n_proposers", 1, true)
                    or c:find("n proposers", 1, true)
                    or c:find("proposer", 1, true)
                then
                    return true, nil
                end
                return false, "n_proposers not surfaced in report"
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
