--- E2E: aot (Atom of Thoughts, Teng et al. NeurIPS 2025).
---
--- Run: agent-block -s scripts/e2e/aot.lua -p .
---
--- Flow: Markov DAG decomposition + contraction — decompose into sub-
---   questions with dependencies, contract independent ones into the
---   remaining work, iterate until depth budget, then solve.
---
--- Graders:
---   * agent_ok                — agent block terminated normally
---   * max_tokens(150000)      — budget guard (multiple decompose + contract + solve)
---   * output_present          — final report non-empty
---   * decompose_marker        — DAG / subquestion structure surfaced in report
---   * final_answer_marker     — final answer surfaced in report

package.path = "scripts/e2e/?.lua;" .. package.path
local common = require("common")

local params = {
    task             = "Alice has 12 apples and gives half to Bob. Bob gives 2 of those to Carol. How many apples does each person end up with?",
    max_depth        = 1,
    decompose_tokens = 400,
    contract_tokens  = 300,
    solve_tokens     = 200,
}

local prompt = string.format([[
Use algocline to run the aot (Atom of Thoughts) package on a multi-step
question.

Call alc_advice with:
- package: "aot"
- entry: "run"
- task: %q
- opts: {
    max_depth        = %d,
    decompose_tokens = %d,
    contract_tokens  = %d,
    solve_tokens     = %d,
  }

Each alc.llm call inside the package returns status "needs_response" — reply
through alc_continue with a genuine response.

Phase 1 (decomposition): the verifier prompt asks for STRICTLY VALID JSON
  in the shape:
  {"subquestions": [
    {"id": 1, "text": "...", "depend": []},
    {"id": 2, "text": "...", "depend": [1]}
  ]}
  Respond with exactly that JSON shape — no preamble, no markdown fence.

Phase 2 (contract): the package gives you independent and dependent sub-
  questions; produce ONE new self-contained question that folds the
  independent ones in as known conditions.

Phase 3 (solve): produce the concise final answer.

When the run completes, report DIRECTLY from the alc_advice payload:
1. The final answer (e.g. "Alice: 6, Bob: 4, Carol: 2")
2. The number of contraction iterations actually executed (depth_used)
3. The initial depth budget D returned by GetMaxPathLength

IMPORTANT:
- Do NOT modify the opts from the values above.
- Keep decomposition JSON minimal (2-3 subquestions max).
- Do NOT call alc_status, alc_log_view, or other diagnostic tools.
]],
    params.task,
    params.max_depth,
    params.decompose_tokens,
    params.contract_tokens,
    params.solve_tokens
)

common.run({
    name           = "aot",
    prompt         = prompt,
    params         = params,
    max_iterations = 25,
    graders = {
        common.grader_agent_ok(),
        common.grader_max_tokens(150000),
        {
            name = "output_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = result.content or ""
                if #c < 50 then
                    return false, "agent content too short — aot output likely missing"
                end
                return true, nil
            end,
        },
        {
            name = "decompose_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("subquestion", 1, true)
                    or c:find("decompos", 1, true)
                    or c:find("depth", 1, true)
                    or c:find("dag", 1, true)
                then
                    return true, nil
                end
                return false, "decompose / depth marker not surfaced in report"
            end,
        },
        {
            name = "final_answer_marker_present",
            check = function(result)
                if not result.ok then return false, "agent failed" end
                local c = (result.content or ""):lower()
                if c:find("final answer", 1, true)
                    or c:find("answer", 1, true)
                    or c:find("alice", 1, true)
                then
                    return true, nil
                end
                return false, "final answer not surfaced in report"
            end,
        },
    },
})
