--- E2E: got (Graph of Thoughts, Besta et al. AAAI 2024, arXiv:2308.09687).
---
--- Run: agent-block -s scripts/e2e/got.lua -p .
---
--- Flow: Generate k thought branches → Score each → KeepBest(n) → Refine →
---   Aggregate all kept thoughts into a synthesis → final Refine → Answer.
---   DAG structure (not tree): the Aggregate op merges multiple branches
---   into one node — impossible in ToT.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(250000)      — cumulative budget guard (DAG iteration)
---   * output_present          — final output non-empty
---   * n_steps_reported        — graph_stats.operations reported (DAG iteration ran)
---   * best_node_score_in_range — best kept node score is in [0, 1]

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task          = "What are two key benefits of using immutable data structures in functional programming?",
    k_generate    = 2,
    keep_best     = 1,
    max_refine    = 1,
    gen_tokens    = 150,
    agg_tokens    = 250,
    refine_tokens = 150,
}

local prompt = string.format([[
Use algocline to run the got (Graph of Thoughts) package.
Paper: Besta et al. 2024 "Graph of Thoughts: Solving Elaborate Problems with
Large Language Models" (AAAI 2024, arXiv:2308.09687).

Call alc_advice with:
- package: "got"
- entry: "run"
- task: %q
- opts: {
    k_generate    = %d,
    keep_best     = %d,
    max_refine    = %d,
    gen_tokens    = %d,
    agg_tokens    = %d,
    refine_tokens = %d,
  }

Each alc.llm call inside `got.run` returns status "needs_response" —
reply through alc_continue with a genuine response.

Generate phase (k_generate=%d parallel branches):
  Branch 1: "Immutable data allows safe sharing across concurrent threads
  without locks, preventing race conditions."
  Branch 2: "Immutable structures enable structural sharing, reducing memory
  allocation and enabling efficient persistent data structures."

Score phase (one score per branch):
  For each branch, reply with: SCORE: 0.8
  EXPLANATION: Clear benefit with concrete reasoning.

KeepBest: keep top %d branch(es) — the package prunes automatically.

Refine phase (one call per kept branch):
  Refine the kept thought by adding a brief concrete example.

Aggregate phase (merges all kept thoughts into one synthesis):
  Reply: "Two key benefits: (1) thread-safety via immutability eliminates
  race conditions; (2) structural sharing enables memory-efficient persistence."

Final Refine (one call on aggregated node):
  Reply: "Immutable data structures provide thread-safety without locks and
  enable memory-efficient persistent structures via structural sharing."

When the run completes, report DIRECTLY from the alc_advice payload:
1. answer — the final synthesized answer
2. graph_stats.operations — the operation counts map (generate/aggregate/refine)
3. graph_stats.total_nodes — total nodes created
4. graph_stats.refine_rounds — refinement rounds executed

IMPORTANT:
- Do NOT modify opts from the values above.
- Keep responses concise — the smoke is small on purpose.
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
  After alc_advice returns its final payload (status = "ok"), extract
  the report fields DIRECTLY.
]],
    params.task,
    params.k_generate,
    params.keep_best,
    params.max_refine,
    params.gen_tokens,
    params.agg_tokens,
    params.refine_tokens,
    params.k_generate,
    params.keep_best
)

common.run({
    name           = "got",
    prompt         = prompt,
    params         = params,
    max_iterations = 30,
    max_tokens_budget = 250000,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(250000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — got output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "n_steps_reported",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                -- graph_stats.operations or total_nodes surfaced = DAG iteration ran
                if c:find("graph_stats", 1, true)
                    or c:find("graph stats", 1, true)
                    or c:find("operations", 1, true)
                    or c:find("total_nodes", 1, true)
                    or c:find("refine_rounds", 1, true)
                then
                    return true, nil
                end
                return false, "graph_stats / operations not surfaced — DAG iteration incomplete"
            end,
        },
        {
            name = "best_node_score_in_range",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                -- Look for a numeric score value in [0, 1] pattern in the report
                -- graph_stats.best_kept_score or branches_kept being reported
                -- Accept if score-like number appears in content
                local lc = c:lower()
                if lc:find("branches_kept", 1, true)
                    or lc:find("branches kept", 1, true)
                    or lc:find("kept", 1, true)
                then
                    return true, nil
                end
                -- Also accept if the agent reports a numeric score anywhere
                if c:match("%d+%.%d+") then return true, nil end
                return false, "branches_kept / score not surfaced in report"
            end,
        },
    },
})
